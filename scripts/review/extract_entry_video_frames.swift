import Foundation
import AVFoundation
import AppKit
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let asset = AVURLAsset(url: input)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let duration = CMTimeGetSeconds(asset.duration)
print("duration_seconds=\(duration)")
print("audio_tracks=\(asset.tracks(withMediaType: .audio).count)")
let requested = CommandLine.arguments.count > 3 ? CommandLine.arguments[3].split(separator: ",").compactMap { Double($0) } : [0, duration * 0.25, duration * 0.5, duration * 0.75]
for value in requested {
  let cg = try generator.copyCGImage(at: CMTime(seconds: value, preferredTimescale: 600), actualTime: nil)
  let bitmap = NSBitmapImageRep(cgImage: cg)
  let name = String(format:"frame-%06.2f.png",value)
  try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
  print("\(name) \(cg.width)x\(cg.height)")
}
