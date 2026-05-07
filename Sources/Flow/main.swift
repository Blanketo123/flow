import Cocoa
import SwiftUI
import AVFoundation
import WhisperKit
import Combine

// MARK: - Shared state

final class FlowState: ObservableObject {
    enum Phase { case loading, ready, recording, transcribing }

    @Published var phase: Phase = .loading
    @Published var lastTranscription: String = ""
    @Published var detectedLanguage: String = ""
    @Published var modelName: String = "whisper-base"

    var iconName: String {
        switch phase {
        case .loading: return "hourglass"
        case .ready: return "mic"
        case .recording: return "waveform"
        case .transcribing: return "ellipsis.circle"
        }
    }

    var iconColor: Color {
        switch phase {
        case .loading: return .secondary
        case .ready: return .accentColor
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    var statusTitle: String {
        switch phase {
        case .loading: return "Lade Modell"
        case .ready: return "Bereit"
        case .recording: return "Höre zu"
        case .transcribing: return "Transkribiere"
        }
    }

    var statusSubtitle: String {
        switch phase {
        case .loading: return "Erster Start lädt \(modelName) (~140 MB)"
        case .ready: return "Deutsch, lokal auf Apple Silicon"
        case .recording: return "Sprich frei"
        case .transcribing: return "Whisper läuft lokal"
        }
    }

    func copyLastToClipboard() {
        guard !lastTranscription.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastTranscription, forType: .string)
    }
}

// MARK: - SwiftUI views

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct StatusHero: View {
    @ObservedObject var state: FlowState

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(state.iconColor.opacity(0.12))
                    .frame(width: 148, height: 148)

                Circle()
                    .stroke(state.iconColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 148, height: 148)

                Image(systemName: state.iconName)
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(state.iconColor)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative.reversing,
                                  options: .repeating,
                                  isActive: state.phase == .recording || state.phase == .transcribing)
            }

            VStack(spacing: 4) {
                Text(state.statusTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(.opacity)
                Text(state.statusSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
        }
    }
}

struct HotkeyCard: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                KeyCap("Fn")
                Text("halten + sprechen + loslassen")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("oder")
                    .foregroundStyle(.tertiary)
                KeyCap("Fn")
                Text("tap • sprechen •")
                    .foregroundStyle(.secondary)
                KeyCap("Fn")
                Text("tap")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }
}

struct LastTranscriptionCard: View {
    @ObservedObject var state: FlowState
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LETZTE DIKTION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                if !state.detectedLanguage.isEmpty {
                    Text(state.detectedLanguage.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Button {
                    state.copyLastToClipboard()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(state.lastTranscription.isEmpty)
            }
            Text(state.lastTranscription.isEmpty ? "Noch nichts diktiert" : state.lastTranscription)
                .font(.system(size: 13))
                .foregroundStyle(state.lastTranscription.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ContentView: View {
    @ObservedObject var state: FlowState

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)
                StatusHero(state: state)
                    .animation(.smooth(duration: 0.35), value: state.phase)
                Spacer(minLength: 0)
                HotkeyCard()
                LastTranscriptionCard(state: state)
                    .animation(.smooth(duration: 0.3), value: state.lastTranscription)
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 580)
    }
}

// MARK: - Hotkey (Fn key, dual-mode: hold-to-talk OR tap-toggle)

final class HotkeyManager {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    private enum InternalState {
        case idle
        case recording(start: Date, toggleArmed: Bool)
    }

    private var state: InternalState = .idle
    private var fnDown = false
    private var tap: CFMachPort?
    private let holdThreshold: TimeInterval = 0.5

    func start() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let isDown = event.flags.contains(.maskSecondaryFn)
                DispatchQueue.main.async { mgr.handle(isDown: isDown) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            print("Flow: failed to create event tap. Grant Accessibility permission.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    private func handle(isDown: Bool) {
        guard isDown != fnDown else { return }
        fnDown = isDown

        switch (state, isDown) {
        case (.idle, true):
            state = .recording(start: Date(), toggleArmed: false)
            onStart()
        case (.recording(let start, let armed), false):
            if armed { return }
            let duration = Date().timeIntervalSince(start)
            if duration >= holdThreshold {
                state = .idle
                onStop()
            } else {
                state = .recording(start: start, toggleArmed: true)
            }
        case (.recording(_, let armed), true):
            if armed {
                state = .idle
                onStop()
            }
        default:
            break
        }
    }
}

// MARK: - Audio recorder

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let queue = DispatchQueue(label: "flow.audio")

    func start() throws {
        queue.sync { samples.removeAll() }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "Flow", code: 1)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: outBuffer, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }

            if let channels = outBuffer.floatChannelData {
                let count = Int(outBuffer.frameLength)
                let chunk = Array(UnsafeBufferPointer(start: channels[0], count: count))
                self.queue.async { self.samples.append(contentsOf: chunk) }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return queue.sync { samples }
    }
}

// MARK: - Transcriber

final class Transcriber {
    private var pipe: WhisperKit?

    func load() async {
        do {
            pipe = try await WhisperKit(model: "openai_whisper-base", verbose: false)
        } catch {
            print("Flow: WhisperKit load failed: \(error)")
        }
    }

    func transcribe(_ samples: [Float]) async -> (text: String, language: String) {
        guard let pipe else { return ("", "") }
        guard samples.count > 1600 else { return ("", "") }
        do {
            let options = DecodingOptions(
                task: .transcribe,
                language: "de",
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (text, "de")
        } catch {
            print("Flow: transcribe failed: \(error)")
            return ("", "")
        }
    }
}

// MARK: - Text injector

final class TextInjector {
    func inject(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        if let oldString {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pb.clearContents()
                pb.setString(oldString, forType: .string)
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let flowState = FlowState()
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWindow()

        Task {
            await transcriber.load()
            await MainActor.run {
                self.flowState.phase = .ready
                self.updateMenubarIcon()
            }
        }

        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.stopAndInject() }
        hotkey.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateMenubarIcon()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Flow zeigen", action: #selector(showWindowAction), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Flow beenden", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    @objc private func showWindowAction() { showWindow() }

    private func updateMenubarIcon() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbolName = flowState.iconName
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Flow")?
            .withSymbolConfiguration(cfg)
    }

    private func setupWindow() {
        let view = ContentView(state: flowState)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.title = "Flow"
        win.delegate = self
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        showWindow()
    }

    private func showWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleWindow() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func startRecording() {
        guard flowState.phase == .ready else { return }
        flowState.phase = .recording
        updateMenubarIcon()
        do { try recorder.start() } catch {
            print("Flow: record start failed: \(error)")
            flowState.phase = .ready
            updateMenubarIcon()
        }
    }

    private func stopAndInject() {
        guard flowState.phase == .recording else { return }
        let samples = recorder.stop()
        flowState.phase = .transcribing
        updateMenubarIcon()
        Task {
            let result = await transcriber.transcribe(samples)
            await MainActor.run {
                self.injector.inject(result.text)
                if !result.text.isEmpty {
                    self.flowState.lastTranscription = result.text
                    self.flowState.detectedLanguage = result.language
                }
                self.flowState.phase = .ready
                self.updateMenubarIcon()
            }
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
