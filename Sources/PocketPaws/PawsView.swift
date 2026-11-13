import SwiftUI
import PawsCore

private enum Theme {
    static let ink = Color(hex: "35483E")
    static let secondary = Color(hex: "7C877C")
    static let green = Color(hex: "557A5B")
    static let paper = Color(hex: "FBFAF5")
    static let line = Color(hex: "E5E8DE")
}

struct PawsView: View {
    @ObservedObject var model: AppModel
    var quit: () -> Void = { NSApp.terminate(nil) }
    static var preferredHeight: CGFloat { min(770, max(420, (NSScreen.main?.visibleFrame.height ?? 810) - 40)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    animalPicker
                    sizePicker
                    gesturePicker
                    preferences
                    Text("A tiny companion beside your Mac pointer. Press & hold stands in for a pressure click in this prototype.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            footer
        }
        .frame(width: 432, height: Self.preferredHeight)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.green)
                    Text("pocket paws")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(-0.9)
                }
                Text("LITTLE FRIEND. EVERYWHERE YOU GO.")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text("MAC LAB / 01")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
        }
        .padding(24)
        .padding(.bottom, 0)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Checkerboard()
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(model.enabled ? Theme.green : Theme.secondary).frame(width: 5, height: 5)
                            Text(model.enabled ? "ON YOUR DESKTOP" : "TAKING A BREAK")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .tracking(0.8)
                        }
                        Spacer()
                        Text("\(model.animal.species.uppercased()) / \(String(format: "%02d", (model.animals.firstIndex(of: model.animal) ?? 0) + 1))")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    HStack {
                        Text("say hello to \(model.animal.name.lowercased())")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(model.enabled ? model.activePose.title.lowercased() : "paused")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.green)
                    }
                }
                .padding(14)
                AnimalSprite(animal: model.animal, pose: model.activePose,
                             reducedMotion: model.effectiveReducedMotion)
                    .frame(width: 148, height: 148)
                    .offset(y: -3)
            }
            .frame(height: 178)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your desktop, a little happier.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(model.animal.personality)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 6)
                Toggle("Enable desktop pet", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(Theme.green)
                    .help("Show or pause the desktop animal")
            }
            .padding(14)
            .background(.white.opacity(0.65))
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line))
    }

    private var animalPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("01", "Choose your little friend", trailing: "\(model.animals.count) PALS")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(model.animals) { animal in
                    let selected = model.selectedID == animal.id
                    Button {
                        model.selectedID = animal.id
                        model.preview(.hop)
                    } label: {
                        VStack(spacing: 0) {
                            AnimalSprite(animal: animal, reducedMotion: true)
                                .frame(height: 62)
                            Text(animal.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text(animal.species).font(.system(size: 9)).foregroundStyle(Theme.secondary)
                                .padding(.top, 3)
                                .padding(.bottom, 11)
                        }
                        .frame(maxWidth: .infinity)
                        .background(selected ? Color(hex: "EDF2E6") : Color.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.green.opacity(0.65) : Theme.line, lineWidth: selected ? 1.5 : 1))
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10)).foregroundStyle(Theme.green)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose \(animal.name) the \(animal.species)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                Text("Little steps, right by your pointer.")
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button { model.preview(.walk) } label: {
                    Label("Preview steps", systemImage: "figure.walk")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.green)
                .help("Preview the small front-facing footsteps")
            }
            .font(.system(size: 10))
        }
    }

    private var sizePicker: some View {
        HStack {
            Text("Little, or a little bigger?")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            HStack(spacing: 3) {
                ForEach(1...3, id: \.self) { size in
                    Button {
                        model.pixelSize = size
                    } label: {
                        Text(["S", "M", "L"][size - 1])
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .frame(width: 29, height: 24)
                            .background(model.pixelSize == size ? Theme.green : Color.clear)
                            .foregroundStyle(model.pixelSize == size ? .white : Theme.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(["Small", "Medium", "Large"][size - 1]) animal size")
                    .accessibilityAddTraits(model.pixelSize == size ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Theme.line.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var gesturePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("02", "A little personality", trailing: "GESTURES")
            VStack(spacing: 0) {
                ForEach(Gesture.allCases) { gesture in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: gesture))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.green)
                            .frame(width: 27, height: 29)
                            .background(Color(hex: "F0F2E9"), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gesture.title).font(.system(size: 11, weight: .medium))
                            Text(gesture.detail).font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                        Picker(gesture.title, selection: Binding(
                            get: { model.mappings[gesture] ?? gesture.defaultPose },
                            set: { model.mappings[gesture] = $0; model.preview($0) }
                        )) {
                            ForEach(Pose.reactions) { pose in Text(pose.title).tag(pose) }
                        }
                        .labelsHidden()
                        .frame(width: 106)
                        .controlSize(.small)
                        Button { model.preview(model.mappings[gesture] ?? gesture.defaultPose) } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Preview \(gesture.title.lowercased())")
                        .accessibilityLabel("Preview \(gesture.title)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if gesture != Gesture.allCases.last { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 49) }
                }
            }
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            HStack {
                Text("Try a click anywhere on your desktop.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Reset") { model.resetMappings() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.green)
                    .accessibilityLabel("Reset gesture mappings")
            }
        }
    }

    private var preferences: some View {
        VStack(spacing: 12) {
            preference("Sleepy when idle", subtitle: "A tiny nap after 6 quiet seconds", value: $model.napsEnabled)
            preference("Calmer animations", subtitle: "Still poses, same personality", value: $model.reducedMotion)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "heart").font(.system(size: 9))
                    Text("SMALL PAWS. OPEN SOURCE.")
                        .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.5)
                }
                .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Quit") { quit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Theme.paper)
    }

    private func sectionHeading(_ number: String, _ title: String, trailing: String) -> some View {
        HStack(spacing: 7) {
            Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            Text(trailing).font(.system(size: 8, design: .monospaced)).tracking(0.6).foregroundStyle(Theme.secondary)
        }
    }

    private func preference(_ title: String, subtitle: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(subtitle).font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.green)
        }
    }

    private func icon(for gesture: PawsCore.Gesture) -> String {
        switch gesture {
        case .leftClick: return "cursorarrow.click"
        case .rightClick: return "computermouse"
        case .longPress: return "hand.point.up.left"
        case .drag: return "hand.draw"
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "F3F4EB")))
            let cell: CGFloat = 14
            for y in 0...Int(size.height / cell) {
                for x in 0...Int(size.width / cell) where (x + y).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(Color(hex: "EBEEE1")))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
