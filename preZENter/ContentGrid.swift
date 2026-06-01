import Cocoa

class ContentSourceCardView: NSView {
    
    public var isSelected = false { didSet { updateStyle() } }
    public var onSelect: (() -> Void)?
    
    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    
    override var isFlipped: Bool { return true }   // Flips NSView coordinate system's read sequence
    
    init(frame: NSRect, name: String, thumbnail: NSImage?) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        
        let pad: CGFloat = 4
        let labelHeight: CGFloat = 22
        let thumbnailHeight: CGFloat = max(frame.height - labelHeight - pad * 2 - 2, 10)
        
        // Content thumbnail at the top
        thumbnailView.frame = NSRect(x: pad, y: pad, width: frame.width - pad * 2, height: thumbnailHeight)
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.image = thumbnail ?? ContentSourceCardView.noSourceThumbnail(size: NSSize(width: frame.width - pad * 2, height: thumbnailHeight))
        addSubview(thumbnailView)
        
        // Content name label at the bottom
        nameLabel.frame = NSRect(x: pad, y: thumbnailHeight + pad + 2, width: frame.width - pad * 2, height: labelHeight)
        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .labelColor
        addSubview(nameLabel)
        
        updateStyle()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    public func setThumbnail(_ image: NSImage) {
        DispatchQueue.main.async { self.thumbnailView.image = image }
    }
    
    // Mouse interaction
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }
    
    override func mouseExited (with event: NSEvent) {
        isHovered = false
        updateStyle()
    }
    
    override func mouseDown (with event: NSEvent) {
        onSelect?()
    }
    
    // Appearance
    private func updateStyle() {
        // NSColor.controlAccentColor and .separatorColor require 10.14+.
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
    
    public static func noSourceThumbnail(size: NSSize) -> NSImage {
        return stringToNSImg(text: "OFF", size: size)
    }
    
    public static func videoDevThumbnail(size: NSSize) -> NSImage {
        return stringToNSImg(text: "📹", size: size)
    }
    
    private static func stringToNSImg(text: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Background
        NSColor(white: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 4, yRadius: 4).fill()
        
        // Takes in string
        let fontSize = min(size.width, size.height) * 0.35
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: NSColor(white: 0.55, alpha: 1)]
        let str = text as NSString
        let strSize = str.size(withAttributes: attrs)
        let origin = NSPoint(x: (size.width-strSize.width)/2, y: (size.height-strSize.height)/2)
        str.draw(at: origin, withAttributes: attrs)
        
        image.unlockFocus()
        return image
    }
    
}

class ContentGridView: NSView {
    
    private static let columns: Int = 3
    private static let padding: CGFloat = 8
    private(set) var cards: [ContentSourceCardView] = []
    
    override var isFlipped: Bool { return true }   // NSView coordinate system is down-up, flip so subview layout reads up-down
    
    public func populateGridItems(items: [(name: String, thumbnail: NSImage?)], selectedIndex: Int?, onSelect: @escaping (Int) -> Void) {
        cards.forEach { $0.removeFromSuperview() }
        cards = []
        
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
            
            let card = ContentSourceCardView(frame: NSRect(x: x, y: y, width: itemWidth, height: itemHeight), name: item.name, thumbnail: item.thumbnail)
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
        
        // Resize to fit all rows (minimum = container height)
        let rows = CGFloat((items.count + gridColumns - 1) / gridColumns)
        let needed = gridPaddings + rows * (itemHeight + gridPaddings)
        frame.size.height = max(needed, superview?.frame.height ?? needed)
    }
    
    public func deselectAll() {
        cards.forEach { $0.isSelected = false }
    }
    
    public func selectCard(at index: Int) {
        deselectAll()
        cards[safe: index]?.isSelected = true
    }
    
}

// Safe array subscript helper
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
