import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Abre (y crea la primera vez) la base de datos SQLite del celular.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'bicicrew.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE activities (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,                       -- recording | finished
            started_at INTEGER NOT NULL,                -- milisegundos epoch
            ended_at INTEGER,
            duration_s INTEGER NOT NULL DEFAULT 0,
            distance_m REAL NOT NULL DEFAULT 0,
            elevation_gain_m REAL NOT NULL DEFAULT 0,
            sync_status TEXT NOT NULL DEFAULT 'pending', -- pending | synced | error
            sync_error TEXT
          )''');
        await db.execute('''
          CREATE TABLE points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            activity_id TEXT NOT NULL,
            segment INTEGER NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            alt REAL NOT NULL,
            accuracy REAL NOT NULL,
            time INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_points_activity ON points(activity_id, id)');
      },
    );
  }
}