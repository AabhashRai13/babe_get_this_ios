import Foundation

// Port of Android `core/sync/data/mapper/SyncMappers.kt`.

enum SyncMappingError: Error, Equatable, Sendable {
    /// Rows read back from the server always carry `updated_at`; one without it is rejected.
    case missingServerClock
    case invalidTimestamp(String)
}

// MARK: - ISO-8601 timestamptz ↔ epoch millis

extension String {
    /// Matches kotlinx `Instant.parse(this).toEpochMilliseconds()`: accepts `Z` or a numeric offset and any
    /// fraction of a second (PostgREST sends microseconds), flooring to whole milliseconds.
    func isoToMillis() throws -> Int64 {
        guard let millis = ISOTimestamp.parse(self) else { throw SyncMappingError.invalidTimestamp(self) }
        return millis
    }
}

extension Int64 {
    /// Matches kotlinx `Instant.fromEpochMilliseconds(this).toString()`: UTC with `Z`, and a three-digit
    /// fraction only when the milliseconds are non-zero.
    func millisToIso() -> String {
        ISOTimestamp.format(self)
    }
}

private enum ISOTimestamp {
    static func parse(_ text: String) -> Int64? {
        var scanner = Scanner(Array(text.utf8))
        guard let year = scanner.digits(4), scanner.take("-"),
              let month = scanner.digits(2), scanner.take("-"),
              let day = scanner.digits(2), scanner.take("T") || scanner.take("t"),
              let hour = scanner.digits(2), scanner.take(":"),
              let minute = scanner.digits(2), scanner.take(":"),
              let second = scanner.digits(2)
        else { return nil }
        guard (1...12).contains(month), (1...daysIn(month: month, year: year)).contains(day),
              hour < 24, minute < 60, second < 60
        else { return nil }

        var fractionMillis: Int64 = 0
        if scanner.take(".") || scanner.take(",") {
            var count = 0
            while let digit = scanner.digit() {
                if count < 3 { fractionMillis = fractionMillis * 10 + digit }
                count += 1
            }
            guard (1...9).contains(count) else { return nil }
            for _ in min(count, 3)..<3 { fractionMillis *= 10 }
        }

        let offsetSeconds: Int64
        if scanner.take("Z") || scanner.take("z") {
            offsetSeconds = 0
        } else if let sign = scanner.offsetSign(),
                  let offsetHour = scanner.digits(2), offsetHour <= 18 {
            var offsetMinute: Int64 = 0
            let hasColon = scanner.take(":")
            if let minutes = scanner.digits(2) {
                offsetMinute = minutes
            } else if hasColon {
                return nil
            }
            guard offsetMinute < 60 else { return nil }
            offsetSeconds = sign * (offsetHour * 3600 + offsetMinute * 60)
        } else {
            return nil
        }
        guard scanner.atEnd else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return seconds * 1000 + fractionMillis
    }

    static func format(_ millis: Int64) -> String {
        let seconds = floorDiv(millis, 1000)
        let fraction = millis - seconds * 1000
        let days = floorDiv(seconds, 86_400)
        let secondOfDay = seconds - days * 86_400
        let (year, month, day) = civilFromDays(days)
        var text = String(
            format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld",
            year, month, day, secondOfDay / 3600, secondOfDay % 3600 / 60, secondOfDay % 60
        )
        if fraction != 0 { text += String(format: ".%03lld", fraction) }
        return text + "Z"
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    private static func isLeap(_ year: Int64) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private static func daysIn(month: Int64, year: Int64) -> Int64 {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian, day 0 = 1970-01-01).
    private static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index == bytes.count }

        mutating func take(_ character: Character) -> Bool {
            guard index < bytes.count, let ascii = character.asciiValue, bytes[index] == ascii else { return false }
            index += 1
            return true
        }

        mutating func offsetSign() -> Int64? {
            if take("+") { return 1 }
            if take("-") { return -1 }
            return nil
        }

        mutating func digit() -> Int64? {
            guard index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else { return nil }
            defer { index += 1 }
            return Int64(bytes[index] - UInt8(ascii: "0"))
        }

        /// Exactly `count` digits, or nil without consuming anything.
        mutating func digits(_ count: Int) -> Int64? {
            let start = index
            var value: Int64 = 0
            for _ in 0..<count {
                guard let d = digit() else {
                    index = start
                    return nil
                }
                value = value * 10 + d
            }
            return value
        }
    }
}

// MARK: - local record → row (push direction)

extension LocalListRecord {
    func toRow(createdBy: String) -> ListRow {
        ListRow(
            id: id,
            name: name,
            shareCode: shareCode,
            createdBy: createdBy,
            createdAt: createdAt.millisToIso(),
            deletedAt: deletedAt?.millisToIso()
        )
    }
}

extension LocalItemRecord {
    /// Never carries `picked_up_at`: iOS v1 acts as a pre-Got-This client.
    func toRow() -> ItemRow {
        ItemRow(
            id: id,
            listId: listId,
            name: name,
            quantity: quantity,
            isPickedUp: isPickedUp,
            categoryId: categoryId,
            shop: shop,
            note: note,
            deletedAt: deletedAt?.millisToIso()
        )
    }
}

// MARK: - row → local record (apply direction)
//
// Incoming rows land as clean (pendingSync = false) records whose updatedAt carries the SERVER clock in
// millis — that's what later LWW comparisons run against. `local` is the row currently stored (any state,
// may be nil): device-local concerns (createdAt ordering, the PIN lock) survive from it. A list row from the
// server is the signed-in account's and is on the server by definition; a list this device had locked before
// sign-out evicted it comes back locked (`lockedIds`, docs/technical-decisions/008).

extension ListRow {
    func toRecord(local: LocalListRecord?, accountId: String, lockedIds: Set<String>) throws -> LocalListRecord {
        guard let updatedAt else { throw SyncMappingError.missingServerClock }
        let serverMs = try updatedAt.isoToMillis()
        return LocalListRecord(
            id: id,
            name: name,
            // This phone's own record of when the list was made wins, then the server's, so a list that comes
            // back after sign-out (or onto another phone) keeps its place on the lists screen.
            createdAt: try local?.createdAt ?? createdAt?.isoToMillis() ?? serverMs,
            updatedAt: serverMs,
            isLocked: local?.isLocked ?? lockedIds.contains(id), // per-device, never synced
            shareCode: shareCode,
            deletedAt: try deletedAt?.isoToMillis(),
            pendingSync: false,
            accountId: accountId,
            onServer: true
        )
    }
}

extension ItemRow {
    func toRecord(local: LocalItemRecord?) throws -> LocalItemRecord {
        guard let updatedAt else { throw SyncMappingError.missingServerClock }
        let serverMs = try updatedAt.isoToMillis()
        return LocalItemRecord(
            id: id,
            listId: listId,
            name: name,
            quantity: quantity,
            isPickedUp: isPickedUp,
            categoryId: categoryId, // opaque; unknown ids render as uncategorised
            shop: shop,
            note: note,
            createdAt: local?.createdAt ?? serverMs,
            updatedAt: serverMs,
            deletedAt: try deletedAt?.isoToMillis(),
            pendingSync: false
        )
    }
}
