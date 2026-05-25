# DBLook

**Right-click any SQLite database in macOS Finder. See the schema. Instantly.**

Three inspection modes. One right-click. The SQLite inspector for developers who use LLMs.

## The Problem

To inspect a SQLite database today, you either memorize `sqlite3` terminal commands, launch a heavy GUI client (TablePlus: $89, DBeaver: 500MB Java app), or dig through documentation. DBLook does it in a right-click — schema, indexes, foreign keys, and sample data, copied to your clipboard and ready to paste into Claude or ChatGPT.

## Modes

| Mode | Menu Label | Output | Use Case |
|------|-----------|--------|----------|
| Inspect | "Inspect Schema" | Clipboard + notification | Quick look, paste into LLM |
| Clipboard | "Schema to Clipboard" | LLM-ready text to clipboard | Feed schema to AI for query help |
| Dump | "Full Dump to File" | Saves `_schema.md` next to the database | Documentation, sharing |

## Install

```bash
git clone https://github.com/opera10r/DBLook.git
cd DBLook
./install.sh
```

The installer will open **System Settings** automatically. Toggle ON all 3 DBLook actions under **Finder Extensions**, then press Enter to finish.

After that, right-click any `.db`, `.sqlite`, or `.sqlite3` file in Finder → **Quick Actions** → pick a DBLook mode.

## Uninstall

```bash
cd DBLook
./uninstall.sh
```

## Features

- **100% read-only**: Opens databases in read-only mode — cannot modify, lock, or corrupt your files
- **Zero dependencies**: Uses macOS built-in `sqlite3` — nothing to install
- **LLM-optimized output**: CREATE statements, column types, constraints, indexes, foreign keys, and sample data formatted for AI consumption
- **Full schema extraction**: Tables, columns, types, primary keys, indexes, foreign keys, views, triggers
- **Sample data preview**: First 10 rows per table in clean columnar format
- **Notifications**: Visual confirmation with table count and row totals

## Example Output

```
═══ DBLook: Database Inspection ═══
File: app.db
Size: 12.4 MB
SQLite Version: 3.51.0
Tables: 5 | Total Rows: 48,231
══════════════════════════════════════════════════

── Table: users (12,450 rows) ──

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    name TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
)

Columns (4):
  id INTEGER [PK]
  email TEXT [NOT NULL]
  name TEXT
  created_at TEXT [DEFAULT CURRENT_TIMESTAMP]

Indexes (1):
  UNIQUE sqlite_autoindex_users_1 (email)

Sample Data (first 10 rows):
  id  name   email           created_at
  --  -----  --------------  ----------
  1   Alice  alice@test.com  2024-01-15
  2   Bob    bob@test.com    2024-02-20
```

## Supported File Types

`.db`, `.sqlite`, `.sqlite3`, `.db3`, `.s3db`, `.sl3`

## Pricing

- **Free**: 1 inspection per day
- **Unlimited**: [$1/month](https://buy.stripe.com/28E8wO9f415CciI7HM2cg04)

To activate after purchase:

```bash
dblook activate <your_license_key>
```

Check your status anytime:

```bash
dblook status
```

## Requirements

- macOS 13+ (Ventura or later)
- No external dependencies

## License

MIT

---

Built by Raven's Gate Publishers LLC
