import SwiftUI

struct RegisterView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool { password == confirmPassword }
    private var canSubmit: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 8
            && passwordsMatch && !authVM.isLoading
    }

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Text("CREATE ACCOUNT")
                    .font(Theme.Typography.label)
                    .tracking(3)
                    .foregroundStyle(Theme.Colors.amber)
                    .padding(.top, Theme.Spacing.lg)

                VStack(spacing: Theme.Spacing.md) {
                    DarkTextField(placeholder: "Your name", text: $displayName,
                                  isSecure: false, icon: "person.fill")
                    DarkTextField(placeholder: "Email", text: $email,
                                  keyboard: .emailAddress, isSecure: false, icon: "envelope.fill")
                    DarkTextField(placeholder: "Password (8+ chars)", text: $password,
                                  isSecure: true, icon: "lock.fill")
                    DarkTextField(placeholder: "Confirm password", text: $confirmPassword,
                                  isSecure: true, icon: "lock.fill")

                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords don't match")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Button {
                    Task {
                        await authVM.register(email: email, password: password, displayName: displayName)
                    }
                } label: {
                    Group {
                        if authVM.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("CREATE ACCOUNT")
                                .font(Theme.Typography.title)
                                .tracking(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canSubmit ? Theme.Colors.amber : Theme.Colors.surfaceHi)
                    .foregroundStyle(canSubmit ? .black : Theme.Colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                }
                .disabled(!canSubmit)
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: authVM.isAuthenticated) { _, new in
            if new { dismiss() }
        }
    }
}
