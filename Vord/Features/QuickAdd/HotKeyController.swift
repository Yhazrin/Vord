import Carbon
import Foundation

final class HotKeyController {
    var handler: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var installed = false
    private let identifier = EventHotKeyID(signature: OSType(0x564F5244), id: UInt32.random(in: 1...UInt32.max))

    func register(keyCode: UInt32, modifiers: UInt32) -> String? {
        unregister()
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                1,
                &spec,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            if status != noErr {
                return "Could not install the shortcut handler (\(status))."
            }
            installed = true
        }
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            return "This shortcut is already in use. Choose another one in Settings."
        }
        return nil
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    fileprivate func fire(_ event: EventRef?) -> OSStatus {
        var received = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                MemoryLayout<EventHotKeyID>.size, nil, &received) == noErr,
              received.signature == identifier.signature, received.id == identifier.id else {
            return OSStatus(eventNotHandledErr)
        }
        let handler = handler
        DispatchQueue.main.async {
            handler?()
        }
        return noErr
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    return Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue().fire(event)
}
