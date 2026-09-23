# Persistence and search verification

Run from `DaBin/native`:

```sh
./scripts/test.sh --storage-only
```

Result on this Mac: **171 assertions passed**, including all 10 supplied search fixtures. Tests use a unique temporary directory, delete only their own fixtures, and do not access personal documents, the system clipboard, the network, or notification permission. Core Data prints expected diagnostics for the intentionally corrupt database test; the runner verifies the database bytes were preserved.

## Local store

The installed command-line tools contain SwiftData interfaces but lack the `SwiftDataMacros` compiler plugin supplied with full Xcode. This implementation therefore uses Apple's Core Data SQLite store, with an explicit `DaBinV1` model and a versioned Codable capture payload. UI objects retain the same Capture/CaptureStore interface. There is no CloudKit configuration or automatic destructive store recovery. Newer payload/schema versions fail clearly and require a deliberate migration.

Capture identity, receipt timestamp, local Gregorian day, receipt timezone and receipt UTC offset have private setters. Edits and preview updates cannot move a capture to another day. Captures, comments and reminder revisions survive reopening the local store. HTTP(S)-only multiline pastes commit all their individual links in one metadata transaction; mixed prose stays one verbatim text capture.

## Dated local archive

The current storage run passes 171 domain, 50 archive-layout and 81 archive-integration checks, alongside service/task/input suites. Tests cover Gregorian English names, immutable local dates and offsets, exact UTF-8, duplicate names, sidecar identity, external-edit preservation, symlink/traversal guards, stable reopen, legacy copy/verify/commit migration, destination conflicts, old/new journals and post-commit readable-file failure repair. Production metadata access is separately factored into CaptureRepository; invalid stores are preserved.

## Tasks

Schema 3 adds explicit task captures and completion state. Existing schema 1/2 records decode as incomplete without changing their kind or receipt fields. Tests cover task/reminder creation together, invalid/empty input, write-failure compensation, completion rollback, reopening, search membership, immutable receipt data, notification cancellation/resume and completion during an in-flight schedule.

## Source provenance

New payloads use schema 2 and store optional original file paths and explicit source URLs. Schema 1 records and older recovery journals remain readable with unknown provenance. Actual file imports save their source path before copying into managed storage; copied bytes and promised files never claim DaBin staging as their origin. Supplied text provenance is retained when available, and ordinary plain text stays unknown. Tests cover reopening, source deletion, and recovery with both old and new payloads.

## Original import protocol

1. Allocate a UUID and freeze receipt metadata before awaiting background I/O.
2. Persist an import journal and copy into its uniquely owned Staging directory. Directories, symlinks, aliases and other nonregular files are rejected.
3. Verify the finished managed copy by streaming its byte count and SHA-256. Record both in the journal.
4. Move the file to its dated capture folder’s Original directory on the same volume.
5. Commit metadata synchronously. Only a committed capture is returned as saved.
6. Remove the completed journal and staging directory.

On an ordinary failure before commit, only that import's files and pending metadata are compensated. Failure after commit retains the saved capture. Relaunch recovers a verified staged/moved original with its original receipt stamp, and avoids duplicating an already committed capture. Partial, malformed, hash-mismatched or unclaimed data is preserved and reported for recovery. The source file is never deleted or modified. Two equal filenames receive different UUID directories.

The checksum establishes integrity of the completed managed copy and subsequent recovery. Source applications can modify a file during import; no filesystem-wide snapshot or lock of an external source is claimed. Tests verify that managed originals remain readable after deleting the source and reopening the store.

## Verified cases

- Empty input rejection; supported HTTP(S) links; URL batches; mixed text; unsafe/custom schemes remain text.
- File extension/type fallback, specialist AI files, group filters, sanitized storage names, no overwrites.
- Midnight/year rollover, repeated DST hour offsets, immutable dates after comment/reminder changes and reopen.
- Normalized AND search, case/diacritics, newest matching dates, same-day immediate neighbors, overlapping context deduplication, type filters applied to matches, UUID tie ordering.
- Pre-copy, post-copy, post-move and pre-metadata failures preserve existing captures and remove only owned temporary files.
- Simulated abrupt interruption at each stage; recovery at most once, preserved bytes and receipt date; postcommit cleanup failure still returns a saved capture.
- Corrupt staged bytes are preserved without a false saved card. A corrupt SQLite file is rejected without replacement.

The failure injection hook is unset in normal operation. These tests do not establish native drag delivery, corner hit testing, notification presentation, or UI appearance; those require separate application integration checks.
