import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum PhotoError: Error, LocalizedError {
    case unreadable
    case tooLarge
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return "This photo couldn't be read. Your previous photo is unchanged."
        case .tooLarge: return "This photo is too large."
        case .writeFailed: return "The photo couldn't be saved. Your previous photo is unchanged."
        }
    }
}

/// Local photo files. Imports drop EXIF/GPS, apply orientation and cap the long side at 1600 px.
final class PhotoStore {
    static let maxLongSide: CGFloat = 1600
    static let thumbLongSide: CGFloat = 360
    static let maxBackupPhotoBytes = 10 * 1024 * 1024
    static let maxBackupPixels = 20_000_000

    let directory: URL
    private let cache = NSCache<NSString, UIImage>()
    private let fm = FileManager.default

    init(directory: URL) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        cache.countLimit = 120
    }

    func url(_ fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    // MARK: Import from the picker

    /// Runs off the main thread. The user's original is never modified.
    func importPhoto(data: Data) throws -> PhotoRef {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw PhotoError.unreadable
        }
        guard let full = Self.downsample(source, maxPixel: Self.maxLongSide),
              let thumb = Self.downsample(source, maxPixel: Self.thumbLongSide),
              let fullData = Self.jpeg(full, quality: 0.86),
              let thumbData = Self.jpeg(thumb, quality: 0.8) else { throw PhotoError.unreadable }
        let id = UUID()
        let ref = PhotoRef(id: id, fileName: "\(id.uuidString).jpg", thumbFileName: "\(id.uuidString)_thumb.jpg",
                           mime: "image/jpeg", width: full.width, height: full.height, sha256: Self.sha256(fullData))
        do {
            try fullData.write(to: url(ref.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try thumbData.write(to: url(ref.thumbFileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            remove(ref)
            throw PhotoError.writeFailed
        }
        return ref
    }

    static func downsample(_ source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Encodes a fresh JPEG; no source metadata (EXIF, GPS) is carried over.
    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Read

    func image(_ ref: PhotoRef, thumbnail: Bool) -> UIImage? {
        let name = thumbnail ? ref.thumbFileName : ref.fileName
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    func data(_ ref: PhotoRef) -> Data? { try? Data(contentsOf: url(ref.fileName)) }

    func remove(_ ref: PhotoRef) {
        try? fm.removeItem(at: url(ref.fileName))
        try? fm.removeItem(at: url(ref.thumbFileName))
        cache.removeObject(forKey: ref.fileName as NSString)
        cache.removeObject(forKey: ref.thumbFileName as NSString)
    }

    /// Deletes files no record points to (e.g. a picked photo whose form was discarded).
    func removeOrphans(keeping refs: [PhotoRef]) {
        let keep = Set(refs.flatMap { [$0.fileName, $0.thumbFileName] })
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !keep.contains(file) { try? fm.removeItem(at: url(file)) }
    }

    // MARK: Backup

    /// Checks a backup photo: real image format, size limits and checksum. Returns the bytes to store.
    static func validateBackupPhoto(_ photo: BackupPhoto) throws -> Data {
        guard let data = Data(base64Encoded: photo.data) else { throw DomainError.validation("A photo in the backup is damaged.") }
        guard data.count <= maxBackupPhotoBytes else { throw DomainError.validation("A photo in the backup is larger than 10 MB.") }
        guard sha256(data) == photo.ref.sha256 else { throw DomainError.validation("A photo in the backup failed its checksum.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier].contains(type),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw DomainError.validation("A photo in the backup isn't a supported image.")
        }
        guard w * h <= maxBackupPixels else { throw DomainError.validation("A photo in the backup is over 20 megapixels.") }
        return data
    }

    /// Writes the incoming photo set into a staging folder; nothing in the live folder changes.
    func stage(_ photos: [(PhotoRef, Data)]) throws -> URL {
        let staging = directory.deletingLastPathComponent().appendingPathComponent("Photos.staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for (ref, data) in photos {
            try data.write(to: staging.appendingPathComponent(ref.fileName), options: [.atomic])
            let thumb = (CGImageSourceCreateWithData(data as CFData, nil)).flatMap { Self.downsample($0, maxPixel: Self.thumbLongSide) }
            let thumbData = thumb.flatMap { Self.jpeg($0, quality: 0.8) } ?? data
            try thumbData.write(to: staging.appendingPathComponent(ref.thumbFileName), options: [.atomic])
        }
        return staging
    }

    /// Swaps the staged folder in. The old folder is kept until `finishSwap` so a failed database switch can roll back.
    func swapIn(staging: URL) throws -> URL {
        let old = directory.deletingLastPathComponent().appendingPathComponent("Photos.previous", isDirectory: true)
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: directory.path) { try fm.moveItem(at: directory, to: old) }
        do {
            try fm.moveItem(at: staging, to: directory)
        } catch {
            try? fm.moveItem(at: old, to: directory)
            throw error
        }
        cache.removeAllObjects()
        return old
    }

    func rollbackSwap(old: URL) {
        try? fm.removeItem(at: directory)
        try? fm.moveItem(at: old, to: directory)
        cache.removeAllObjects()
    }

    func finishSwap(old: URL) { try? fm.removeItem(at: old) }

    func removeAll() {
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        cache.removeAllObjects()
    }
}
