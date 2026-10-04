import SwiftUI

struct LoginView: View {
    let session: AppSession

    @State private var username = ""
    @State private var password = ""
    @State private var showsPassword = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 760 {
                tabletLayout
            } else {
                phoneLayout
            }
        }
        .background(AppColors.backgroundPrimary)
        .tint(AppColors.accentStrong)
    }

    private var tabletLayout: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            loginPanel
                .frame(width: 494)
                .padding(.trailing, 116)
        }
        .padding(.leading, 96)
    }

    private var phoneLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                compactBrand
                loginPanel
            }
            .padding(AppSpacing.large)
        }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark
                .padding(.top, 84)

            Spacer().frame(height: 96)

            Text("天和雀庄")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text("门店运营管理系统")
                .font(.title3)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 4)
            Text("机器、计费、订单与经营数据")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 12)
        }
    }

    private var compactBrand: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            brandMark
            Text("天和雀庄")
                .font(.largeTitle.bold())
                .foregroundStyle(AppColors.textPrimary)
            Text("门店运营管理系统")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var brandMark: some View {
        Image("TihoLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
    }

    private var loginPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("欢迎回来")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text("登录后进入独立的门店数据空间")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 4)

            formLabel("账号")
                .padding(.top, 48)
            TextField("请输入账号", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(ProductTextFieldStyle())

            formLabel("密码")
                .padding(.top, AppSpacing.medium)
            HStack {
                Group {
                    if showsPassword {
                        TextField("请输入密码", text: $password)
                    } else {
                        SecureField("请输入密码", text: $password)
                    }
                }
                Button {
                    showsPassword.toggle()
                } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .modifier(ProductFieldContainer())

            if let loginError = session.loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(AppColors.danger)
                    .padding(.top, AppSpacing.small)
            }

            Button("登录") { signIn() }
                .buttonStyle(ProductPrimaryButtonStyle())
                .padding(.top, AppSpacing.large)

        }
        .padding(48)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.bottom, 8)
    }

    private func signIn() {
        _ = session.signIn(username: username, password: password)
    }
}

private struct ProductTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .modifier(ProductFieldContainer())
    }
}

private struct ProductFieldContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, lineWidth: 1)
            }
    }
}
