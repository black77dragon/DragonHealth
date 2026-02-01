import Foundation
import SQLite3
import InfraLogging

struct BackupStatus: Sendable {
    let lastBackupDate: Date?
    let lastBackupDayKey: String?
    let lastBackupPath: String?
    let lastBackupError: String?
    let iCloudAvailable: Bool
}

struct BackupOutcome: Sendable {
    let success: Bool
    let performed: Bool
    let errorMessage: String?
    let backupPath: String?

    nonisolated static func skipped() -> BackupOutcome {
        BackupOutcome(success: true, performed: false, errorMessage: nil, backupPath: nil)
    }

    nonisolated static func succeeded(path: String) -> BackupOutcome {
        BackupOutcome(success: true, performed: true, errorMessage: nil, backupPath: path)
    }

    nonisolated static func failed(_ message: String) -> BackupOutcome {
        BackupOutcome(success: false, performed: true, errorMessage: message, backupPath: nil)
    }
}

struct RestoreOutcome: Sendable {
    let success: Bool
    let errorMessage: String?

    nonisolated static func succeeded() -> RestoreOutcome {
        RestoreOutcome(success: true, errorMessage: nil)
    }

    nonisolated static func failed(_ message: String) -> RestoreOutcome {
        RestoreOutcome(success: false, errorMessage: message)
    }
}

nonisolated struct BackupMetadata: Codable, Sendable {
    let createdAt: String
    let dayKey: String
    let databaseVersion: Int
    let note: String?
}

struct BackupRecord: Identifiable, Sendable {
    let id: String
    let fileURL: URL
    let createdAt: Date
    let dayKey: String?
    let databaseVersion: Int
    let note: String?
    let isCompatible: Bool
}

enum BackupError: Error, LocalizedError {
    case iCloudUnavailable
    case databaseMissing
    case backupCreateFailed(String)
    case backupWriteFailed(String)
    case backupNotFound
    case incompatibleBackup(expected: Int, found: Int)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available. Sign in to iCloud to enable backups."
        case .databaseMissing:
            return "Database file not found. Open the app and try again."
        case .backupCreateFailed(let message):
            return "Unable to create backup: \(message)"
        case .backupWriteFailed(let message):
            return "Unable to write backup: \(message)"
        case .backupNotFound:
            return "Backup file not found."
        case .incompatibleBackup(let expected, let found):
            return "Backup is not compatible (expected DB version \(expected), found \(found))."
        case .restoreFailed(let message):
            return "Unable to restore backup: \(message)"
        }
    }
}

actor BackupWorker {
    static let shared = BackupWorker()

    private enum Keys {
        static let lastBackupDate = "dragonhealth.backup.last_date"
        static let lastBackupDay = "dragonhealth.backup.last_day"
        static let lastBackupPath = "dragonhealth.backup.last_path"
        static let lastBackupError = "dragonhealth.backup.last_error"
    }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private let logger = AppLogger(category: .backup)

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = iso
    }

    func loadStatus() -> BackupStatus {
        let lastDate = defaults.string(forKey: Keys.lastBackupDate).flatMap { isoFormatter.date(from: $0) }
        let lastDay = defaults.string(forKey: Keys.lastBackupDay)
        let lastPath = defaults.string(forKey: Keys.lastBackupPath)
        let lastError = defaults.string(forKey: Keys.lastBackupError)
        let available = iCloudAvailable()
        return BackupStatus(
            lastBackupDate: lastDate,
            lastBackupDayKey: lastDay,
            lastBackupPath: lastPath,
            lastBackupError: lastError,
            iCloudAvailable: available
        )
    }

    func performBackupIfNeeded(force: Bool = false, note: String? = nil) async -> BackupOutcome {
        let todayKey = dayKey(for: Date())
        if !force, defaults.string(forKey: Keys.lastBackupDay) == todayKey {
            return .skipped()
        }
        do {
            let backupURL = try performBackup(dayKey: todayKey, note: note)
            recordSuccess(date: Date(), dayKey: todayKey, backupPath: backupURL.path)
            return .succeeded(path: backupURL.path)
        } catch {
            let message = error.localizedDescription
            recordFailure(message)
            logger.error("backup_failed", metadata: ["error": message])
            return .failed(message)
        }
    }

    func fetchBackups() -> [BackupRecord] {
        guard iCloudAvailable() else { return [] }
        guard let backupsDirectory = try? backupsDirectoryURL() else { return [] }
        let currentVersion = readUserVersion(from: AppStore.databaseURL())
        let urls = (try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let backupFiles = urls.filter { $0.pathExtension == "sqlite" }
        var records: [BackupRecord] = []
        records.reserveCapacity(backupFiles.count)
        for backupURL in backupFiles {
            let metadataURL = metadataURL(for: backupURL)
            let metadata = loadMetadata(from: metadataURL)
            let createdAt = metadata.flatMap { isoFormatter.date(from: $0.createdAt) } ?? fileDate(for: backupURL)
            let dayKey = metadata?.dayKey ?? parseDayKey(from: backupURL)
            let databaseVersion = metadata?.databaseVersion ?? readUserVersion(from: backupURL)
            let note = metadata?.note
            let isCompatible = databaseVersion == currentVersion
            records.append(
                BackupRecord(
                    id: backupURL.path,
                    fileURL: backupURL,
                    createdAt: createdAt,
                    dayKey: dayKey,
                    databaseVersion: databaseVersion,
                    note: note,
                    isCompatible: isCompatible
                )
            )
        }
        return records.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func restoreBackup(_ record: BackupRecord) async -> RestoreOutcome {
        do {
            guard iCloudAvailable() else { throw BackupError.iCloudUnavailable }
            guard fileManager.fileExists(atPath: record.fileURL.path) else { throw BackupError.backupNotFound }
            let currentVersion = readUserVersion(from: AppStore.databaseURL())
            let backupVersion = record.databaseVersion
            guard backupVersion == currentVersion else {
                throw BackupError.incompatibleBackup(expected: currentVersion, found: backupVersion)
            }
            try restoreSQLiteBackup(from: record.fileURL, to: AppStore.databaseURL())
            return .succeeded()
        } catch {
            let message = error.localizedDescription
            logger.error("restore_failed", metadata: ["error": message])
            return .failed(message)
        }
    }

    private func performBackup(dayKey: String, note: String?) throws -> URL {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            throw BackupError.iCloudUnavailable
        }
        let databaseURL = AppStore.databaseURL()
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw BackupError.databaseMissing
        }
        let backupsDirectory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let backupFileName = "dragonhealth-\(dayKey).sqlite"
        let backupURL = backupsDirectory.appendingPathComponent(backupFileName)
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(
            "dragonhealth-backup-\(UUID().uuidString).sqlite"
        )

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        try createSQLiteBackup(from: databaseURL, to: tempURL)

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.moveItem(at: tempURL, to: backupURL)
        let metadata = BackupMetadata(
            createdAt: isoFormatter.string(from: Date()),
            dayKey: dayKey,
            databaseVersion: readUserVersion(from: databaseURL),
            note: note
        )
        try writeMetadata(metadata, to: metadataURL(for: backupURL))
        logger.info("backup_success", metadata: ["path": backupURL.path])
        return backupURL
    }

    private func createSQLiteBackup(from sourceURL: URL, to destinationURL: URL) throws {
        var sourceHandle: OpaquePointer?
        var destinationHandle: OpaquePointer?
        if sqlite3_open_v2(sourceURL.path, &sourceHandle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = sourceHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            sqlite3_close(sourceHandle)
            throw BackupError.backupCreateFailed(message)
        }
        if sqlite3_open_v2(destinationURL.path, &destinationHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            let message = destinationHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite backup open failed"
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.backupWriteFailed(message)
        }
        guard let sourceHandle, let destinationHandle else {
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.backupCreateFailed("SQLite handles missing")
        }
        guard let backup = sqlite3_backup_init(destinationHandle, "main", sourceHandle, "main") else {
            let message = String(cString: sqlite3_errmsg(destinationHandle))
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.backupWriteFailed(message)
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        sqlite3_close(sourceHandle)
        sqlite3_close(destinationHandle)
        if result != SQLITE_DONE {
            throw BackupError.backupWriteFailed("SQLite backup returned code \(result)")
        }
    }

    private func restoreSQLiteBackup(from sourceURL: URL, to destinationURL: URL) throws {
        var sourceHandle: OpaquePointer?
        var destinationHandle: OpaquePointer?
        if sqlite3_open_v2(sourceURL.path, &sourceHandle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = sourceHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            sqlite3_close(sourceHandle)
            throw BackupError.restoreFailed(message)
        }
        if sqlite3_open_v2(destinationURL.path, &destinationHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            let message = destinationHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite restore open failed"
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.restoreFailed(message)
        }
        guard let sourceHandle, let destinationHandle else {
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.restoreFailed("SQLite handles missing")
        }
        guard let backup = sqlite3_backup_init(destinationHandle, "main", sourceHandle, "main") else {
            let message = String(cString: sqlite3_errmsg(destinationHandle))
            sqlite3_close(sourceHandle)
            sqlite3_close(destinationHandle)
            throw BackupError.restoreFailed(message)
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        sqlite3_close(sourceHandle)
        sqlite3_close(destinationHandle)
        if result != SQLITE_DONE {
            throw BackupError.restoreFailed("SQLite restore returned code \(result)")
        }
    }

    private func recordSuccess(date: Date, dayKey: String, backupPath: String) {
        defaults.set(isoFormatter.string(from: date), forKey: Keys.lastBackupDate)
        defaults.set(dayKey, forKey: Keys.lastBackupDay)
        defaults.set(backupPath, forKey: Keys.lastBackupPath)
        defaults.removeObject(forKey: Keys.lastBackupError)
    }

    private func recordFailure(_ message: String) {
        defaults.set(message, forKey: Keys.lastBackupError)
    }

    private func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func backupsDirectoryURL() throws -> URL {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            throw BackupError.iCloudUnavailable
        }
        let backupsDirectory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        return backupsDirectory
    }

    private func metadataURL(for backupURL: URL) -> URL {
        backupURL.deletingPathExtension().appendingPathExtension("json")
    }

    private func writeMetadata(_ metadata: BackupMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private func loadMetadata(from url: URL) -> BackupMetadata? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BackupMetadata.self, from: data)
        } catch {
            logger.error("backup_metadata_read_failed", metadata: ["error": error.localizedDescription])
            return nil
        }
    }

    private func fileDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
    }

    private func parseDayKey(from url: URL) -> String? {
        let baseName = url.deletingPathExtension().lastPathComponent
        guard let range = baseName.range(of: "dragonhealth-") else { return nil }
        let trimmed = baseName[range.upperBound...]
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    private func readUserVersion(from url: URL) -> Int {
        var handle: OpaquePointer?
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(handle)
            return 0
        }
        guard let opened = handle else {
            sqlite3_close(handle)
            return 0
        }
        defer { sqlite3_close(opened) }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(opened, "PRAGMA user_version;", -1, &statement, nil) != SQLITE_OK {
            sqlite3_finalize(statement)
            return 0
        }
        guard let prepared = statement else { return 0 }
        defer { sqlite3_finalize(prepared) }
        if sqlite3_step(prepared) == SQLITE_ROW {
            return Int(sqlite3_column_int(prepared, 0))
        }
        return 0
    }

    private func iCloudAvailable() -> Bool {
        guard fileManager.ubiquityIdentityToken != nil else {
            return false
        }
        return fileManager.url(forUbiquityContainerIdentifier: nil) != nil
    }
}
