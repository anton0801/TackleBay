import Foundation

struct ImportCandidate {
    let db: TBDatabase
    let summary: BackupSummary
    let photos: [(PhotoRef, Data)]
}

/// Pure, actor-free backup coding used from background tasks.
enum BackupCoding {
    static let maxFileBytes = 150 * 1024 * 1024

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// Full check in a temporary area: JSON, schema, references, invariants, photos. Nothing live is touched.
    static func readCandidate(from url: URL) throws -> ImportCandidate {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { throw DomainError.validation("This backup is larger than 150 MB.") }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) } catch {
            throw DomainError.validation("This file couldn't be opened.")
        }
        let file: BackupFile
        do { file = try makeDecoder().decode(BackupFile.self, from: data) } catch {
            throw DomainError.validation("This file isn't a valid Tackle Bay backup.")
        }
        var (db, summary) = try BackupValidator.validate(file)
        var photos: [(PhotoRef, Data)] = []
        for photo in file.photos {
            photos.append((photo.ref, try PhotoStore.validateBackupPhoto(photo)))
        }
        db.settings.onboardingCompleted = true
        return ImportCandidate(db: db, summary: summary, photos: photos)
    }

    static func encode(db: TBDatabase, photoStore: PhotoStore, now: Date) throws -> Data {
        var photos: [BackupPhoto] = []
        for ref in db.photos.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let data = photoStore.data(ref) else {
                throw DomainError.validation("A photo file is missing, so the backup wasn't created.")
            }
            photos.append(BackupPhoto(ref: ref, data: data.base64EncodedString()))
        }
        return try makeEncoder().encode(BackupFile(db: db, photos: photos, createdAt: now))
    }
}

/// Export, validated import (Replace, never Merge), the single internal safety copy and Reset.
@MainActor
final class BackupService: ObservableObject {

    @Published private(set) var previousCopyDate: Date?

    private let store: TackleStore
    private let fm = FileManager.default

    init(store: TackleStore) {
        self.store = store
        refreshPreviousInfo()
    }

    var previousCopyURL: URL { store.rootURL.appendingPathComponent("PreviousData/tackle-bay-previous.json") }
    private var exportDirectory: URL { fm.temporaryDirectory.appendingPathComponent("Export", isDirectory: true) }

    func refreshPreviousInfo() {
        let values = try? previousCopyURL.resourceValues(forKeys: [.contentModificationDateKey])
        previousCopyDate = fm.fileExists(atPath: previousCopyURL.path) ? (values?.contentModificationDate ?? Date()) : nil
    }

    // MARK: Export

    /// Consistent snapshot of everything, including an unfinished return draft.
    private func encodeSnapshot() async throws -> Data {
        let db = store.db
        let photoStore = store.photos
        let now = store.now
        return try await Task.detached(priority: .userInitiated) {
            try BackupCoding.encode(db: db, photoStore: photoStore, now: now)
        }.value
    }

    func makeExportFile() async throws -> URL {
        let data = try await encodeSnapshot()
        try? fm.removeItem(at: exportDirectory)
        try fm.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appendingPathComponent(BackupFile.fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try store.perform { db, now in db.settings.lastExportAt = now }
        return url
    }

    func cleanUpExport() { try? fm.removeItem(at: exportDirectory) }

    // MARK: Import

    func importBlockReason() -> String? {
        if store.isLocked { return "Another data operation is running." }
        if let trip = store.db.openTrip {
            return "Finish returning “\(trip.displayName)” before replacing your data."
        }
        return nil
    }

    func readCandidate(from url: URL) async throws -> ImportCandidate {
        try await Task.detached(priority: .userInitiated) { try BackupCoding.readCandidate(from: url) }.value
    }

    func readPreviousCandidate() async throws -> ImportCandidate {
        try await readCandidate(from: previousCopyURL)
    }

    /// Saves one internal safety copy of the current data first; if that fails, nothing is replaced.
    func apply(_ candidate: ImportCandidate) async throws {
        if let reason = importBlockReason() { throw DomainError.blocked(reason) }
        store.lock(true)
        defer { store.lock(false) }
        do {
            let current = try await encodeSnapshot()
            try fm.createDirectory(at: previousCopyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try current.write(to: previousCopyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw DomainError.blocked("A safety copy of your current data couldn't be saved, so nothing was replaced.")
        }
        let photoStore = store.photos
        let staging = try await Task.detached { try photoStore.stage(candidate.photos) }.value
        let old = try photoStore.swapIn(staging: staging)
        do {
            try store.replaceDatabase(candidate.db)
        } catch {
            photoStore.rollbackSwap(old: old)
            throw DomainError.blocked("The data couldn't be replaced. Your current data has not changed.")
        }
        photoStore.finishSwap(old: old)
        refreshPreviousInfo()
    }

    func deletePreviousCopy() {
        try? fm.removeItem(at: previousCopyURL)
        refreshPreviousInfo()
    }

    // MARK: Reset

    /// Deletes the local database, photos, settings, history, the virtual collection and the safety copy.
    /// Files the user exported earlier are not touched.
    func resetAll() throws {
        guard !store.isLocked else { throw DomainError.blocked("Another data operation is running.") }
        store.lock(true)
        defer { store.lock(false) }
        try store.replaceDatabase(TBDatabase())
        store.photos.removeAll()
        try? fm.removeItem(at: previousCopyURL.deletingLastPathComponent())
        cleanUpExport()
        refreshPreviousInfo()
    }
}
