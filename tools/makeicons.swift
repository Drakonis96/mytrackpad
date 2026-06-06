import AppKit
import CoreGraphics
import Foundation

// Generates the PNGs for the icon catalogs from logo.png.
// macOS keeps transparency (squircle style); iOS is flattened onto white.

let root = FileManager.default.currentDirectoryPath
let logoPath = "\(root)/logo.png"

guard let image = NSImage(contentsOfFile: logoPath),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let srcCG = rep.cgImage else {
    FileHandle.standardError.write(Data("Could not read logo.png\n".utf8))
    exit(1)
}

func render(size: Int, flattenWhite: Bool) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    if flattenWhite {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
    }
    ctx.draw(srcCG, in: rect)
    guard let out = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
}

func write(_ data: Data?, to path: String) {
    guard let data else { FileHandle.standardError.write(Data("render failed \(path)\n".utf8)); exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)")
}

// iOS: 1024 flattened onto white (iOS does not support transparency in the icon).
write(render(size: 1024, flattenWhite: true),
      to: "\(root)/iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

// macOS: sizes with transparency preserved.
let macSizes = [16, 32, 64, 128, 256, 512, 1024]
let macDir = "\(root)/macOS/Assets.xcassets/AppIcon.appiconset"
for size in macSizes {
    write(render(size: size, flattenWhite: false), to: "\(macDir)/icon-\(size).png")
}

print("Done.")
