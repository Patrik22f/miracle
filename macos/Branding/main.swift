import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let dimension = CGFloat(pixels)
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let tile = CGRect(x: dimension * 0.10, y: dimension * 0.10, width: dimension * 0.80, height: dimension * 0.80)
        context.setFillColor(CGColor(srgbRed: 0.10, green: 0.36, blue: 0.94, alpha: 1))
        context.addPath(CGPath(roundedRect: tile, cornerWidth: dimension * 0.18, cornerHeight: dimension * 0.18, transform: nil))
        context.fillPath()
        MiracleArtwork.drawMark(in: context,
            bounds: CGRect(x: dimension * 0.18, y: dimension * 0.19, width: dimension * 0.64, height: dimension * 0.64),
            color: CGColor(gray: 1, alpha: 1))
        let suffix = scale == 2 ? "@2x" : ""
        let url = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write Miracle icon") }
    }
}
