import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var showEmailLogin = false
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: max(geometry.size.height * 0.15, 60))

                    // Logo & Description
                    VStack(spacing: 12) {
                        Text("CareNote")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("ケアマネジャーのための\n音声記録アプリ")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                        .frame(height: max(geometry.size.height * 0.1, 40))

                    // Info Message (network errors, incorrect credentials, etc.)
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Sign In Buttons
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        VStack(spacing: 16) {
                            // Sign in with Apple
                            SignInWithAppleButton(.signIn) { request in
                                viewModel.appleSignInCoordinator.configureRequest(request)
                            } onCompletion: { result in
                                Task {
                                    await viewModel.handleAppleSignInResult(result)
                                }
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50)

                            // Google Sign-In
                            GoogleSignInButton(scheme: .dark, style: .wide) {
                                Task {
                                    await viewModel.signInWithGoogle()
                                }
                            }
                            .frame(height: 50)

                            // Email Login (collapsible)
                            emailLoginSection
                        }
                    }

                    Spacer()
                        .frame(height: 60)
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    @ViewBuilder
    private var emailLoginSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showEmailLogin.toggle()
                }
            } label: {
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                    Text("メールでログイン / Email Login")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
            }

            if showEmailLogin {
                VStack(spacing: 10) {
                    TextField("メールアドレス", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Group {
                            if showPassword {
                                TextField("パスワード", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("パスワード", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task {
                            await viewModel.signInWithEmail(email: email, password: password)
                        }
                    } label: {
                        Text("ログイン")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView(viewModel: AuthViewModel())
}
