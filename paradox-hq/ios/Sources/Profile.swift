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
    static let roles = ["Founder & Director", "Writer", "Programmer", "Actor", "Designer", "Filmmaker"]

    var name: String = UserDefaults.standard.string(forKey: "profile-name") ?? "Labern" {
        didSet { UserDefaults.standard.set(name, forKey: "profile-name") }
    }
    var role: String = UserDefaults.standard.string(forKey: "profile-role") ?? Profile.roles[0] {
        didSet { UserDefaults.standard.set(role, forKey: "profile-role") }
    }
    /// Roles added on the phone.
    private(set) var added: [String] = UserDefaults.standard.stringArray(forKey: "profile-roles") ?? [] {
        didSet { UserDefaults.standard.set(added, forKey: "profile-roles") }
    }
    var framing: Framing = Profile.savedFraming() {
        didSet {
            guard framing != oldValue, let data = try? JSONEncoder().encode(framing) else { return }
            UserDefaults.standard.set(data, forKey: "profile-framing")
        }
    }
    private(set) var photo: UIImage?
    @ObservationIgnored private let folder: URL

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Profile")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        photo = UIImage(contentsOfFile: file.path(percentEncoded: false))
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
        photo = picture
        framing = Self.face(in: picture).map { Framing.around(face: $0, in: picture.size) } ?? Framing()
        return true
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: file)
        photo = nil
        framing = Framing()
    }

    /// Adds a role of your own and puts it on.
    func add(role new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !allRoles.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) { added.append(trimmed) }
        role = allRoles.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }

    // MARK: Pure parts, tested

    /// The roles that ship, then the ones added, with no repeats.
    nonisolated static func merged(_ fixed: [String], _ added: [String]) -> [String] {
        var seen = Set(fixed.map { $0.lowercased() })
        return fixed + added.filter { seen.insert($0.lowercased()).inserted }
    }

    nonisolated static func savedFraming() -> Framing {
        guard let data = UserDefaults.standard.data(forKey: "profile-framing"),
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
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(Ink.body)
                    .frame(width: side, height: side)
                    .background(Ink.surface2)
            }
        }
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Ink.line, lineWidth: 1) }
    }
}

/// Top right of Today: the photo, the name, and the role under it. The photo
/// opens the editor; the role opens the list of hats.
struct ProfileBadge: View {
    @Environment(Profile.self) private var profile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var adding = false
    @State private var draft = ""
    @State private var hits = 0

    var body: some View {
        @Bindable var profile = profile
        HStack(spacing: 10) {
            Button { editing = true } label: {
                Avatar(photo: profile.photo, framing: profile.framing, side: 40, initial: profile.initial)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your photo")
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.body)
                    .foregroundStyle(Ink.head)
                    .lineLimit(1)
                Menu {
                    Picker("Role", selection: $profile.role) {
                        ForEach(profile.allRoles, id: \.self) { Text($0).tag($0) }
                    }
                    Button("New role", systemImage: "plus") {
                        draft = ""
                        adding = true
                    }
                } label: {
                    Text(profile.role)
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        // Hit stop: the new role swells, holds, and settles.
                        .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { view, scale in
                            view.scaleEffect(scale, anchor: .leading)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(1.14, duration: 0.06)
                                LinearKeyframe(1.14, duration: 0.10)
                                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                            }
                        }
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Role, \(profile.role)")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: profile.role)
        .onChange(of: profile.role) {
            if !reduceMotion { hits += 1 }
        }
        .sheet(isPresented: $editing) { ProfileEditor() }
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
            .font(.subheadline.weight(.semibold))
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
                        .gesture(position)
                        .padding(.top, 12)
                    if let photo = profile.photo {
                        HStack(spacing: 12) {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: Binding(
                                get: { profile.framing.zoom },
                                set: { value in
                                    var closer = profile.framing
                                    closer.zoom = value
                                    profile.framing = closer.clamped(to: photo.size)
                                }), in: 1...Framing.closest)
                            .tint(Ink.head)
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, 8)
                    }
                    // The picker builds its label off the main actor, so the label is made here.
                    let choose = ChoosePhotoLabel(title: profile.photo == nil ? "Choose a photo" : "Change photo")
                    PhotosPicker(selection: $pick, matching: .images) { choose }
                    if !problem.isEmpty {
                        Text(problem)
                            .font(.footnote)
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
                        .font(.subheadline)
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
