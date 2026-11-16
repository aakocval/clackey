import CoreGraphics
import Foundation

/// System-wide, listen-only keyboard + mouse-button tap.
///
/// Privacy: only the key *code* and up/down state (and, for clicks, the cursor's horizontal
/// position for stereo panning) are read, to choose a sound. Nothing is
/// stored, logged or sent anywhere. macOS never delivers keystrokes from password fields
/// (Secure Input) to event taps, so those stay silent.
@MainActor
final class KeyTap {
    /// (sound, pan) where pan is the key's horizontal position: -1 left … +1 right.
    var onKey: ((KeySound, Float) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Input Monitoring permission (System Settings > Privacy & Security > Input Monitoring).
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards macOS just returns false.
    static func requestPermission() { _ = CGRequestListenEventAccess() }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,             // never blocks or alters typing
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            onKey?(Self.sound(forKeyCode: code), KeyLayout.pan(code))
        case .keyUp:
            onKey?(.up, KeyLayout.pan(event.getIntegerValueField(.keyboardEventKeycode)))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onKey?(.mousedown, Self.pan(forCursorAt: event.location))
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onKey?(.mouseup, Self.pan(forCursorAt: event.location))
        case .flagsChanged:
            // Modifier keys don't send keyDown/keyUp; work out press vs release from the flags.
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let flag = Self.modifierFlags[code] else { return }
            let pan = KeyLayout.pan(code)
            if code == 57 { onKey?(.down, pan); return }      // Caps Lock: one event per press
            onKey?(event.flags.contains(flag) ? .down : .up, pan)
        default:
            break
        }
    }

    /// Cursor x across all displays → -1 (far left) … +1 (far right).
    static func pan(forCursorAt point: CGPoint) -> Float {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success, count > 0 else { return 0 }
        let bounds = ids[0..<Int(count)].map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
        guard bounds.width > 0 else { return 0 }
        return Float((point.x - bounds.minX) / bounds.width) * 2 - 1
    }

    static func sound(forKeyCode code: Int64) -> KeySound {
        switch code {
        case 49: return .space
        case 36, 76: return .return       // Return, keypad Enter
        case 51, 117: return .back        // Delete, Forward Delete
        default: return .down
        }
    }

    static let modifierFlags: [Int64: CGEventFlags] = [
        56: .maskShift, 60: .maskShift,
        59: .maskControl, 62: .maskControl,
        58: .maskAlternate, 61: .maskAlternate,
        55: .maskCommand, 54: .maskCommand,
        63: .maskSecondaryFn,
        57: .maskAlphaShift,
    ]
}

/// Approximate horizontal position of each key on a MacBook (ANSI) keyboard, for stereo panning.
enum KeyLayout {
    private static let positions: [Int64: Float] = {
        var p: [Int64: Float] = [:]
        let rows: [(keys: [Int64], offset: Float)] = [
            ([50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51], 0.0),   // ` 1 … = delete
            ([48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42], 0.0),   // tab q … backslash
            ([57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36], 0.3),             // caps a … return
            ([56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 60], 0.6),               // shift z … shift
        ]
        for row in rows {
            for (i, key) in row.keys.enumerated() { p[key] = (Float(i) + row.offset) / 13 }
        }
        let extra: [Int64: Float] = [53: 0, 63: 0, 59: 0.08, 58: 0.17, 55: 0.27, 49: 0.5,
                                     54: 0.7, 61: 0.78, 123: 0.85, 125: 0.92, 126: 0.92, 124: 1, 76: 1, 117: 1]
        p.merge(extra) { $1 }
        return p
    }()

    static func pan(_ keyCode: Int64) -> Float {
        guard let x = positions[keyCode] else { return 0 }
        return min(1, max(-1, x * 2 - 1))
    }
}

/// C callback: runs on the main run loop (where the source was added).
private func keyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { tap.handle(type, event) }
    }
    return Unmanaged.passUnretained(event)
}
