import SwiftUI
import SwiftData

struct RingPage: View {
    @Query(sort: \Camera.order) private var cameras: [Camera]
    @Environment(\.openURL) private var openURL

    var body: some View {
        let low = cameras.filter { $0.battery < 0.25 }

        PageScaffold(spine: .ring, eyebrow: "\(cameras.count) cameras", title: "Ring", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Cameras", trailing: low.isEmpty ? "Batteries fine" : "\(low.count) low")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(cameras) { camera in
                            CameraTile(camera: camera, open: openRing)
                        }
                    }
                }
                TodoCard(spine: .ring, inlineAdd: true)
            }
        } reach: {
            Button(action: openRing) {
                Label("Events", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(QuietStyle())
            Button(action: openRing) {
                Label("Front door", systemImage: "video.fill")
            }
            .buttonStyle(ProminentStyle(spine: .ring))
        }
    }

    private var subtitle: String {
        let latest = cameras
            .compactMap { camera in camera.lastMotion.map { (camera.name, $0) } }
            .max { $0.1 < $1.1 }
        guard let latest else { return "No motion yet" }
        return "Motion: \(latest.0), \(latest.1.formatted(date: .omitted, time: .shortened))"
    }

    private func openRing() {
        Launcher.open("ring://", fallback: "https://account.ring.com", with: openURL)
    }
}

struct CameraTile: View {
    @Bindable var camera: Camera
    let open: () -> Void

    var body: some View {
        let low = camera.battery < 0.25

        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: camera.order == 0 ? "video.doorbell.fill" : "video.fill")
                        .foregroundStyle(Spine.ring.tint)
                    Spacer(minLength: 0)
                    if low {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Spine.tesla.tint)
                            .accessibilityLabel("Battery low")
                    }
                }
                .font(.subheadline)
                Text(camera.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                BatteryBar(level: camera.battery, low: low)
                HStack {
                    Text(camera.battery, format: .percent.precision(.fractionLength(0)))
                    Spacer(minLength: 0)
                    if let motion = camera.lastMotion {
                        Text(Ago.short(motion))
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            Button("Battery replaced", systemImage: "battery.100") {
                withAnimation(.snappy) {
                    camera.battery = 1
                    camera.batteryChanged = .now
                }
            }
            Button("Open in Ring", systemImage: "arrow.up.forward.app", action: open)
        }
    }
}

struct BatteryBar: View {
    let level: Double
    let low: Bool

    var body: some View {
        Capsule()
            .fill(Ink.surface2)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(low ? Spine.tesla.tint : Spine.ring.tint)
                        .frame(width: max(5, proxy.size.width * level))
                }
            }
            .accessibilityHidden(true)
    }
}
