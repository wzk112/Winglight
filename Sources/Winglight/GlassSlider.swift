import SwiftUI

/// Pointer movement stays local. Only the small thumb/track subtree is laid out
/// while the consumer can coalesce scene updates independently.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var formattedValue: String
    var step: Double? = nil
    var onEditingEnded: () -> Void = {}
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedValue: Double?
    @State private var hovered=false
    @FocusState private var focused: Bool
    private let thumbWidth: CGFloat=28
    private var fraction: Double { min(1,max(0,((draggedValue ?? value)-range.lowerBound)/(range.upperBound-range.lowerBound))) }
    var body: some View {
        GeometryReader { proxy in
            let travel=max(1,proxy.size.width-thumbWidth)
            ZStack(alignment:.leading) {
                Capsule().fill(.primary.opacity(0.10)).frame(height:7)
                Capsule().fill(.tint.opacity(enabled ? 0.55 : 0.18)).frame(width:thumbWidth/2+travel*fraction,height:7)
                thumb.frame(width:thumbWidth,height:22)
                    .scaleEffect(draggedValue == nil ? (hovered ? 1.04 : 1) : 1.12)
                    .offset(x:travel*fraction)
                    .animation(reduceMotion ? nil : .easeOut(duration:0.15),value:draggedValue != nil)
                    .animation(reduceMotion ? nil : .easeOut(duration:0.15),value:hovered)
            }.frame(height:30).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { event in
                    guard enabled else { return }
                    if !focused { focused=true }
                    let progress=min(1,max(0,(event.location.x-thumbWidth/2)/travel))
                    let next=range.lowerBound+progress*(range.upperBound-range.lowerBound)
                    // Do not attach a spring to the drag position.
                    draggedValue=next;value=next
                }.onEnded { _ in onEditingEnded();draggedValue=nil })
        }.frame(height:30).opacity(enabled ? 1 : 0.45)
            .onHover { hovered=$0 }
            .accessibilityElement(children:.ignore).accessibilityLabel(label).accessibilityValue(formattedValue)
            .accessibilityAdjustableAction { direction in adjust(direction == .increment ? 1 : -1) }
            .focusable(enabled)
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.leftArrow) { adjust(-1);return .handled }
            .onKeyPress(.rightArrow) { adjust(1);return .handled }
    }
    @ViewBuilder private var thumb: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule().fill(.white.opacity(0.12))
                .glassEffect(.regular.interactive(),in:Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.6),lineWidth:0.65) }
                .overlay { Capsule().strokeBorder(.tint.opacity(focused ? 0.9 : 0),lineWidth:1.5) }
                .shadow(color:.black.opacity(0.16),radius:3,y:1)
        } else {
            Capsule().fill(.ultraThinMaterial).overlay { Capsule().strokeBorder(.white.opacity(0.6),lineWidth:0.65) }
                .overlay { Capsule().strokeBorder(.tint.opacity(focused ? 0.9 : 0),lineWidth:1.5) }
        }
    }
    private func adjust(_ direction: Double) {
        guard enabled else { return }
        value=min(range.upperBound,max(range.lowerBound,value+direction*(step ?? (range.upperBound-range.lowerBound)/100)))
        onEditingEnded()
    }
}
