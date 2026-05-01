import AppKit

final class StatusBarView: NSView {
    private let uploadLabel: NSTextField
    private let downloadLabel: NSTextField

    override init(frame: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

        uploadLabel = NSTextField(labelWithString: "U: 0 B/s")
        uploadLabel.font = font
        uploadLabel.textColor = .labelColor

        downloadLabel = NSTextField(labelWithString: "D: 0 B/s")
        downloadLabel.font = font
        downloadLabel.textColor = .labelColor

        super.init(frame: frame)

        let stack = NSStackView(views: [uploadLabel, downloadLabel])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(upload: String, download: String) {
        uploadLabel.stringValue = "U: \(upload)"
        downloadLabel.stringValue = "D: \(download)"
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let uploadSize = uploadLabel.intrinsicContentSize
        let downloadSize = downloadLabel.intrinsicContentSize
        let width = max(uploadSize.width, downloadSize.width) + 8
        return NSSize(width: width, height: NSStatusBar.system.thickness)
    }
}
