//
//  AppLogDateTimePicker.swift
//  HotTub
//
//  Compact date and time picker for log forms. A single click still chooses a day.
//  A double-click on a day closes the calendar.
//

import SwiftUI
import UIKit

struct AppLogDateTimePicker: View {
    @Binding var selection: Date

    @State private var pickerIdentity = 0

    var body: some View {
        DatePicker(
            "Date & time",
            selection: $selection,
            in: ...FormValidation.latestLoggableMoment(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(pickerIdentity)
        .background(CalendarDoubleClickInstaller())
        .onReceive(NotificationCenter.default.publisher(for: .compactDatePickerCalendarDoubleClick)) { _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pickerIdentity += 1
            }
        }
    }
}

private extension Notification.Name {
    static let compactDatePickerCalendarDoubleClick = Notification.Name(
        "HotTub.compactDatePickerCalendarDoubleClick"
    )
}

/// Watches for a double-click inside the system calendar popover and asks the picker to close.
private struct CalendarDoubleClickInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var started = false

        func start() {
            guard !started else { return }
            started = true
            CalendarDoubleClickMonitor.shared.retainClient()
        }

        func stop() {
            guard started else { return }
            started = false
            CalendarDoubleClickMonitor.shared.releaseClient()
        }
    }
}

private final class CalendarDoubleClickMonitor: NSObject, UIGestureRecognizerDelegate {
    static let shared = CalendarDoubleClickMonitor()

    private var clientCount = 0
    private var recognizers: [ObjectIdentifier: UITapGestureRecognizer] = [:]
    private var windowObserver: NSObjectProtocol?

    func retainClient() {
        clientCount += 1
        guard clientCount == 1 else {
            installOnVisibleWindows()
            return
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow else { return }
            MainActor.assumeIsolated {
                CalendarDoubleClickMonitor.shared.install(on: window)
            }
        }
        installOnVisibleWindows()
    }

    func releaseClient() {
        clientCount = max(0, clientCount - 1)
        guard clientCount == 0 else { return }

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        for recognizer in recognizers.values {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        recognizers.removeAll()
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated {
            guard let view = touch.view else { return false }
            return Self.containsCalendar(view)
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let window = recognizer.view else { return }
        let point = recognizer.location(in: window)
        guard let hit = window.hitTest(point, with: nil), Self.containsCalendar(hit) else { return }
        NotificationCenter.default.post(name: .compactDatePickerCalendarDoubleClick, object: nil)
    }

    private func installOnVisibleWindows() {
        recognizers = recognizers.filter { $0.value.view != nil }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                install(on: window)
            }
        }
    }

    fileprivate func install(on window: UIWindow) {
        let id = ObjectIdentifier(window)
        guard recognizers[id] == nil else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        tap.numberOfTapsRequired = 2
        tap.numberOfTouchesRequired = 1
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        recognizers[id] = tap
    }

    private static func containsCalendar(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate is UICalendarView { return true }
            let described = String(describing: type(of: candidate))
            let named = NSStringFromClass(type(of: candidate))
            if described.localizedCaseInsensitiveContains("Calendar")
                || named.localizedCaseInsensitiveContains("Calendar") {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}
