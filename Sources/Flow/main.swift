import Cocoa
import AVFoundation
import WhisperKit

// MARK: - Hotkey (Fn key, dual-mode: hold-to-talk OR tap-toggle)

final class HotkeyManager {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    private enum State {
        case idle
        case recording(start: Date, toggleArmed: Bool)
    }

    private var state: State = .idle
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
            print("Flow: failed to create event tap. Grant Accessibility permission in System Settings.")
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
            if armed { return } // toggle mode: ignore release
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

// MARK: - Audio recorder (16kHz mono float)

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

// MARK: - Transcriber (WhisperKit)

final class Transcriber {
    private var pipe: WhisperKit?

    func load() async {
        do {
            pipe = try await WhisperKit(model: "openai_whisper-small", verbose: false)
        } catch {
            print("Flow: WhisperKit load failed: \(error)")
        }
    }

    func transcribe(_ samples: [Float]) async -> String {
        guard let pipe else { return "" }
        guard samples.count > 1600 else { return "" } // skip <100ms clips
        do {
            let results = try await pipe.transcribe(audioArray: samples)
            return results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            print("Flow: transcribe failed: \(error)")
            return ""
        }
    }
}

// MARK: - Text injector (clipboard + Cmd-V into focused app)

final class TextInjector {
    func inject(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // V
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()
    private var isRecording = false
    private var isReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("hourglass")

        let menu = NSMenu()
        let status = NSMenuItem(title: "Loading model...", action: nil, keyEquivalent: "")
        status.tag = 1
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flow", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        Task {
            await transcriber.load()
            await MainActor.run {
                self.isReady = true
                self.setIcon("mic")
                if let item = self.statusItem.menu?.item(withTag: 1) {
                    item.title = "Ready (hold or tap Fn)"
                }
            }
        }

        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.stopAndInject() }
        hotkey.start()
    }

    private func setIcon(_ symbol: String) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flow")?
            .withSymbolConfiguration(cfg)
    }

    private func startRecording() {
        guard isReady, !isRecording else { return }
        isRecording = true
        setIcon("mic.fill")
        do { try recorder.start() } catch {
            print("Flow: record start failed: \(error)")
            isRecording = false
            setIcon("mic")
        }
    }

    private func stopAndInject() {
        guard isRecording else { return }
        isRecording = false
        let samples = recorder.stop()
        setIcon("ellipsis.circle")
        Task {
            let text = await transcriber.transcribe(samples)
            await MainActor.run {
                self.injector.inject(text)
                self.setIcon("mic")
            }
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
