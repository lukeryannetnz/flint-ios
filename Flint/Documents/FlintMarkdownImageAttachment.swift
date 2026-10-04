import Foundation
import UIKit

final class FlintMarkdownImageAttachment: NSTextAttachment {
    let markdownSource: String
    let assetURL: URL?
    let altText: String

    private var lastAppliedWidth: CGFloat = -1

    init(markdownSource: String, assetURL: URL?, altText: String) {
        self.markdownSource = markdownSource
        self.assetURL = assetURL
        self.altText = altText
        super.init(data: nil, ofType: nil)
        image = FlintImageAttachmentRenderer.renderThumbnail(assetURL: assetURL, altText: altText, availableWidth: 320)
        bounds = CGRect(x: 0, y: 6, width: image?.size.width ?? 220, height: image?.size.height ?? 160)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func applyLayout(for availableWidth: CGFloat) {
        guard availableWidth > 1, abs(lastAppliedWidth - availableWidth) > 0.5 else { return }
        let rendered = FlintImageAttachmentRenderer.renderThumbnail(
            assetURL: assetURL,
            altText: altText,
            availableWidth: availableWidth
        )
        image = rendered
        bounds = CGRect(origin: CGPoint(x: 0, y: 6), size: rendered.size)
        lastAppliedWidth = availableWidth
    }

    var viewerItem: NoteImageViewerItem? {
        guard let assetURL else { return nil }
        return NoteImageViewerItem(assetURL: assetURL, altText: altText)
    }
}

private enum FlintImageAttachmentRenderer {
    static func renderThumbnail(assetURL: URL?, altText: String, availableWidth: CGFloat) -> UIImage {
        let preparation = DebugLog.shared.begin(.imagePrepare, file: assetURL)
        defer { preparation.finish(.success) }
        if let assetURL,
           let sourceImage = loggedImage(at: assetURL) {
            return renderImageCard(image: sourceImage, altText: altText, availableWidth: availableWidth)
        }

        return renderPlaceholderCard(title: altText.isEmpty ? "Image unavailable" : altText, availableWidth: availableWidth)
    }

    private static func loggedImage(at url: URL) -> UIImage? {
        let read = DebugLog.shared.begin(.imageRead, file: url)
        let image = UIImage(contentsOfFile: url.path)
        read.finish(image == nil ? .failure : .success)
        return image
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
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
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

