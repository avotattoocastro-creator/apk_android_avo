import UIKit

/// Logo of the report header (trainer's sketch 13/11/2026): (1) the horse head and (2) the «AVO · Horse Edition ·
/// Performance» logotype, both cut from avo_brand_hero. Same files as windows/AVO.Windows.Core/Reports/report_*.jpg.
enum ReportLogo {
    struct Part {
        let jpeg: Data
        let width: Int
        let height: Int
    }

    static let head: Part? = load("report_head")
    static let text: Part? = load("report_text")

    private static func load(_ name: String) -> Part? {
        guard let im = UIImage(named: name), let cg = im.cgImage, let d = im.jpegData(compressionQuality: 0.9) else { return nil }
        return Part(jpeg: d, width: cg.width, height: cg.height)
    }
}
