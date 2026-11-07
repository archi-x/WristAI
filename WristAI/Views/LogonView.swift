import SwiftUI
import AuthenticationServices

/// The sign-in screen shown before the app unlocks.
///
/// Visual language: deep indigo → violet vertical gradient, a soft glowing
/// waveform mark, and a single white "通过 Apple 登录" button — one obvious
/// action, no form fields, nothing to typo.
struct LogonView: View {
    @Environment(AuthService.self) private var auth

    @State private var isWorking = false
    @State private var showError = false

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 48)

                    logoMark
                        .padding(.bottom, 28)

                    Text("WristAI")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("手腕上的录音笔")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 6)

                    featureList
                        .padding(.top, 36)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 40)

                    signInButton
                        .padding(.horizontal, 32)

                    legalText
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .alert("登录失败", isPresented: $showError) {
            Button("好", role: .cancel) { auth.clearError() }
        } message: {
            Text(auth.lastError ?? "请稍后重试。")
        }
        .onChange(of: auth.lastError) { _, newValue in
            showError = (newValue != nil)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { isWorking = false }
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.07, blue: 0.22),
                Color(red: 0.20, green: 0.11, blue: 0.42),
                Color(red: 0.35, green: 0.15, blue: 0.50)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Logo

    private var logoMark: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.0)],
                        center: .center,
                        startRadius: 4,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 108, height: 108)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.35), radius: 10)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 14) {
            featureRow(icon: "applewatch", title: "手表一键录音", detail: "点按即录，自动传回手机")
            featureRow(icon: "waveform.badge.mic", title: "端侧转录", detail: "音频与文字都不出设备")
            featureRow(icon: "icloud", title: "iCloud 同步", detail: "登录后笔记自动备份到你的云端")
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Sign in

    private var signInButton: some View {
        ZStack {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                isWorking = true
                auth.handle(result: result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isWorking)

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.black)
                    Text("正在登录…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.black.opacity(0.7))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
            }
        }
    }

    private var legalText: some View {
        Text("登录即表示你同意将录音笔记同步到自己的 iCloud 私有数据库。开发者无法读取你的数据。")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
