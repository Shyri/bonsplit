import AppKit
import SwiftUI

struct TabBarSelectionChromeMask: Equatable {
    let leftFadeWidth: CGFloat
    let rightFadeWidth: CGFloat
    let rightOcclusionWidth: CGFloat
    let actionLaneSeparatorFadeWidth: CGFloat
    let actionLaneSeparatorSolidWidth: CGFloat
    let actionLaneSeparatorFadeRampStartFraction: CGFloat
}

struct TabBarSelectionChromeView: NSViewRepresentable {
    let selectedTabId: UUID?
    let geometryRegistry: TabBarItemGeometryRegistry
    let indicatorColor: NSColor
    let separatorColor: NSColor
    let mask: TabBarSelectionChromeMask

    func makeNSView(context: Context) -> ChromeNSView {
        let view = ChromeNSView()
        view.geometryRegistry = geometryRegistry
        geometryRegistry.registerObserver(view)
        update(view)
        return view
    }

    func updateNSView(_ nsView: ChromeNSView, context: Context) {
        if nsView.geometryRegistry !== geometryRegistry {
            nsView.geometryRegistry?.unregisterObserver(nsView)
            nsView.geometryRegistry = geometryRegistry
            geometryRegistry.registerObserver(nsView)
        }
        update(nsView)
    }

    private func update(_ view: ChromeNSView) {
        view.selectedTabId = selectedTabId
        view.indicatorColor = indicatorColor
        view.separatorColor = separatorColor
        view.mask = mask
        view.needsDisplay = true
    }

    final class ChromeNSView: NSView {
        weak var geometryRegistry: TabBarItemGeometryRegistry?
        var selectedTabId: UUID?
        var indicatorColor: NSColor = .controlAccentColor
        var separatorColor: NSColor = .separatorColor
        var mask = TabBarSelectionChromeMask(
            leftFadeWidth: 0,
            rightFadeWidth: 0,
            rightOcclusionWidth: 0,
            actionLaneSeparatorFadeWidth: 0,
            actionLaneSeparatorSolidWidth: 0,
            actionLaneSeparatorFadeRampStartFraction: 0
        )

        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let selectedFrame = selectedTabId.flatMap {
                geometryRegistry?.frame(for: $0, in: self)
            }
            drawBottomSeparator(around: selectedFrame)
            drawSelectedIndicator(in: selectedFrame)
        }

        private func drawBottomSeparator(around selectedFrame: CGRect?) {
            separatorColor.setFill()
            let separatorY = max(bounds.minY, bounds.maxY - 1)
            guard let selectedFrame else {
                NSBezierPath(
                    rect: NSRect(x: bounds.minX, y: separatorY, width: bounds.width, height: 1)
                ).fill()
                return
            }

            let selectedMinX = min(max(selectedFrame.minX, bounds.minX), bounds.maxX)
            let selectedMaxX = min(max(selectedFrame.maxX, bounds.minX), bounds.maxX)
            if selectedMinX > bounds.minX {
                NSBezierPath(rect: NSRect(
                    x: bounds.minX,
                    y: separatorY,
                    width: selectedMinX - bounds.minX,
                    height: 1
                )).fill()
            }
            if selectedMaxX < bounds.maxX {
                NSBezierPath(rect: NSRect(
                    x: selectedMaxX,
                    y: separatorY,
                    width: bounds.maxX - selectedMaxX,
                    height: 1
                )).fill()
            }

            let solidWidth = max(0, mask.actionLaneSeparatorSolidWidth)
            let solidMinX = max(bounds.minX, bounds.maxX - solidWidth)
            let solidIntersection = NSIntersectionRect(
                NSRect(x: solidMinX, y: separatorY, width: solidWidth, height: 1),
                NSRect(x: selectedMinX, y: separatorY, width: selectedMaxX - selectedMinX, height: 1)
            )
            if !solidIntersection.isEmpty {
                NSBezierPath(rect: solidIntersection).fill()
            }

            let fadeWidth = max(0, mask.actionLaneSeparatorFadeWidth)
            let fadeFrame = NSRect(
                x: solidMinX - fadeWidth,
                y: separatorY,
                width: fadeWidth,
                height: 1
            )
            let fadeIntersection = NSIntersectionRect(
                fadeFrame,
                NSRect(x: selectedMinX, y: separatorY, width: selectedMaxX - selectedMinX, height: 1)
            )
            if !fadeIntersection.isEmpty {
                let clearSeparator = separatorColor.withAlphaComponent(0)
                let rampStart = min(
                    max(0, mask.actionLaneSeparatorFadeRampStartFraction),
                    0.95
                )
                let gradient = NSGradient(
                    colorsAndLocations:
                        (clearSeparator, 0),
                        (clearSeparator, rampStart),
                        (separatorColor, 1)
                )
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: fadeIntersection).addClip()
                gradient?.draw(in: fadeFrame, angle: 0)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        private func drawSelectedIndicator(in selectedFrame: CGRect?) {
            guard var frame = selectedFrame else { return }
            frame.origin.y = bounds.minY
            frame.size.width = max(0, frame.width - TabBarMetrics.activeIndicatorTrailingInset)
            frame.size.height = TabBarMetrics.activeIndicatorHeight

            let clipMinX = min(bounds.maxX, bounds.minX + max(0, mask.leftFadeWidth))
            let rightInset = max(0, mask.rightFadeWidth) + max(0, mask.rightOcclusionWidth)
            let clipMaxX = max(bounds.minX, bounds.maxX - rightInset)
            guard clipMaxX > clipMinX else { return }

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(
                x: clipMinX,
                y: bounds.minY,
                width: clipMaxX - clipMinX,
                height: bounds.height
            )).addClip()
            indicatorColor.setFill()
            NSBezierPath(rect: frame).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
