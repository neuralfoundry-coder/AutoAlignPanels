import Foundation
import CoreGraphics
import ApplicationServices

/// A window captured once from the AX server: the element plus everything the
/// alignment pipeline needs, so frames are never re-fetched mid-pipeline.
struct ManagedWindow {
    let element: AXUIElement
    /// AX top-left global coordinates, read at collection time.
    let frame: CGRect
    let title: String?
}

/// Type-checked decoding of CFTypeRef values returned by the AX API.
/// Misbehaving AX servers (Electron, Java) can return unexpected types;
/// every decode verifies the CF type before touching the value.
enum AXDecode {
    private static func axValue(_ ref: CFTypeRef?, _ type: AXValueType) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = ref as! AXValue
        guard AXValueGetType(value) == type else { return nil }
        return value
    }

    static func point(_ ref: CFTypeRef?) -> CGPoint? {
        guard let value = axValue(ref, .cgPoint) else { return nil }
        var out = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &out) else { return nil }
        return out
    }

    static func size(_ ref: CFTypeRef?) -> CGSize? {
        guard let value = axValue(ref, .cgSize) else { return nil }
        var out = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &out) else { return nil }
        return out
    }

    static func bool(_ ref: CFTypeRef?) -> Bool? { ref as? Bool }
    static func string(_ ref: CFTypeRef?) -> String? { ref as? String }

    /// Batch reads report per-attribute failures as AXValue-wrapped AXErrors.
    static func axError(_ ref: CFTypeRef?) -> AXError? {
        guard let value = axValue(ref, .axError) else { return nil }
        var out = AXError.success
        guard AXValueGetValue(value, .axError, &out) else { return nil }
        return out
    }
}

/// Raw per-window attributes from a single batch read.
struct WindowAttributes {
    var position: CGPoint?
    var size: CGSize?
    var minimized: Bool?
    var minimizedError: AXError?
    var title: String?
    var subrole: String?
    var isFullScreen = false
    /// The batch read hit the messaging timeout — the app is unresponsive.
    var timedOut = false
}

enum AXWindowKit {
    /// Cross-process AX calls block; the system default timeout is ~6s per
    /// call, so one hung target app would freeze this app for seconds per
    /// window. 1.5s bounds the damage while leaving room for slow apps.
    static let messagingTimeout: Float = 1.5

    static let fullScreenAttribute = "AXFullScreen"

    /// The timeout is per-element and does not inherit from the app element.
    static func applyTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    static func copyValue(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return (error == .success ? ref : nil, error)
    }

    /// nil means the settability check itself failed — treat as "try anyway".
    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return nil
        }
        return settable.boolValue
    }

    /// One IPC round-trip for all attributes the pipeline needs, with an
    /// individual-read fallback for AX servers that reject the batch call.
    static func readWindowAttributes(_ element: AXUIElement) -> WindowAttributes {
        let names = [
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
            kAXMinimizedAttribute as String,
            kAXTitleAttribute as String,
            kAXSubroleAttribute as String,
            fullScreenAttribute,
        ]

        var attrs = WindowAttributes()
        var valuesRef: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(), &valuesRef)

        if error == .cannotComplete {
            // The app blew the messaging timeout on a single batch call —
            // do NOT fall through to six more blocking calls against the
            // same unresponsive process. The caller decides how to abort.
            attrs.timedOut = true
        } else if error == .success, let values = valuesRef as? [CFTypeRef], values.count == names.count {
            attrs.position = AXDecode.point(values[0])
            attrs.size = AXDecode.size(values[1])
            attrs.minimized = AXDecode.bool(values[2])
            if attrs.minimized == nil {
                attrs.minimizedError = AXDecode.axError(values[2]) ?? .failure
            }
            attrs.title = AXDecode.string(values[3])
            attrs.subrole = AXDecode.string(values[4])
            attrs.isFullScreen = AXDecode.bool(values[5]) ?? false
        } else {
            // Fallback for AX servers that reject the batch call. Each read
            // blocks up to the messaging timeout, so the FIRST timeout marks
            // the window timedOut and aborts the rest — otherwise a hung app
            // would cost six timeouts per window and the caller's retry/abort
            // accounting (keyed on timedOut) would never trigger.
            let (position, positionError) = copyValue(element, kAXPositionAttribute as String)
            if positionError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.position = AXDecode.point(position)
            let (size, sizeError) = copyValue(element, kAXSizeAttribute as String)
            if sizeError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.size = AXDecode.size(size)
            let (minimized, minimizedError) = copyValue(element, kAXMinimizedAttribute as String)
            if minimizedError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.minimized = AXDecode.bool(minimized)
            if attrs.minimized == nil {
                attrs.minimizedError = minimizedError
            }
            let (title, titleError) = copyValue(element, kAXTitleAttribute as String)
            if titleError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.title = AXDecode.string(title)
            let (subrole, subroleError) = copyValue(element, kAXSubroleAttribute as String)
            if subroleError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.subrole = AXDecode.string(subrole)
            let (fullScreen, fullScreenError) = copyValue(element, fullScreenAttribute)
            if fullScreenError == .cannotComplete { attrs.timedOut = true; return attrs }
            attrs.isFullScreen = AXDecode.bool(fullScreen) ?? false
        }
        return attrs
    }

    static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> AXError {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    static func setSize(_ element: AXUIElement, _ size: CGSize) -> AXError {
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    /// size → position → size: shrinking first keeps the window server from
    /// clamping the new position against the old, larger size; the final size
    /// set catches apps that re-adjust on move. Returns the first error, and
    /// aborts remaining steps on a timeout.
    static func setFrame(_ element: AXUIElement, to target: CGRect) -> AXError {
        let first = setSize(element, target.size)
        if first == .cannotComplete { return first }
        let second = setPosition(element, target.origin)
        if second == .cannotComplete { return second }
        let third = setSize(element, target.size)
        for error in [first, second, third] where error != .success { return error }
        return .success
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        let (positionRef, _) = copyValue(element, kAXPositionAttribute as String)
        let (sizeRef, _) = copyValue(element, kAXSizeAttribute as String)
        guard let origin = AXDecode.point(positionRef), let size = AXDecode.size(sizeRef) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func title(of element: AXUIElement) -> String? {
        let (ref, _) = copyValue(element, kAXTitleAttribute as String)
        guard let title = AXDecode.string(ref), !title.isEmpty else { return nil }
        return title
    }

    /// A dead element (closed window, quit app) can no longer answer the most
    /// basic query.
    static func isAlive(_ element: AXUIElement) -> Bool {
        copyValue(element, kAXRoleAttribute as String).error == .success
    }
}
