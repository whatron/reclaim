// Prints the window number of Reclaim's main window, for `screencapture -l`.
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
var best = (number: 0, area: 0.0)
var bestBounds = ""
for w in windows {
    guard (w[kCGWindowOwnerName as String] as? String) == "Reclaim",
          (w[kCGWindowLayer as String] as? Int) == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    let width = (bounds["Width"] as? Double) ?? 0
    let height = (bounds["Height"] as? Double) ?? 0
    if width * height > best.area {
        best = ((w[kCGWindowNumber as String] as? Int) ?? 0, width * height)
        let x = (bounds["X"] as? Double) ?? 0
        let y = (bounds["Y"] as? Double) ?? 0
        bestBounds = "\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))"
    }
}
// `window_id bounds` prints x,y,w,h instead, for capturing a window together with its sheet.
print(CommandLine.arguments.contains("bounds") ? bestBounds : String(best.number))
