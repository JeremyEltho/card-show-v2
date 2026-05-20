import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "rectangle.dashed.badge.record")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Theme.Colors.amber)
                        Text("CARDSHOW PRO")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Card scanner for vendors")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.bottom, 48)

                    VStack(spacing: Theme.Spacing.md) {
                        DarkTextField(placeholder: "Email", text: $email,
                                      keyboard: .emailAddress, isSecure: false,
                                      icon: "envelope.fill")
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }

                        DarkTextField(placeholder: "Password", text: $password,
                                      isSecure: true, icon: "lock.fill")
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await authVM.login(email: email, password: password) }
                            }

                        if let error = authVM.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                            }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await authVM.login(email: email, password: password) }
                        } label: {
                            Group {
                                if authVM.isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("SIGN IN")
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
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    Spacer()

                    Button {
                        showRegister = true
                    } label: {
                        Text("New here? **Create account**")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct DarkTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var icon: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(.password)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .font(Theme.Typography.body)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }
}
