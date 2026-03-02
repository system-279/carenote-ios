import AuthenticationServices
import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

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

            // Error Message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Sign In Button
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { _ in
                    Task {
                        await viewModel.signInWithApple()
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SignInView(viewModel: AuthViewModel())
}
