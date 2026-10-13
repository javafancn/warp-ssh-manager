// Check screencapture -l (RGBA) for genuine see-through interior seams.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),
      let img = NSBitmapImageRep(data:data),
      img.pixelsWide >= 700, img.pixelsHigh >= 500 else {
    fputs("Invalid native window screenshot\n",stderr)
    exit(2)
}
let width=img.pixelsWide, height=img.pixelsHigh
let xRange=Int(Double(width)*0.13)..<Int(Double(width)*0.90)
let yRange=Int(Double(height)*0.18)..<Int(Double(height)*0.86)
func hole(_ x:Int,_ y:Int) -> Bool {
    guard let pixel=img.colorAt(x:x,y:y) else {return false}
    return pixel.alphaComponent < 0.40 // The old pane-divider holes were 66/255.
}
var columns:[Int]=[]
for x in xRange {
    var count=0, total=0
    for y in stride(from:yRange.lowerBound,to:yRange.upperBound,by:7) {
        if hole(x,y) {count += 1}
        total += 1
    }
    if total>0 && Double(count)/Double(total)>0.65 {columns.append(x)}
}
var rows:[Int]=[]
for y in yRange {
    var count=0, total=0
    for x in stride(from:xRange.lowerBound,to:xRange.upperBound,by:7) {
        if hole(x,y) {count += 1}
        total += 1
    }
    if total>0 && Double(count)/Double(total)>0.65 {rows.append(y)}
}
print("Window interior alpha audit (\(width)x\(height))")
print("Transparent interior columns: \(columns.count); rows: \(rows.count)")
if !columns.isEmpty { print("Columns: \(columns.prefix(12))") }
if !rows.isEmpty { print("Rows: \(rows.prefix(12))") }
guard columns.isEmpty && rows.isEmpty else {
    fputs("FAILED: see-through seam detected in native window\n",stderr)
    exit(1)
}
// Also catch over-translucent windows: alpha below 0.91 lets desktop
// icons and unblurred text bleed through even though no seam exists.
// Sample the central panes away from the rounded window edges.
var lowAlpha=0, inspected=0
for y in stride(from:yRange.lowerBound,to:yRange.upperBound,by:5) {
    for x in stride(from:xRange.lowerBound,to:xRange.upperBound,by:5) {
        guard let pixel=img.colorAt(x:x,y:y) else { continue }
        inspected += 1
        if pixel.alphaComponent < 0.91 { lowAlpha += 1 }
    }
}
let lowRatio=inspected == 0 ? 1 : Double(lowAlpha)/Double(inspected)
print(String(format:"Interior low-opacity samples (<232/255): %.1f%% of %d",
             100 * lowRatio,inspected))
guard lowRatio < 0.08 else {
    fputs("FAILED: excessive wallpaper bleed-through in native window\n",stderr)
    exit(1)
}
print("PASS: no interior seams and native glass opacity preserves legibility")
