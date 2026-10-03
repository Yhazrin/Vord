import Foundation

enum SyncSchema {
    static func install(in database: AppDatabase, db: OpaquePointer) throws {
        try database.exec(db, """
        CREATE TABLE IF NOT EXISTS sync_outbox (
          kind TEXT NOT NULL, record_id TEXT NOT NULL, clock INTEGER NOT NULL,
          device_id TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (kind,record_id)
        );
        CREATE TABLE IF NOT EXISTS sync_baselines (
          kind TEXT NOT NULL, record_id TEXT NOT NULL, payload TEXT,
          PRIMARY KEY (kind,record_id)
        );
        CREATE TABLE IF NOT EXISTS sync_tombstones (entry_id TEXT PRIMARY KEY);
        INSERT OR IGNORE INTO meta(key,value) VALUES ('sync.clock','0'),('sync.cursor','0'),('sync.applying','0');
        """)
        try database.run(db, "INSERT OR IGNORE INTO meta(key,value) VALUES ('sync.device',?)", [.text(UUID().uuidString)])
        for (table, kind, id) in [
            ("vocabulary_entries", "entry", "id"),
            ("review_direction_states", "direction", "entry_id || '/' || NEW.direction"),
            ("review_logs", "log", "id")
        ] {
            for action in ["INSERT", "UPDATE", "DELETE"] {
                // State/log deletion follows the parent tombstone; individual history is immutable.
                if action == "DELETE" && kind != "entry" { continue }
                let row = action == "DELETE" ? "OLD" : "NEW"
                let expr = id == "id" ? "\(row).id" : "NEW.\(id)"
                let tombstone = action == "DELETE" ? "INSERT OR IGNORE INTO sync_tombstones(entry_id) VALUES (OLD.id);" : ""
                try database.exec(db, """
                CREATE TRIGGER IF NOT EXISTS sync_\(kind)_\(action.lowercased()) AFTER \(action) ON \(table)
                WHEN (SELECT value FROM meta WHERE key='sync.applying')='0'
                BEGIN
                  UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='sync.clock';
                  INSERT OR REPLACE INTO sync_outbox(kind,record_id,clock,device_id,deleted)
                  VALUES ('\(kind)',\(expr),(SELECT CAST(value AS INTEGER) FROM meta WHERE key='sync.clock'),
                    (SELECT value FROM meta WHERE key='sync.device'),\(action == "DELETE" ? 1 : 0));
                  \(tombstone)
                END;
                """)
            }
        }
        if try database.query(db, "SELECT value FROM meta WHERE key='sync.bootstrapped'").isEmpty {
            try bootstrap(in: database, db: db)
            try database.exec(db, "INSERT INTO meta(key,value) VALUES ('sync.bootstrapped','1')")
        }
    }
    static func bootstrap(in database: AppDatabase, db: OpaquePointer) throws {
        for (kind, sql) in [
            ("entry", "SELECT id AS record_id FROM vocabulary_entries ORDER BY id"),
            ("direction", "SELECT entry_id || '/' || direction AS record_id FROM review_direction_states ORDER BY entry_id,direction"),
            ("log", "SELECT id AS record_id FROM review_logs ORDER BY id")
        ] {
            for row in try database.query(db, sql) {
                guard let id = row.text("record_id") else { continue }
                try database.exec(db, "UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='sync.clock'")
                try database.run(db, """
                  INSERT OR REPLACE INTO sync_outbox(kind,record_id,clock,device_id,deleted)
                  VALUES (?,?,(SELECT CAST(value AS INTEGER) FROM meta WHERE key='sync.clock'),
                    (SELECT value FROM meta WHERE key='sync.device'),0)
                  """, [.text(kind), .text(id)])
            }
        }
    }
}
