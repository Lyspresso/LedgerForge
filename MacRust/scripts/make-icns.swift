#!/usr/bin/env swift

import Foundation

enum IconError: Error, CustomStringConvertible {
    case usage
    case invalidPNG(String)
    case fileTooLarge(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: make-icns.swift INPUT.iconset OUTPUT.icns"
        case let .invalidPNG(path):
            return "icon representation is not a PNG: \(path)"
        case let .fileTooLarge(path):
            return "icon representation is too large for an ICNS chunk: \(path)"
        }
    }
}

func appendFourCC(_ value: String, to data: inout Data) {
    data.append(contentsOf: value.utf8)
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

func makeICNS(iconset: URL, output: URL) throws {
    // Modern ICNS PNG slots. Logical 1x and Retina 2x representations are
    // carried separately even where their physical pixel dimensions match.
    let representations = [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]
    let pngSignature = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    var chunks = Data()

    for (type, fileName) in representations {
        let url = iconset.appendingPathComponent(fileName)
        let png = try Data(contentsOf: url)
        guard png.starts(with: pngSignature) else {
            throw IconError.invalidPNG(url.path)
        }
        let (chunkLength, overflow) = UInt32(png.count).addingReportingOverflow(8)
        guard !overflow else {
            throw IconError.fileTooLarge(url.path)
        }
        appendFourCC(type, to: &chunks)
        appendUInt32(chunkLength, to: &chunks)
        chunks.append(png)
    }

    let (containerLength, overflow) = UInt32(chunks.count).addingReportingOverflow(8)
    guard !overflow else {
        throw IconError.fileTooLarge(output.path)
    }
    var container = Data()
    appendFourCC("icns", to: &container)
    appendUInt32(containerLength, to: &container)
    container.append(chunks)
    try container.write(to: output, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconError.usage
    }
    try makeICNS(
        iconset: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        output: URL(fileURLWithPath: CommandLine.arguments[2])
    )
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
