/**
 * Cangmo - document storage engine.
 *
 * A small, crash-safe, append-only document store:
 *   - an in-memory map of collection -> id -> JSON document
 *   - an fsync-free write-ahead log (one JSON record per line) for durability
 *   - atomic snapshots (temp file + rename) with a .bak fallback
 *   - automatic compaction when the log grows
 *
 * It is deliberately independent from any SQL database or third-party storage
 * library. All data is ordinary JSON and can be exported/inspected easily.
 */
package cangmo.store

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.fs.*
import std.sync.*
import std.sort.*

public let STORE_FORMAT_VERSION: Int64 = 1
public let WAL_COMPACT_ENTRIES: Int64 = 2000
public let WAL_COMPACT_BYTES: Int64 = 4 * 1024 * 1024

public class Store {
    private let mutex: Mutex = Mutex()
    private let rootDir: String
    private let snapshotPath: String
    private let backupPath: String
    private let walPath: String
    private let persist: Bool
    private var data: HashMap<String, HashMap<String, JsonValue>> = HashMap<String, HashMap<String, JsonValue>>()
    private var walEntries: Int64 = 0
    private var walBytes: Int64 = 0
    private var startupWarnings: ArrayList<String> = ArrayList<String>()
    private var closed: Bool = false

    public init(rootDir: String, persist!: Bool = true) {
        this.rootDir = rootDir
        this.snapshotPath = rootDir + "/db.json"
        this.backupPath = rootDir + "/db.json.bak"
        this.walPath = rootDir + "/wal.log"
        this.persist = persist
        if (persist) {
            ensureDir(rootDir)
        }
        loadSnapshot()
        if (persist) {
            loadWal()
        }
    }

    public func warnings(): Array<String> {
        synchronized(mutex) {
            startupWarnings.toArray()
        }
    }

    public func collectionNames(): Array<String> {
        synchronized(mutex) {
            let names = data.keys().toArray()
            sortStrings(names)
            names
        }
    }

    public func exists(collection: String, id: String): Bool {
        synchronized(mutex) {
            match (data.get(collection)) {
                case Some(col) => col.contains(id)
                case None => false
            }
        }
    }

    /**
     * Returns a read-only view of the document. Callers MUST NOT mutate the
     * returned JsonValue; use getForUpdate() when a mutable copy is needed.
     */
    public func get(collection: String, id: String): ?JsonValue {
        synchronized(mutex) {
            match (data.get(collection)) {
                case Some(col) => col.get(id)
                case None => None
            }
        }
    }

    public func getForUpdate(collection: String, id: String): ?JsonValue {
        match (get(collection, id)) {
            case Some(doc) => Some(cloneJson(doc))
            case None => None
        }
    }

    public func list(collection: String): Array<JsonValue> {
        synchronized(mutex) {
            let out = ArrayList<JsonValue>()
            match (data.get(collection)) {
                case Some(col) =>
                    for ((_, doc) in col) {
                        out.add(doc)
                    }
                case None => ()
            }
            out.toArray()
        }
    }

    public func listIds(collection: String): Array<String> {
        synchronized(mutex) {
            let out = ArrayList<String>()
            match (data.get(collection)) {
                case Some(col) =>
                    for (id in col.keys()) {
                        out.add(id)
                    }
                case None => ()
            }
            out.toArray()
        }
    }

    public func count(collection: String): Int64 {
        synchronized(mutex) {
            match (data.get(collection)) {
                case Some(col) => col.size
                case None => 0
            }
        }
    }

    public func put(collection: String, id: String, doc: JsonValue): Unit {
        if (!persist) {
            synchronized(mutex) {
                putMemory(collection, id, doc)
            }
            return
        }
        synchronized(mutex) {
            if (closed) {
                throw AppError("storage", "store is closed")
            }
            let col = ensureCollection(collection)
            let previous = col.get(id)
            col[id] = cloneJson(doc)
            try {
                appendWalLocked(collection, id, doc, true)
            } catch (e: Exception) {
                match (previous) {
                    case Some(oldDoc) => col[id] = oldDoc
                    case None => col.remove(id)
                }
                throw AppError("storage", "failed to persist document: ${e.message}")
            }
            if (walEntries >= WAL_COMPACT_ENTRIES || walBytes >= WAL_COMPACT_BYTES) {
                compactLocked()
            }
        }
    }

    public func delete(collection: String, id: String): Bool {
        if (!persist) {
            synchronized(mutex) {
                match (data.get(collection)) {
                    case Some(col) => col.remove(id)
                    case None => ()
                }
            }
            return true
        }
        synchronized(mutex) {
            if (closed) {
                throw AppError("storage", "store is closed")
            }
            match (data.get(collection)) {
                case Some(col) =>
                    if (!col.contains(id)) {
                        return false
                    }
                    let old = col[id]
                    col.remove(id)
                    try {
                        appendDeleteWalLocked(collection, id)
                    } catch (e: Exception) {
                        col[id] = old
                        throw AppError("storage", "failed to persist deletion: ${e.message}")
                    }
                    if (walEntries >= WAL_COMPACT_ENTRIES || walBytes >= WAL_COMPACT_BYTES) {
                        compactLocked()
                    }
                    true
                case None => false
            }
        }
    }

    public func compact(): Unit {
        if (!persist) {
            return
        }
        synchronized(mutex) {
            compactLocked()
        }
    }

    public func exportAll(): JsonValue {
        synchronized(mutex) {
            let collections = JsonObject()
            for ((name, col) in data) {
                let obj = JsonObject()
                for ((id, doc) in col) {
                    obj.set(id, doc)
                }
                collections.set(name, JObj(obj))
            }
            let root = JsonObject()
            root.set("format", JInt(STORE_FORMAT_VERSION))
            root.set("version", JStr(APP_VERSION))
            root.set("savedAt", JInt(nowSeconds()))
            root.set("collections", JObj(collections))
            JObj(root)
        }
    }

    /**
     * Replace the entire store with an exported document. The snapshot is
     * written before the write-ahead log is cleared, so an interrupted import
     * can be retried safely.
     */
    public func replaceAll(exported: JsonValue): Int64 {
        if (!persist) {
            throw AppError("storage", "import requires a persistent store")
        }
        synchronized(mutex) {
            let collectionsValue = match (exported.get("collections")) {
                case Some(JObj(o)) => JObj(o)
                case _ => exported
            }
            let collections = match (collectionsValue.asObject()) {
                case Some(o) => o
                case None => throw AppError("validation", "invalid backup: missing collections")
            }
            let fresh = HashMap<String, HashMap<String, JsonValue>>()
            var total: Int64 = 0
            for ((name, value) in collections.fields) {
                if (!isSafeName(name)) {
                    throw AppError("validation", "invalid collection name in backup")
                }
                match (value.asObject()) {
                    case Some(colObj) =>
                        let col = HashMap<String, JsonValue>()
                        for ((id, doc) in colObj.fields) {
                            if (!isSafeId(id)) {
                                throw AppError("validation", "invalid document id in backup")
                            }
                            if (!isJsonObjectValue(doc)) {
                                throw AppError("validation", "invalid document in backup")
                            }
                            col[id] = cloneJson(doc)
                            total += 1
                        }
                        fresh[name] = col
                    case None => throw AppError("validation", "invalid collection in backup: ${name}")
                }
            }
            data = fresh
            writeSnapshotLocked()
            clearWalLocked()
            total
        }
    }

    public func close(): Unit {
        if (!persist) {
            return
        }
        synchronized(mutex) {
            if (closed) {
                return
            }
            compactLocked()
            closed = true
        }
    }

    public func pendingWalEntries(): Int64 {
        synchronized(mutex) {
            walEntries
        }
    }

    // -----------------------------------------------------------------------
    // internals
    // -----------------------------------------------------------------------

    private func ensureCollection(collection: String): HashMap<String, JsonValue> {
        if (!isSafeName(collection)) {
            throw AppError("validation", "invalid collection name")
        }
        if (!data.contains(collection)) {
            data[collection] = HashMap<String, JsonValue>()
        }
        data[collection]
    }

    private func putMemory(collection: String, id: String, doc: JsonValue): Unit {
        if (!isSafeId(id)) {
            throw AppError("validation", "invalid document id")
        }
        let col = ensureCollection(collection)
        col[id] = cloneJson(doc)
    }

    private func appendWalLocked(collection: String, id: String, doc: JsonValue, isPut: Bool): Unit {
        let record = JsonObject()
        record.set("op", JStr("put"))
        record.set("col", JStr(collection))
        record.set("id", JStr(id))
        record.set("doc", doc)
        let line = toJsonCompact(JObj(record)) + "\n"
        appendTextFile(walPath, line)
        walEntries += 1
        walBytes += line.size
    }

    private func appendDeleteWalLocked(collection: String, id: String): Unit {
        let record = JsonObject()
        record.set("op", JStr("del"))
        record.set("col", JStr(collection))
        record.set("id", JStr(id))
        let line = toJsonCompact(JObj(record)) + "\n"
        appendTextFile(walPath, line)
        walEntries += 1
        walBytes += line.size
    }

    private func loadSnapshot(): Unit {
        if (!persist) {
            return
        }
        if (!exists(snapshotPath)) {
            return
        }
        match (readSnapshotFile(snapshotPath)) {
            case Some(root) =>
                loadCollections(root)
            case None =>
                startupWarnings.add("db.json is invalid, trying db.json.bak")
                if (exists(backupPath)) {
                    match (readSnapshotFile(backupPath)) {
                        case Some(root) => loadCollections(root)
                        case None => throw AppError("storage", "both db.json and db.json.bak are corrupt")
                    }
                } else {
                    throw AppError("storage", "db.json is corrupt and no backup exists")
                }
        }
    }

    private func readSnapshotFile(path: String): ?JsonValue {
        try {
            let text = readTextFile(path)
            if (isBlank(text)) {
                return None
            }
            return Some(parseJson(text))
        } catch (e: Exception) {
            return None
        }
    }

    private func loadCollections(root: JsonValue) {
        let collections = match (root.get("collections")) {
            case Some(JObj(o)) => JObj(o)
            case _ => root
        }
        match (collections.asObject()) {
            case Some(obj) =>
                for ((name, value) in obj.fields) {
                    if (!isSafeName(name)) {
                        startupWarnings.add("skipped invalid collection name: ${name}")
                        continue
                    }
                    match (value.asObject()) {
                        case Some(colObj) =>
                            let col = HashMap<String, JsonValue>()
                            for ((id, doc) in colObj.fields) {
                                if (!isSafeId(id) || !isJsonObjectValue(doc)) {
                                    startupWarnings.add("skipped invalid document ${id} in ${name}")
                                    continue
                                }
                                col[id] = doc
                            }
                            data[name] = col
                        case None =>
                            startupWarnings.add("skipped invalid collection: ${name}")
                    }
                }
            case None =>
                throw AppError("storage", "invalid database snapshot")
        }
    }

    private func loadWal(): Unit {
        if (!exists(walPath)) {
            return
        }
        var corrupt = false
        let text = try {
            readTextFile(walPath)
        } catch (e: Exception) {
            startupWarnings.add("could not read wal.log: ${e.message}")
            return
        }
        let lines = text.split("\n")
        var index: Int64 = 0
        for (line in lines) {
            index += 1
            if (isBlank(line)) {
                continue
            }
            let parsed = tryParseJson(line)
            match (parsed) {
                case Some(record) =>
                    applyWalRecord(record)
                    walEntries += 1
                    walBytes += line.size + 1
                case None =>
                    corrupt = true
                    startupWarnings.add("ignored corrupt wal record at line ${index}")
            }
        }
        if (corrupt) {
            // Rewrite the log from the in-memory state to discard the damaged tail.
            compactLocked()
        }
    }

    private func applyWalRecord(record: JsonValue): Unit {
        let op = getString(record, "op", def: "")
        let collection = getString(record, "col", def: "")
        let id = getString(record, "id", def: "")
        if (!isSafeName(collection) || !isSafeId(id)) {
            startupWarnings.add("ignored wal record with unsafe names")
            return
        }
        if (op == "put") {
            match (record.get("doc")) {
                case Some(doc) =>
                    if (!isJsonObjectValue(doc)) {
                        startupWarnings.add("ignored wal put with invalid document")
                        return
                    }
                    putMemory(collection, id, doc)
                case None => startupWarnings.add("ignored wal put without document")
            }
        } else if (op == "del") {
            match (data.get(collection)) {
                case Some(col) => col.remove(id)
                case None => ()
            }
        } else {
            startupWarnings.add("ignored wal record with unknown op: ${op}")
        }
    }

    private func writeSnapshotLocked(): Unit {
        let payload = exportAllLocked()
        let text = toJson(payload, pretty: false)
        if (exists(snapshotPath)) {
            try {
                copy(snapshotPath, to: backupPath, overwrite: true)
            } catch (e: Exception) {
                startupWarnings.add("could not refresh db.json.bak: ${e.message}")
            }
        }
        writeTextAtomic(snapshotPath, text)
    }

    private func exportAllLocked(): JsonValue {
        let collections = JsonObject()
        for ((name, col) in data) {
            let obj = JsonObject()
            for ((id, doc) in col) {
                obj.set(id, doc)
            }
            collections.set(name, JObj(obj))
        }
        let root = JsonObject()
        root.set("format", JInt(STORE_FORMAT_VERSION))
        root.set("version", JStr(APP_VERSION))
        root.set("savedAt", JInt(nowSeconds()))
        root.set("collections", JObj(collections))
        JObj(root)
    }

    private func compactLocked(): Unit {
        if (!persist) {
            return
        }
        writeSnapshotLocked()
        clearWalLocked()
    }

    private func clearWalLocked(): Unit {
        if (exists(walPath)) {
            try {
                remove(walPath, recursive: false)
            } catch (e: Exception) {
                startupWarnings.add("could not truncate wal.log: ${e.message}")
            }
        }
        walEntries = 0
        walBytes = 0
    }
}

public func isSafeName(name: String): Bool {
    if (name.size < 1 || name.size > 64) {
        return false
    }
    for (b in name.toArray()) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x5F || b == 0x2D
        if (!ok) {
            return false
        }
    }
    return true
}

public func isSafeId(id: String): Bool {
    if (id.size < 1 || id.size > 128) {
        return false
    }
    for (b in id.toArray()) {
        let ok = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) ||
                 (b >= 0x30 && b <= 0x39) || b == 0x5F || b == 0x2D || b == 0x3A
        if (!ok) {
            return false
        }
    }
    return true
}

func isJsonObjectValue(value: JsonValue): Bool {
    match (value) {
        case JObj(_) => true
        case _ => false
    }
}

func sortStrings(items: Array<String>) {
    sort<String>(items)
}
