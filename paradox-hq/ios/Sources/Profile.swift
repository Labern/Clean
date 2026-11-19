import SwiftUI
import UIKit
import PhotosUI
import Vision

// Who is running the company: a photo, a name, and the hat being worn right now.

/// How a photo sits in its circle: which point of it is in the middle, and how far in.
nonisolated struct Framing: Codable, Equatable, Sendable {
    /// Across the photo: 0 is its left edge, 1 its right.
    var x: Double = 0.5
    /// Down the photo: 0 is its top edge, 1 its bottom.
    var y: Double = 0.5
    /// 1 fits the photo's shorter side to the circle; more goes in closer.
    var zoom: Double = 1

    static let closest = 6.0

    /// The size the whole photo is drawn at, for a circle `side` across.
    func drawn(_ photo: CGSize, side: CGFloat) -> CGSize {
        let short = min(photo.width, photo.height)
        guard short > 0 else { return .zero }
        let scale = side / short * zoom
        return CGSize(width: photo.width * scale, height: photo.height * scale)
    }

    /// How far the drawn photo is moved from dead centre so that (x, y) sits in the middle.
    func offset(_ photo: CGSize, side: CGFloat) -> CGSize {
        let size = drawn(photo, side: side)
        return CGSize(width: (0.5 - x) * size.width, height: (0.5 - y) * size.height)
    }

    /// The same framing, held in so the circle never shows past the photo's edge.
    func clamped(to photo: CGSize) -> Framing {
        let short = min(photo.width, photo.height)
        guard short > 0 else { return Framing() }
        var held = self
        held.zoom = min(max(zoom, 1), Self.closest)
        // Half the circle, as a share of the photo's width and of its height.
        let halfX = short / (2 * photo.width * held.zoom)
        let halfY = short / (2 * photo.height * held.zoom)
        held.x = min(max(x, halfX), 1 - halfX)
        held.y = min(max(y, halfY), 1 - halfY)
        return held
    }

    /// The photo pushed by a finger: `translation` in points, in a circle `side` across.
    func dragged(by translation: CGSize, photo: CGSize, side: CGFloat) -> Framing {
        let size = drawn(photo, side: side)
        guard size.width > 0, size.height > 0 else { return self }
        var moved = self
        moved.x -= translation.width / size.width
        moved.y -= translation.height / size.height
        return moved.clamped(to: photo)
    }

    /// Pinched in or out by `factor`.
    func zoomed(by factor: Double, photo: CGSize) -> Framing {
        var closer = self
        closer.zoom = zoom * factor
        return closer.clamped(to: photo)
    }

    /// How far the middle can travel across and down the photo at this zoom
    /// before the circle would show past an edge. A single point means no room.
    func room(in photo: CGSize) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        let short = min(photo.width, photo.height)
        guard short > 0, zoom > 0 else { return (0.5...0.5, 0.5...0.5) }
        let halfX = min(0.5, short / (2 * photo.width * zoom))
        let halfY = min(0.5, short / (2 * photo.height * zoom))
        return (halfX...(1 - halfX), halfY...(1 - halfY))
    }

    /// Where to start with a photo when no face can be found in it: head and
    /// shoulders for an upright portrait, the plain middle otherwise.
    static func standing(for photo: CGSize) -> Framing {
        guard photo.height > photo.width * 1.1 else { return Framing() }
        return Framing(x: 0.5, y: 0.25, zoom: 2.2).clamped(to: photo)
    }

    /// A framing that puts a face in the circle with room for the hair. `face` is
    /// the box round it as a share of the photo, measured from the top-left.
    static func around(face: CGRect, in photo: CGSize) -> Framing {
        let short = min(photo.width, photo.height)
        let width = face.width * photo.width
        guard short > 0, width > 0 else { return Framing() }
        // The face fills about half the circle; the middle sits a little above the nose.
        let framing = Framing(x: face.midX, y: face.midY - face.height * 0.08, zoom: 0.5 * short / width)
        return framing.clamped(to: photo)
    }
}

/// Labern's photo, name and current role. Kept on the phone only.
@MainActor @Observable final class Profile {
    /// The hats on offer. More can be added from the role's own menu.
    nonisolated static let roles = ["Founder & Director", "Writer", "Programmer", "Actor", "Designer", "Filmmaker"]

    var name: String = UserDefaults.standard.string(forKey: "profile-name") ?? "Labern" {
        didSet {
            UserDefaults.standard.set(name, forKey: "profile-name")
            onChange?()
        }
    }
    /// The roles being worn, in the order they are listed under the name. Any number, or none.
    private(set) var worn: [String] = Profile.savedWorn() {
        didSet {
            UserDefaults.standard.set(worn, forKey: "profile-worn")
            onChange?()
        }
    }
    /// Roles added on the phone.
    private(set) var added: [String] = UserDefaults.standard.stringArray(forKey: "profile-roles") ?? [] {
        didSet {
            UserDefaults.standard.set(added, forKey: "profile-roles")
            onChange?()
        }
    }
    var framing: Framing = Profile.savedFraming() {
        didSet {
            guard framing != oldValue, let data = try? JSONEncoder().encode(framing) else { return }
            UserDefaults.standard.set(data, forKey: "profile-framing-2")
            onChange?()
        }
    }
    private(set) var photo: UIImage?
    @ObservationIgnored private let folder: URL

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Profile")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        photo = UIImage(contentsOfFile: file.path(percentEncoded: false))
        // No photo chosen on the phone yet: wear the one this build was made with, if
        // any. It lives in Resources/Private on the Mac and is never committed.
        if photo == nil, !UserDefaults.standard.bool(forKey: "profile-no-photo"),
           let built = Bundle.main.url(forResource: "profile", withExtension: "jpg"),
           let data = try? Data(contentsOf: built) {
            photo = Self.prepared(data)
        }
        // A photo that has never been positioned is framed on the face.
        if let photo, UserDefaults.standard.data(forKey: "profile-framing-2") == nil {
            framing = Self.framed(photo)
        }
    }

    /// On the face when one is found, head and shoulders otherwise.
    static func framed(_ photo: UIImage) -> Framing {
        Self.face(in: photo).map { Framing.around(face: $0, in: photo.size) } ?? Framing.standing(for: photo.size)
    }

    private var file: URL { folder.appending(path: "photo.jpg") }

    var allRoles: [String] { Self.merged(Self.roles, added) }

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    /// Takes a new photo: turns it the right way up, keeps it to a sensible size,
    /// and frames it on the face if there is one.
    @discardableResult
    func setPhoto(_ data: Data) -> Bool {
        guard let picture = Self.prepared(data), let jpeg = picture.jpegData(compressionQuality: 0.9) else { return false }
        try? jpeg.write(to: file, options: .atomic)
        UserDefaults.standard.set(false, forKey: "profile-no-photo")
        photo = picture
        framing = Self.framed(picture)
        onChange?()
        return true
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: file)
        UserDefaults.standard.set(true, forKey: "profile-no-photo")
        photo = nil
        framing = Framing()
        onChange?()
    }

    // MARK: The canonical copy (see `CloudSync`)

    /// Called whenever anything here changes, so it is sent on.
    @ObservationIgnored var onChange: (() -> Void)? = nil

    /// The photo being worn, as bytes: the one chosen on the phone, or the one this build carries.
    var photoBytes: Data? {
        if let chosen = try? Data(contentsOf: file) { return chosen }
        guard !UserDefaults.standard.bool(forKey: "profile-no-photo"),
              let built = Bundle.main.url(forResource: "profile", withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: built)
    }

    /// A photo small enough to send: as it is, or made lighter when it is large.
    static func light(_ data: Data) -> Data {
        guard data.count > 700_000, let smaller = prepared(data)?.jpegData(compressionQuality: 0.85) else { return data }
        return smaller
    }

    /// Takes the name, roles and framing set on another device.
    func take(name: String, worn: [String], added: [String], framing: Framing) {
        if self.name != name, !name.isEmpty { self.name = name }
        if self.added != added { self.added = added }
        if self.worn != worn { self.worn = worn }
        if self.framing != framing { self.framing = framing }
    }

    /// Takes the photo chosen on another device, exactly as it is (its framing comes with it), or none.
    func takePhoto(_ data: Data?) {
        if let data, let picture = UIImage(data: data) {
            try? data.write(to: file, options: .atomic)
            UserDefaults.standard.set(false, forKey: "profile-no-photo")
            photo = picture
        } else if data == nil {
            try? FileManager.default.removeItem(at: file)
            UserDefaults.standard.set(true, forKey: "profile-no-photo")
            photo = nil
        }
    }

    /// Adds a role of your own and puts it on.
    func add(role new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !allRoles.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { added.append(trimmed) }
        let named = allRoles.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
        if !worn.contains(named) { worn = Self.toggled(worn, named, order: allRoles) }
    }

    func wears(_ role: String) -> Bool { worn.contains(role) }

    /// Puts a role on, or takes it off.
    func toggle(_ role: String) {
        worn = Self.toggled(worn, role, order: allRoles)
    }

    /// The roles worn after one is tapped, kept in the order of the list they are chosen from.
    nonisolated static func toggled(_ worn: [String], _ role: String, order: [String]) -> [String] {
        var next = worn.contains(role) ? worn.filter { $0 != role } : worn + [role]
        next.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        return next
    }

    /// What was worn last time; before there could be several, the one role chosen.
    nonisolated static func savedWorn() -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: "profile-worn") { return saved }
        return [UserDefaults.standard.string(forKey: "profile-role") ?? roles[0]]
    }

    // MARK: Pure parts, tested

    /// The roles that ship, then the ones added, with no repeats.
    nonisolated static func merged(_ fixed: [String], _ added: [String]) -> [String] {
        var seen = Set(fixed.map { $0.lowercased() })
        return fixed + added.filter { seen.insert($0.lowercased()).inserted }
    }

    nonisolated static func savedFraming() -> Framing {
        guard let data = UserDefaults.standard.data(forKey: "profile-framing-2"),
              let framing = try? JSONDecoder().decode(Framing.self, from: data) else { return Framing() }
        return framing
    }

    /// The photo the right way up and no more than `longest` points on its longer side.
    static func prepared(_ data: Data, longest: CGFloat = 1600) -> UIImage? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The largest face in a photo, as a share of it, measured from the top-left.
    static func face(in image: UIImage) -> CGRect? {
        guard let picture = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: picture, options: [:]).perform([request])
        guard let box = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox else {
            return nil
        }
        // Vision measures up from the bottom-left.
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
}

/// A photo in its circle, or an initial where there isn't one yet.
struct Avatar: View {
    let photo: UIImage?
    var framing = Framing()
    var side: CGFloat = 40
    var initial = ""

    var body: some View {
        Group {
            if let photo {
                let size = framing.drawn(photo.size, side: side)
                Image(uiImage: photo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .offset(framing.offset(photo.size, side: side))
                    .frame(width: side, height: side)
            } else {
                Text(initial)
                    .font(Face.at(side * 0.42, .semibold))
                    .foregroundStyle(Ink.body)
                    .frame(width: side, height: side)
                    .background(Ink.surface2)
            }
        }
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Ink.line, lineWidth: 1) }
    }
}

/// Top right of the Work tab: the photo, the name, and under it every role
/// being worn, stacked. The photo opens the editor; the roles open the list.
struct ProfileBadge: View {
    @Environment(Profile.self) private var profile
    @Environment(CloudSync.self) private var cloud
    @State private var signingIn = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var adding = false
    @State private var draft = ""
    @State private var hits = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The photo is the account: its picture, and the way out.
            Menu {
                Button("Photo and position", systemImage: "person.crop.circle") { editing = true }
                if cloud.available {
                    if cloud.signedIn {
                        Section(cloud.email ?? "Signed in") {
                            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                leaving = true
                            }
                        }
                    } else {
                        Divider()
                        Button("Sign in", systemImage: "person.badge.key") { signingIn = true }
                    }
                }
            } label: {
                Avatar(photo: profile.photo, framing: profile.framing, side: 44, initial: profile.initial)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your account")
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(Face.style(.body))
                    .foregroundStyle(Ink.head)
                    .lineLimit(1)
                // Tick as many as apply; the menu stays open while you do.
                Menu {
                    ForEach(profile.allRoles, id: \.self) { role in
                        Toggle(role, isOn: Binding(get: { profile.wears(role) }, set: { _ in profile.toggle(role) }))
                    }
                    .menuActionDismissBehavior(.disabled)
                    Divider()
                    Button("New role", systemImage: "plus") {
                        draft = ""
                        adding = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        if profile.worn.isEmpty {
                            Text("Add a role")
                                .foregroundStyle(Ink.idle)
                        }
                        ForEach(profile.worn, id: \.self) { role in
                            Text(role)
                                .lineLimit(1)
                        }
                    }
                    .font(Face.style(.subheadline))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.leading)
                    // Hit stop: a change swells the stack, holds, and settles.
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { view, scale in
                        view.scaleEffect(scale, anchor: .topLeading)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(1.1, duration: 0.06)
                            LinearKeyframe(1.1, duration: 0.10)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                    }
                    .frame(minHeight: 22, alignment: .top)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(profile.worn.isEmpty ? "Roles" : "Roles: \(profile.worn.joined(separator: ", "))")
            }
            // The name sits level with the middle of the photo's top half, like the account row it is modelled on.
            .padding(.top, 2)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: profile.worn)
        .onChange(of: profile.worn) {
            if !reduceMotion { hits += 1 }
        }
        .sheet(isPresented: $editing) { ProfileEditor() }
        .sheet(isPresented: $signingIn) { CloudSignIn() }
        .confirmationDialog("Sign out of the dashboard on this phone?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await cloud.signOut()
                    // Straight to the way back in.
                    signingIn = true
                }
            }
        } message: {
            Text("Everything stays on this phone. It stops syncing until you sign in again.")
        }
        .alert("New role", isPresented: $adding) {
            TextField("Role", text: $draft)
            Button("Add") { profile.add(role: draft) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct ChoosePhotoLabel: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "photo")
            .font(Face.style(.subheadline, .semibold))
            .foregroundStyle(Ink.body)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Change the photo, move it about in its circle, and set the name.
struct ProfileEditor: View {
    @Environment(Profile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem? = nil
    @State private var dragged = CGSize.zero
    @State private var pinched: CGFloat = 1
    @State private var problem = ""

    private let side: CGFloat = 248

    var body: some View {
        @Bindable var profile = profile
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Avatar(photo: profile.photo, framing: profile.framing, side: side, initial: profile.initial)
                        .contentShape(Circle())
                        // Ahead of the page's own scrolling, so a drag on the photo moves the photo.
                        .highPriorityGesture(position)
                        .padding(.top, 12)
                    if let photo = profile.photo {
                        let room = profile.framing.room(in: photo.size)
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                control("plus.magnifyingglass", "Zoom", 1...Framing.closest,
                                        get: { profile.framing.zoom },
                                        set: { value in
                                            var closer = profile.framing
                                            closer.zoom = value
                                            profile.framing = closer.clamped(to: photo.size)
                                        })
                                Hairline(inset: 50)
                                control("arrow.left.and.right", "Left and right", room.x,
                                        get: { profile.framing.x },
                                        set: { value in
                                            var moved = profile.framing
                                            moved.x = value
                                            profile.framing = moved.clamped(to: photo.size)
                                        })
                                Hairline(inset: 50)
                                control("arrow.up.and.down", "Up and down", room.y,
                                        get: { profile.framing.y },
                                        set: { value in
                                            var moved = profile.framing
                                            moved.y = value
                                            profile.framing = moved.clamped(to: photo.size)
                                        })
                            }
                        }
                    }
                    // The picker builds its label off the main actor, so the label is made here.
                    let choose = ChoosePhotoLabel(title: profile.photo == nil ? "Choose a photo" : "Change photo")
                    PhotosPicker(selection: $pick, matching: .images) { choose }
                    if !problem.isEmpty {
                        Text(problem)
                            .font(Face.style(.footnote))
                            .foregroundStyle(Ink.hazard)
                    }
                    Card(padding: 0) {
                        TextField("Name", text: $profile.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                    }
                    if profile.photo != nil {
                        Button("Remove photo", role: .destructive) {
                            withAnimation(.snappy) { profile.removePhoto() }
                        }
                        .font(Face.style(.subheadline))
                    }
                }
                .page()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Ink.ground)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: pick) { _, chosen in
                guard let chosen else { return }
                Task {
                    let data = try? await chosen.loadTransferable(type: Data.self)
                    if let data, profile.setPhoto(data) {
                        problem = ""
                        Thud.success()
                    } else {
                        problem = "That photo couldn't be opened."
                    }
                    pick = nil
                }
            }
        }
    }

    /// One slider of the three. With no room to move (a tall photo at full width has
    /// none sideways until it is zoomed), the slider rests in the middle, dimmed.
    private func control(_ symbol: String, _ name: String, _ range: ClosedRange<Double>,
                         get: @escaping @MainActor () -> Double,
                         set: @escaping @MainActor (Double) -> Void) -> some View {
        let open = range.upperBound - range.lowerBound > 0.002
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(Face.at(15, .semibold))
                .foregroundStyle(Ink.muted)
                .frame(width: 24)
            if open {
                Slider(value: Binding(get: { min(max(get(), range.lowerBound), range.upperBound) }, set: { set($0) }),
                       in: range)
                    .tint(Ink.head)
            } else {
                Slider(value: .constant(0.5), in: 0...1)
                    .tint(Ink.head)
                    .disabled(true)
                    .opacity(0.35)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }

    /// One finger moves the photo in its circle; two fingers bring it closer or further.
    private var position: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                guard let photo = profile.photo else { return }
                let step = CGSize(width: value.translation.width - dragged.width,
                                  height: value.translation.height - dragged.height)
                dragged = value.translation
                profile.framing = profile.framing.dragged(by: step, photo: photo.size, side: side)
            }
            .onEnded { _ in dragged = .zero }
        let pinch = MagnifyGesture()
            .onChanged { value in
                guard let photo = profile.photo, pinched > 0 else { return }
                let step = value.magnification / pinched
                pinched = value.magnification
                profile.framing = profile.framing.zoomed(by: Double(step), photo: photo.size)
            }
            .onEnded { _ in pinched = 1 }
        return drag.simultaneously(with: pinch)
    }
}
