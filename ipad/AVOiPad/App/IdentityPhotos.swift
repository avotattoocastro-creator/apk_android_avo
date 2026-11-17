import UIKit

/// Photo of a horse or rider (trainer's sketch 14/11/2026: «foto» in the card of the Cuadra). One JPEG per code in
/// <app>/fotos/<código>.jpg, at most 900 px on the long side.
enum IdentityPhotos {
    static func dir(_ root: String) -> String { AvoFiles.join(root, "fotos") }

    static func path(_ root: String, _ code: String) -> String {
        let safe: String = code.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? String($0) : "_" }.joined()
        return AvoFiles.join(dir(root), safe + ".jpg")
    }

    static func load(_ root: String, _ code: String) -> UIImage? {
        guard !code.isEmpty else { return nil }
        return UIImage(contentsOfFile: path(root, code))
    }

    /// Resizes and saves; returns false when the data is not an image.
    @discardableResult
    static func save(_ root: String, _ code: String, _ data: Data) -> Bool {
        guard !code.isEmpty, let img = UIImage(data: data) else { return false }
        let maxSide: CGFloat = 900
        let s: CGFloat = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let out: UIImage = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = out.jpegData(compressionQuality: 0.85) else { return false }
        try? FileManager.default.createDirectory(atPath: dir(root), withIntermediateDirectories: true)
        return FileManager.default.createFile(atPath: path(root, code), contents: jpeg)
    }

    static func remove(_ root: String, _ code: String) {
        try? FileManager.default.removeItem(atPath: path(root, code))
    }
}
