import AppKit
@testable import Bonsplit
import SwiftUI
import Testing

#if DEBUG
@MainActor
@Suite("Tab bar layout feedback")
struct TabBarLayoutFeedbackTests {
    @Test("Scrolling 50 content-sized tabs does not feed measured frames into SwiftUI state")
    func scrollingManyTabsDoesNotMutateLayoutFeedbackState() throws {
        let size = NSSize(width: 420, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false
        let pane = try #require(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<50).map { index in
            TabItem(
                title: "Terminal \(index + 1) — \(String(repeating: "x", count: index % 17))",
                icon: "terminal.fill",
                kind: "terminal"
            )
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.first?.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        settleLayout(in: window, hostingView: hostingView)
        let scrollView = try #require(tabBarScrollView(in: hostingView))
        let chromeView = try #require(
            descendants(ofType: TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first
        )
        let initialFirstFrame = try #require(
            chromeView.geometryRegistry?.frame(for: tabs[0].id, in: chromeView)
        )
        let maximumOffset = max(
            0,
            max(
                scrollView.documentView?.frame.width ?? 0,
                scrollView.documentView?.bounds.width ?? 0
            ) - scrollView.contentView.bounds.width
        )
        #expect(maximumOffset > 0)

        BonsplitDebugCounters.reset()
        for step in 1...8 {
            let offset = maximumOffset * CGFloat(step) / 8
            scrollView.contentView.scroll(to: NSPoint(x: offset, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            settleLayout(in: window, hostingView: hostingView, passes: 2)
        }

        let registeredFrames = try #require(chromeView.geometryRegistry?.frames(
            for: tabs.map(\.id),
            in: chromeView
        ))
        let scrolledFirstFrame = try #require(registeredFrames[tabs[0].id])
        #expect(registeredFrames.count == tabs.count)
        #expect(abs((initialFirstFrame.minX - maximumOffset) - scrolledFirstFrame.minX) <= 1)

        #expect(
            BonsplitDebugCounters.tabFrameLayoutFeedbackMutationCount == 0,
            "Tab geometry must remain inside AppKit layout instead of invalidating the SwiftUI view graph."
        )
    }

    private func settleLayout(in window: NSWindow, hostingView: NSView, passes: Int = 6) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.01))
        }
    }

    private func tabBarScrollView(in root: NSView) -> NSScrollView? {
        descendants(ofType: NSScrollView.self, in: root).first { scrollView in
            let documentHeight = max(
                scrollView.documentView?.frame.height ?? 0,
                scrollView.documentView?.bounds.height ?? 0
            )
            return abs(scrollView.frame.height - TabBarMetrics.barHeight) <= 0.5
                && abs(documentHeight - TabBarMetrics.barHeight) <= 0.5
                && scrollView.frame.width > 0
        }
    }

    private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        if let match = root as? T {
            matches.append(match)
        }
        for subview in root.subviews {
            matches.append(contentsOf: descendants(ofType: type, in: subview))
        }
        return matches
    }
}
#endif
