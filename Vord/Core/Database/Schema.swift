import Foundation

enum SQLValue: Sendable {
    case text(String)
    case integer(Int64)
    case double(Double)
    case null
}

enum SQLiteError: LocalizedError, CustomStringConvertible {
    case message(String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

enum Schema {
    static let currentVersion = 1

    static let v1 = """
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS vocabulary_entries (
      id TEXT PRIMARY KEY,
      english TEXT NOT NULL,
      chinese TEXT NOT NULL,
      lemma TEXT,
      phonetic TEXT,
      part_of_speech TEXT,
      english_definition TEXT,
      chinese_definition TEXT,
      example_sentence TEXT,
      source_sentence TEXT,
      source TEXT,
      tags_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_entries_english ON vocabulary_entries(english);
    CREATE INDEX IF NOT EXISTS idx_entries_chinese ON vocabulary_entries(chinese);
    CREATE INDEX IF NOT EXISTS idx_entries_created ON vocabulary_entries(created_at);

    CREATE TABLE IF NOT EXISTS review_direction_states (
      entry_id TEXT NOT NULL,
      direction TEXT NOT NULL,
      due_at TEXT NOT NULL,
      last_reviewed_at TEXT,
      stage INTEGER NOT NULL,
      interval_seconds REAL NOT NULL,
      difficulty REAL NOT NULL,
      stability REAL NOT NULL,
      review_count INTEGER NOT NULL,
      lapse_count INTEGER NOT NULL,
      correct_count INTEGER NOT NULL,
      incorrect_count INTEGER NOT NULL,
      PRIMARY KEY (entry_id, direction),
      FOREIGN KEY (entry_id) REFERENCES vocabulary_entries(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_review_due ON review_direction_states(direction, due_at);

    CREATE TABLE IF NOT EXISTS review_logs (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL,
      direction TEXT NOT NULL,
      rating TEXT NOT NULL,
      reviewed_at TEXT NOT NULL,
      previous_due_at TEXT,
      scheduled_due_at TEXT NOT NULL,
      interval_seconds REAL NOT NULL,
      FOREIGN KEY (entry_id) REFERENCES vocabulary_entries(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_logs_reviewed ON review_logs(reviewed_at);
    """
}
