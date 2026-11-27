import SwiftUI

/// Signing in to the dashboard: the mark, the word, two fields. Done once; the
/// phone then stays signed in, and after Sign out the fields come already filled in.
/// The same sheet, once signed in, shows the account.
struct CloudSignIn: View {
    @Environment(CloudSync.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var password = ""
    @State private var again = ""
    /// Making the account rather than signing in to it.
    @State private var new = false
    @State private var stars = 0
    @State private var hits = 0
    @State private var landed = 0
    @FocusState private var field: Field?

    enum Field { case email, password, again }

    private var ready: Bool {
        email.contains("@") && password.count >= (new ? 10 : 1) && (!new || password == again) && !cloud.busy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    MarkView(width: 190, twinkle: stars)
                    HStack(spacing: 12) {
                        Rectangle().fill(Ink.idle).frame(height: 1)
                        Text("Dashboard")
                            .font(Face.graphik(15))
                            .tracking(0.6)
                            .foregroundStyle(Ink.muted)
                            .fixedSize()
                        Rectangle().fill(Ink.idle).frame(height: 1)
                    }
                }
                .padding(.top, 44)

                if cloud.signedIn { account } else { form }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.ground.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Face.at(13, .bold))
                    .foregroundStyle(Ink.muted)
                    .frame(width: 32, height: 32)
                    .background(Ink.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(16)
        }
        .sensoryFeedback(.success, trigger: landed)
        .sensoryFeedback(.error, trigger: cloud.refusal) { _, new in !new.isEmpty }
        .onAppear {
            email = cloud.email ?? email
            // Filled in from the last sign-in on this phone: one tap is all it takes.
            if !cloud.signedIn, password.isEmpty, let kept = cloud.remembered {
                email = kept.email
                password = kept.password
            }
            if !reduceMotion { stars += 1 }
            if !cloud.signedIn, password.isEmpty { field = email.isEmpty ? .email : .password }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($field, equals: .email)
                    .onSubmit { field = .password }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                Hairline(inset: 16)
                SecureField("Password", text: $password)
                    .textContentType(new ? .newPassword : .password)
                    .submitLabel(new ? .next : .go)
                    .focused($field, equals: .password)
                    .onSubmit { if new { field = .again } else { go() } }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                if new {
                    Hairline(inset: 16)
                    SecureField("Password again", text: $again)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .focused($field, equals: .again)
                        .onSubmit(go)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                }
            }
            .font(Face.style(.body))
            .foregroundStyle(Ink.head)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !cloud.refusal.isEmpty {
                Text(cloud.refusal)
                    .font(Face.style(.footnote))
                    .foregroundStyle(Ink.hazard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else if new, !password.isEmpty, password.count < 10 {
                Text("Ten characters or more.")
                    .font(Face.style(.footnote))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button(action: go) {
                HStack(spacing: 8) {
                    if cloud.busy { StarSpinner(size: 22, color: Ink.buttonInk) }
                    Text(new ? "Sign up" : "Sign in")
                        .font(Face.style(.headline))
                }
                .foregroundStyle(Ink.buttonInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Ink.button.opacity(ready ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            // Hit stop: the button dips, holds, and springs back as it is pressed.
            .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.96, duration: 0.05)
                    LinearKeyframe(0.96, duration: 0.09)
                    SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                }
            }

            Button {
                withAnimation(.snappy) {
                    new.toggle()
                    cloud.refusal = ""
                }
            } label: {
                Text(new ? "I have an account" : "Create the account")
                    .font(Face.style(.subheadline, .medium))
                    .foregroundStyle(Ink.muted)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var account: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                InfoRow(symbol: "person.crop.circle", title: cloud.email ?? "Signed in", detail: standing) {
                    Pill(text: cloud.problem.isEmpty ? "In step" : "Waiting", color: cloud.problem.isEmpty ? Ink.ok : Ink.amber)
                }
                Hairline(inset: 58)
                Button {
                    Task { await cloud.pass() }
                } label: {
                    InfoRow(symbol: "arrow.triangle.2.circlepath", title: "Sync now") {
                        if cloud.busy { StarSpinner(size: 22) }
                    }
                }
                .buttonStyle(.plain)
            }
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(role: .destructive) {
                Task { await cloud.signOut() }
            } label: {
                Text("Sign out")
                    .font(Face.style(.subheadline, .medium))
                    .foregroundStyle(Ink.hazard)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var standing: String {
        if !cloud.problem.isEmpty { return cloud.problem }
        guard let last = cloud.last else { return "Syncing" }
        return "Synced \(last.formatted(.dateTime.hour().minute().second()))"
    }

    private func go() {
        guard ready else { return }
        field = nil
        if !reduceMotion { hits += 1 }
        Task {
            if await cloud.signIn(email: email, password: password, new: new) {
                password = ""
                again = ""
                landed += 1
                if !reduceMotion { stars += 1 }
                try? await Task.sleep(for: .seconds(1.1))
                dismiss()
            }
        }
    }
}
