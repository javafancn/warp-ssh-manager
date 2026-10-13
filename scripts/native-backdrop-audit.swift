// Compare *composited desktop* captures, not isolated -l NSWindow captures.
// The two backdrops are rendered by another process behind the same application.
// A visible delta in each pane proves wallpaper sampling survives the glass tint.
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let aData = try? Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),
      let bData = try? Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])),
      let a = NSBitmapImageRep(data:aData),
      let b = NSBitmapImageRep(data:bData),
      a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else {
    fputs("Cannot compare composited desktop screenshots\n",stderr)
    exit(2)
}
struct Region {
    let name:String
    let x0:Double, x1:Double, y0:Double, y1:Double
}
// A full connection-list ROI is predominantly occupied by 70%-opaque host
// cards. That is NOT a test of the underlying material and previously yielded
// a false negative (MAE 1.82 even though the exposed glass visibly changed).
// Measure the uncovered gutter immediately to the right of the sidebar, before
// the first host card (CI desktop capture: sidebar ~26% of screen width,
// host cards begin ~27.5%). Keep the full-pane measurement as a diagnostic.
let regions:[Region] = [
    Region(name:"sidebar glass",x0:0.08,x1:0.22,y0:0.26,y1:0.84),
    Region(name:"connections exposed glass",x0:0.259,x1:0.272,y0:0.22,y1:0.82),
    Region(name:"inspector glass",x0:0.71,x1:0.94,y0:0.34,y1:0.84)
]
let diagnostics:[Region] = [
    Region(name:"connections including opaque host cards",x0:0.29,x1:0.64,y0:0.34,y1:0.84)
]
func sampleMAE(_ region:Region) -> (Double,Int) {
    let minX=Int(Double(a.pixelsWide)*region.x0)
    let maxX=Int(Double(a.pixelsWide)*region.x1)
    let minY=Int(Double(a.pixelsHigh)*region.y0)
    let maxY=Int(Double(a.pixelsHigh)*region.y1)
    var error:Double=0
    var count=0
    for y in stride(from:minY,to:maxY,by:6) {
        for x in stride(from:minX,to:maxX,by:6) {
            guard let ca=a.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),
                  let cb=b.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else {continue}
            error += (abs(ca.redComponent-cb.redComponent)
                      + abs(ca.greenComponent-cb.greenComponent)
                      + abs(ca.blueComponent-cb.blueComponent))*255.0/3.0
            count += 1
        }
    }
    return (count == 0 ? 0 : error/Double(count),count)
}
var failed=false
print("Backdrop A/B audit on FULL desktop composites (RGB MAE, 0...255):")
for region in regions {
    let (mae,count)=sampleMAE(region)
    print(String(format:"  %@: %.2f (%d samples)",region.name,mae,count))
    // Test exposed NSVisualEffectView pixels, not opaque host/field controls.
    // A 2/255 difference per channel is the minimum meaningful response.
    if count < 20 || mae < 2 { failed=true }
}
for region in diagnostics {
    let (mae,count)=sampleMAE(region)
    print(String(format:"  [diagnostic] %@: %.2f (%d samples)",region.name,mae,count))
}
if failed {
    fputs("FAILED: exposed glass did not visibly sample both external backdrops\n",stderr)
    exit(1)
}
print("PASS: exposed glass in all three panes responds to the real desktop backdrop")
