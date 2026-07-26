import AppKit

/// A row of small buttons for standard monitor sizes, hosted inside an `NSMenuItem`.
///
/// Discrete sizes rather than a slider: nobody wants a 27.4" working area, and a
/// continuous control makes it fiddly to land on the size you actually mean.
final class SizePickerMenuItemView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let control = NSSegmentedControl()

    private var sizes: [Double] = []
    private let onSelect: (Double) -> Void

    init(title: String, onSelect: @escaping (Double) -> Void) {
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 54))

        titleLabel.stringValue = title
        titleLabel.font = .menuFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        control.segmentStyle = .automatic
        control.controlSize = .regular
        control.trackingMode = .selectOne
        control.target = self
        control.action = #selector(segmentChanged)
        control.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            control.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isEnabled: Bool {
        get { control.isEnabled }
        set {
            control.isEnabled = newValue
            titleLabel.textColor = newValue ? .labelColor : .disabledControlTextColor
        }
    }

    /// Rebuilds the buttons only when the list itself changes, so reopening the menu does
    /// not flicker the selection.
    func configure(sizes: [Double], selected: Double) {
        if sizes != self.sizes {
            self.sizes = sizes
            control.segmentCount = sizes.count
            for (index, size) in sizes.enumerated() {
                control.setLabel(Self.label(for: size), forSegment: index)
                control.setWidth(0, forSegment: index)
            }
        }

        control.selectedSegment = Self.nearestIndex(to: selected, in: sizes) ?? -1
    }

    /// The list is fixed and short, so a linear scan is the whole story.
    static func nearestIndex(to value: Double, in sizes: [Double]) -> Int? {
        guard !sizes.isEmpty else { return nil }
        return sizes.indices.min { abs(sizes[$0] - value) < abs(sizes[$1] - value) }
    }

    private static func label(for size: Double) -> String {
        size == size.rounded()
            ? String(format: "%.0f\"", size)
            : String(format: "%.1f\"", size)
    }

    @objc private func segmentChanged() {
        let index = control.selectedSegment
        guard sizes.indices.contains(index) else { return }
        onSelect(sizes[index])
    }
}
