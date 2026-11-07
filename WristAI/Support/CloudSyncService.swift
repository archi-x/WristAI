import Foundation
import CloudKit
import Observation
import AVFoundation

enum CloudConfig {
    /// Must match the iCloud container declared in `WristAI.entitlements`
    /// and enabled in the target's Signing & Capabilities tab.
    static let containerIdentifier = "iCloud.com.tal.wristai"
    static let recordType = "VoiceNote"
    static let uploadedAssetsKey = "wristai.cloud.uploadedAssets"
}

/// Sync state surfaced in Settings.
enum CloudStatus: Equatable {
    case idle
    case checking
    case offline(String)
    case syncing
    case ready(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle:            return "未同步"
        case .checking:        return "检查中…"
        case .offline:         return "未连接 iCloud"
        case .syncing:         return "同步中…"
        case .ready:           return "已同步"
        case .failed:          return "同步失败"
        }
    }

    var detail: String {
        switch self {
        case .idle:                    return "登录后会自动同步"
        case .checking:                return "正在确认 iCloud 账户状态"
        case .offline(let reason):     return reason
        case .syncing:                 return "正在上传或拉取笔记"
        case .ready(let date):         return "上次同步 \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason):      return reason
        }
    }

    var isBusy: Bool {
        self == .checking || self == .syncing
    }
}

/// A note pulled down from CloudKit, with its audio already copied locally.
struct RemoteNote {
    let note: VoiceNote
    let localAudioURL: URL?
    let updatedAt: Date
}

/// Mirrors `VoiceNote` to the user's **private** CloudKit database.
///
/// Design notes:
/// - The container is created lazily and only after sign-in, so a user who never
///   logs in never touches CloudKit (and an app built without the iCloud
///   entitlement won't crash on launch).
/// - Audio is stored as a `CKAsset` and uploaded only once per note; later edits
///   sync metadata alone.
/// - Every failure maps to a readable Chinese message instead of a raw `CKError`.
@MainActor
@Observable
final class CloudSyncService {

    private(set) var status: CloudStatus = .idle
    private(set) var lastError: String?

    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var uploadedAssets: Set<String>

    init() {
        uploadedAssets = Set(UserDefaults.standard.stringArray(forKey: CloudConfig.uploadedAssetsKey) ?? [])
    }

    private var database: CKDatabase? {
        if container == nil {
            container = CKContainer(identifier: CloudConfig.containerIdentifier)
        }
        return container?.privateCloudDatabase
    }

    // MARK: - Bootstrap

    /// Verify the iCloud account, then pull everything down.
    func bootstrap() async {
        status = .checking
        lastError = nil

        if container == nil {
            container = CKContainer(identifier: CloudConfig.containerIdentifier)
        }
        guard let container else {
            status = .failed("无法创建 iCloud 容器")
            return
        }

        do {
            let account = try await container.accountStatus()
            switch account {
            case .available:
                break
            case .noAccount:
                status = .offline("此设备未登录 iCloud，请前往「设置 → Apple ID」登录")
                return
            case .restricted:
                status = .offline("iCloud 被家长控制或企业策略限制")
                return
            case .couldNotDetermine, .temporarilyUnavailable:
                status = .offline("暂时无法确认 iCloud 状态，请稍后重试")
                return
            @unknown default:
                status = .offline("未知的 iCloud 账户状态")
                return
            }
            // Account is fine — the next pull/push takes the status from here.
            status = .idle
        } catch {
            status = .failed(Self.describe(error))
            return
        }
    }

    /// True when iCloud is reachable, so a pull/push is worth attempting.
    var isUsable: Bool {
        switch status {
        case .offline, .failed: return false
        default: return true
        }
    }

    // MARK: - Push

    /// Upload one note (metadata + audio if it has never been uploaded).
    func push(note: VoiceNote, audioURL: URL?) async {
        guard let database else { return }
        status = .syncing

        do {
            let recordID = CKRecord.ID(recordName: note.id.uuidString)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: CloudConfig.recordType, recordID: recordID)
            }

            record["noteID"] = note.id.uuidString as CKRecordValue
            record["createdAt"] = note.createdAt as CKRecordValue
            record["duration"] = note.duration as CKRecordValue
            record["fileName"] = note.fileName as CKRecordValue
            record["status"] = note.transcriptionStatus.rawValue as CKRecordValue
            record["title"] = note.title as CKRecordValue
            record["transcription"] = (note.transcription ?? "") as CKRecordValue
            record["summary"] = (note.summary ?? "") as CKRecordValue
            record["todosJSON"] = Self.encodeTodos(note.todos) as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue

            if let audioURL,
               FileManager.default.fileExists(atPath: audioURL.path),
               !uploadedAssets.contains(note.id.uuidString) {
                record["audio"] = CKAsset(fileURL: audioURL)
            } else if uploadedAssets.contains(note.id.uuidString) {
                // Preserve the asset already on the server; don't null it out.
                record["audio"] = nil
            }

            try await save(record, in: database)

            if record["audio"] != nil {
                uploadedAssets.insert(note.id.uuidString)
                persistUploadedAssets()
            }

            status = .ready(.now)
        } catch {
            lastError = Self.describe(error)
            status = .failed(lastError ?? "同步失败")
        }
    }

    /// Save, retrying once against the server's copy on a conflict.
    private func save(_ record: CKRecord, in database: CKDatabase) async throws {
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let serverRecord = error.serverRecord else { throw error }
            for key in record.allKeys() where key != "audio" {
                serverRecord[key] = record[key]
            }
            _ = try await database.save(serverRecord)
        }
    }

    // MARK: - Pull

    /// Fetch every note, copying audio assets into the local recordings folder.
    func pullAll(into recordingsDir: URL) async -> [RemoteNote] {
        guard let database else { return [] }
        status = .syncing

        var collected: [RemoteNote] = []

        do {
            let query = CKQuery(recordType: CloudConfig.recordType,
                                predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            var cursor: CKQueryOperation.Cursor?
            repeat {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor)
                } else {
                    page = try await database.records(matching: query, resultsLimit: 100)
                }

                for (_, result) in page.matchResults {
                    guard let record = try? result.get(),
                          let note = Self.note(from: record) else { continue }
                    let audioURL = copyAsset(from: record, fileName: note.fileName, into: recordingsDir)
                    collected.append(RemoteNote(
                        note: note,
                        localAudioURL: audioURL,
                        updatedAt: record["updatedAt"] as? Date ?? note.createdAt
                    ))
                }
                cursor = page.queryCursor
            } while cursor != nil

            status = .ready(.now)
            lastError = nil
            return collected
        } catch {
            lastError = Self.describe(error)
            status = .failed(lastError ?? "拉取失败")
            return collected
        }
    }

    // MARK: - Delete

    func delete(noteID: UUID) async {
        guard let database else { return }
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: noteID.uuidString))
            uploadedAssets.remove(noteID.uuidString)
            persistUploadedAssets()
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — nothing to do.
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: - Mapping

    private static func note(from record: CKRecord) -> VoiceNote? {
        guard let idString = record["noteID"] as? String,
              let id = UUID(uuidString: idString),
              let createdAt = record["createdAt"] as? Date else { return nil }

        return VoiceNote(
            id: id,
            createdAt: createdAt,
            duration: record["duration"] as? Double ?? 0,
            fileName: record["fileName"] as? String ?? "",
            transcriptionStatus: TranscriptionStatus(rawValue: record["status"] as? String ?? "") ?? .pending,
            transcription: (record["transcription"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            summary: (record["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            todos: decodeTodos(record["todosJSON"] as? String),
            title: record["title"] as? String ?? ""
        )
    }

    private func copyAsset(from record: CKRecord, fileName: String, into dir: URL) -> URL? {
        guard !fileName.isEmpty,
              let asset = record["audio"] as? CKAsset,
              let source = asset.fileURL else { return nil }

        let destination = dir.appendingPathComponent(fileName)
        // An existing local file wins: it may already be transcribed.
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }

        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func encodeTodos(_ todos: [TodoItem]) -> String {
        guard let data = try? JSONEncoder().encode(todos) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeTodos(_ json: String?) -> [TodoItem] {
        guard let json, let data = json.data(using: .utf8),
              let todos = try? JSONDecoder().decode([TodoItem].self, from: data) else { return [] }
        return todos
    }

    private func persistUploadedAssets() {
        UserDefaults.standard.set(Array(uploadedAssets), forKey: CloudConfig.uploadedAssetsKey)
    }

    // MARK: - Error mapping

    static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }
        switch ckError.code {
        case .notAuthenticated:
            return "iCloud 账户未登录或授权已失效"
        case .networkUnavailable, .networkFailure:
            return "网络不可用，请在联网后重试"
        case .quotaExceeded:
            return "iCloud 存储空间已满，请清理后重试"
        case .missingEntitlement, .managedAccountRestricted:
            return "此构建缺少 iCloud 能力，请在 Xcode 的 Signing & Capabilities 中开启"
        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return "iCloud 服务繁忙，请稍后重试"
        case .permissionFailure:
            return "没有访问 iCloud 私有数据库的权限"
        default:
            return ckError.localizedDescription
        }
    }
}
