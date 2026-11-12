import Cocoa

final class ContentGridView: NSView {
    
    override var isFlipped: Bool { return true }   // Flip so NSView coordinate system reads up-down
    
    private(set) var cards: [ContentSourceCardView] = []
    
    private let emptyStateLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = .systemFont(ofSize: 25)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private static let columns: Int = 3
    private static let padding: CGFloat = 8
    
    func populateGridItems(items: [(name: String, thumbnail: NSImage?)],
                           selectedIndex: Int?,
                           emptyMessage: String,
                           onSelect: @escaping (Int) -> Void) {
        cards.forEach { $0.removeFromSuperview() }
        cards = []
        
        updateEmptyState(message: emptyMessage, isVisible: items.isEmpty)
        if items.isEmpty {
            frame.size.height = superview?.bounds.height ?? bounds.height
            return
        }
        
        let gridColumns = ContentGridView.columns
        let gridPaddings = ContentGridView.padding
        let containerWidth: CGFloat = bounds.width > 0 ? bounds.width : 499
        let itemWidth = (containerWidth - CGFloat(gridColumns + 1) * gridPaddings) / CGFloat(gridColumns)
        let itemHeight = itemWidth * (9.0 / 16.0) + 28   // 16:9 thumbnail + 28 pt label area
        
        for (index, item) in items.enumerated() {
            let col = index % gridColumns
            let row = index / gridColumns
            let x = gridPaddings + CGFloat(col) * (itemWidth + gridPaddings)
            let y = gridPaddings + CGFloat(row) * (itemHeight + gridPaddings)
            
            let card = ContentSourceCardView(frame: NSRect(x: x, y: y, width: itemWidth, height: itemHeight),
                                             name: item.name,
                                             thumbnail: item.thumbnail)
            card.isSelected = (index == selectedIndex)
            
            let captured = index
            card.onSelect = { [weak self] in
                self?.cards.forEach { $0.isSelected = false }
                card.isSelected = true
                onSelect(captured)
            }
            
            addSubview(card)
            cards.append(card)
        }
        
        let rows = CGFloat((items.count + gridColumns - 1) / gridColumns)
        let needed = gridPaddings + rows * (itemHeight + gridPaddings)
        frame.size.height = max(needed, superview?.frame.height ?? needed)
    }
    
    private func updateEmptyState(message: String, isVisible: Bool) {
        if emptyStateLabel.superview == nil {
            addSubview(emptyStateLabel)
            NSLayoutConstraint.activate([emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                                         emptyStateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                                         emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
                                         emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)])
        }
        
        emptyStateLabel.stringValue = message
        emptyStateLabel.isHidden = !isVisible
    }
    
    func selectContentCard(at index: Int) {
        deselectAll()
        guard cards.indices.contains(index) else { return }
        cards[index].isSelected = true
    }
    
    func deselectAll() {
        cards.forEach { $0.isSelected = false }
    }
    
}

// MARK: - Individual content card
final class ContentSourceCardView: NSView {
    
    var isSelected = false { didSet { updateStyle() } }
    var onSelect: (() -> Void)?
    
    override var isFlipped: Bool { return true }   // Flip so NSView coordinate system reads up-down
    
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    
    private let preview = NSImageView()
    private let label = NSTextField(labelWithString: "")
    
    init(frame: NSRect, name: String, thumbnail: NSImage?) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        
        let pad: CGFloat = 4
        let labelHeight: CGFloat = 22
        let previewHeight: CGFloat = max(frame.height - labelHeight - pad - 2, 10)
        
        // Content preview thumbnail at the top
        preview.frame = NSRect(x: pad, y: pad, width: frame.width - pad * 2, height: previewHeight)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 4
        preview.layer?.masksToBounds = true
        preview.image = thumbnail ?? ContentSourceCardView.noSourceThumbnail(size: NSSize(width: frame.width - pad * 2, height: previewHeight))
        addSubview(preview)
        
        // Content name label at the bottom
        label.frame = NSRect(x: pad, y: previewHeight + pad + 2, width: frame.width - pad * 2, height: labelHeight)
        label.stringValue = name
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .labelColor
        addSubview(label)
        
        updateStyle()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    // MARK: - Handling mouse interaction
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let area = trackingArea { removeTrackingArea(area) }
        
        let newTrackingArea = NSTrackingArea(rect: bounds,
                                             options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                             owner: self,
                                             userInfo: nil)
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }
    
    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
    
    // MARK: - Content card appearance
    
    private func updateStyle() {
        let accent = NSColor.alternateSelectedControlColor
        let separator = NSColor.gridColor
        
        if isSelected {
            layer?.borderWidth = 2
            layer?.borderColor = accent.cgColor
            layer?.backgroundColor = accent.withAlphaComponent(0.15).cgColor
        } else if isHovered {
            layer?.borderWidth = 1
            layer?.borderColor = accent.withAlphaComponent(0.5).cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        } else {
            layer?.borderWidth = 1
            layer?.borderColor = separator.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
    
    static func noSourceThumbnail(size: NSSize) -> NSImage {
        return stringToNSImg(text: "OFF", size: size)
    }
    
    static func videoDevThumbnail(size: NSSize) -> NSImage {
        return stringToNSImg(text: "📹", size: size)
    }
    
    static func iOSDeviceThumbnail(size: NSSize) -> NSImage {
        return stringToNSImg(text: "📱", size: size)
    }
    
    private static func stringToNSImg(text: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Background
        NSColor(white: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 4, yRadius: 4).fill()
        
        // Takes in string
        let fontSize = min(size.width, size.height) * 0.35
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: fontSize),
                                                    .foregroundColor: NSColor(white: 0.55, alpha: 1)]
        let str = text as NSString
        let strSize = str.size(withAttributes: attrs)
        let origin = NSPoint(x: (size.width-strSize.width)/2, y: (size.height-strSize.height)/2)
        str.draw(at: origin, withAttributes: attrs)
        
        image.unlockFocus()
        return image
    }
    
}
