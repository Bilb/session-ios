
@objc(LKIdenticon)
public final class Identicon : NSObject {
    
    @objc public static func generateIcon(string: String, size: CGFloat) -> UIImage {
        let icon = JazzIcon(seed: string)
        let iconLayer = icon.generateLayer(ofSize: size)
        let rect = CGRect(origin: CGPoint.zero, size: iconLayer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { iconLayer.render(in: $0.cgContext) }
        return image
    }
}
