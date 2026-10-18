import Foundation
import UIKit

final class FlintMarkdownImageAttachment: NSTextAttachment {
    enum LoadState { case pending, loaded, failed }
    let markdownSource: String
    let assetURL: URL?
    let altText: String
    let reference: NoteImageReference?
    private(set) var loadState: LoadState = .pending
    private var preparedImage: UIImage?
    private var loadTask: Task<Void, Never>?
    private var loadID: UUID?
    private var lastAppliedWidth: CGFloat = -1

    init(markdownSource: String, assetURL: URL?, altText: String, vaultURL: URL? = nil) {
        self.markdownSource = markdownSource; self.assetURL = assetURL; self.altText = altText
        reference = assetURL.flatMap { asset in vaultURL.map { NoteImageReference(assetURL: asset, vaultURL: $0) } }
        super.init(data: nil, ofType: nil)
        if reference == nil { loadState = .failed }
        applyLayout(for: 320)
    }
    required init?(coder: NSCoder) { return nil }
    deinit { loadTask?.cancel() }

    func applyLayout(for availableWidth: CGFloat) {
        guard availableWidth > 1, abs(lastAppliedWidth - availableWidth) > 0.5 else { return }
        let title = loadState == .pending ? "Loading image…" : "Image unavailable. Tap to retry."
        let rendered = FlintImageAttachmentRenderer.renderThumbnail(image: preparedImage, title: title, availableWidth: availableWidth)
        image = rendered; bounds = CGRect(origin: CGPoint(x: 0, y: 6), size: rendered.size)
        lastAppliedWidth = availableWidth
    }

    func load(using loader: PreparedImageLoader = .shared, changed: @escaping () -> Void) {
        guard let reference, loadTask == nil, loadState == .pending else { return }
        let id = UUID(); loadID = id
        loadTask = Task { @MainActor [weak self] in
            do {
                let value = try await loader.image(for: reference, size: .inline)
                guard !Task.isCancelled, let self, self.loadID == id else { return }
                self.preparedImage = value.image; self.loadState = .loaded
            } catch {
                guard !Task.isCancelled, let self, self.loadID == id else { return }
                self.loadState = .failed
            }
            guard let self, self.loadID == id else { return }
            self.loadTask = nil
            let width = self.lastAppliedWidth; self.lastAppliedWidth = -1
            self.applyLayout(for: width); changed()
        }
    }

    func cancelLoading() { loadID = nil; loadTask?.cancel(); loadTask = nil }
    func releaseOffscreenPixels() {
        cancelLoading()
        guard loadState == .loaded else { return }
        preparedImage = nil; loadState = .pending
        // Preserve the measured attachment bounds so scrolling does not move the text.
        image = FlintImageAttachmentRenderer.renderThumbnail(image: nil, title: "Loading image…",
            availableWidth: lastAppliedWidth)
    }
    func retry() {
        guard reference != nil else { return }
        cancelLoading(); preparedImage = nil; loadState = .pending
        let width = lastAppliedWidth; lastAppliedWidth = -1; applyLayout(for: width)
    }
    var viewerItem: NoteImageViewerItem? {
        guard let reference else { return nil }
        return NoteImageViewerItem(reference: reference, altText: altText)
    }
}

private enum FlintImageAttachmentRenderer {
    private static let placeholders: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    static func renderThumbnail(image: UIImage?, title: String, availableWidth: CGFloat) -> UIImage {
        if let image { return renderImageCard(image: image, altText: "", availableWidth: availableWidth) }
        return renderPlaceholderCard(title: title, availableWidth: availableWidth)
    }

    private static func renderImageCard(image: UIImage, altText: String, availableWidth: CGFloat) -> UIImage {
        let imageSize = image.size == .zero ? CGSize(width: 1200, height: 900) : image.size
        let targetWidth = targetWidth(for: imageSize, availableWidth: availableWidth)
        let targetHeight = max(120, min(targetWidth * imageSize.height / max(imageSize.width, 1), targetWidth * 1.35))
        let canvasSize = CGSize(width: targetWidth, height: targetHeight)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 24)

            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: UIColor.black.withAlphaComponent(0.16).cgColor)
            UIColor.systemBackground.setFill()
            path.fill()
            context.cgContext.restoreGState()

            UIColor.separator.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            context.cgContext.saveGState()
            path.addClip()
            image.draw(in: rect, blendMode: .normal, alpha: 1)

            let overlay = CAGradientLayer()
            overlay.frame = rect
            overlay.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.08).cgColor
            ]
            overlay.startPoint = CGPoint(x: 0.5, y: 0)
            overlay.endPoint = CGPoint(x: 0.5, y: 1)
            overlay.render(in: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private static func renderPlaceholderCard(title: String, availableWidth: CGFloat) -> UIImage {
        let size = CGSize(width: max(180, min(availableWidth * 0.72, 320)), height: 168)
        let key = "\(size.width)::\(title)" as NSString
        if let cached = placeholders.object(forKey: key) { return cached }
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 24)
            UIColor.secondarySystemBackground.setFill()
            path.fill()
            UIColor.separator.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            let iconConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
            let icon = UIImage(systemName: "photo.slash", withConfiguration: iconConfig)
            let iconRect = CGRect(x: (size.width - 30) / 2, y: 42, width: 30, height: 28)
            icon?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal).draw(in: iconRect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ]
            let textRect = CGRect(x: 18, y: 92, width: size.width - 36, height: 40)
            (title.isEmpty ? "Image unavailable" : title).draw(in: textRect, withAttributes: attributes)
        }
        let cost = rendered.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        placeholders.setObject(rendered, forKey: key, cost: cost)
        return rendered
    }

    private static func targetWidth(for imageSize: CGSize, availableWidth: CGFloat) -> CGFloat {
        let safeWidth = max(availableWidth, 180)
        let aspectRatio = imageSize.width / max(imageSize.height, 1)
        let maxWidth = min(safeWidth, 720)
        let minWidth = min(220, maxWidth)
        let sourceWidth = imageSize.width

        let desiredWidth: CGFloat
        if aspectRatio >= 1 {
            desiredWidth = maxWidth
        } else {
            desiredWidth = max(minWidth, maxWidth * 0.7)
        }

        return min(desiredWidth, max(minWidth, sourceWidth))
    }
}

