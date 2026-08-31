import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;

  // Bump this whenever the schema changes and add a matching branch in
  // _onUpgrade below. Never edit old migration steps once released.
  static const int _dbVersion = 2;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  /// Full path to the underlying sqlite file, used by [GoogleDriveService]
  /// to read/replace the raw database file for backup and restore.
  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'site_daily_log.db');
  }

  /// Closes the current connection so the file can be safely overwritten
  /// (e.g. during a Drive restore). Call [database] again afterwards to
  /// reopen it.
  Future<void> closeForRestore() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDb() async {
    final path = await getDbPath();
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Required for ON DELETE CASCADE to actually cascade in SQLite.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        client TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL,
        name TEXT NOT NULL,
        address TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_logs (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        weather TEXT,
        crewCount INTEGER,
        workCompleted TEXT,
        issues TEXT,
        photoPaths TEXT,
        lat REAL,
        lng REAL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        receiptPhotoPath TEXT,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE materials_and_equipment (
        id TEXT PRIMARY KEY,
        log_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT,
        category TEXT NOT NULL DEFAULT 'material',
        FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Each `if` runs independently so an install can hop from any older
    // version straight to the newest schema in one open() call.
    if (oldVersion < 2) {
      // v1 -> v2: cloud-backup readiness + materials/equipment tracking.
      // `weather`, `lat`, `lng` already existed on daily_logs since v1;
      // only is_synced is new here.
      await db.execute('ALTER TABLE daily_logs ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS materials_and_equipment (
          id TEXT PRIMARY KEY,
          log_id TEXT NOT NULL,
          item_name TEXT NOT NULL,
          quantity REAL NOT NULL,
          unit TEXT,
          category TEXT NOT NULL DEFAULT 'material',
          FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // ---------- Projects ----------
  Future<void> insertProject(Project p) async {
    final db = await database;
    await db.insert('projects', p.toMap());
  }

  Future<List<Project>> getProjects() async {
    final db = await database;
    final rows = await db.query('projects', orderBy: 'createdAt DESC');
    return rows.map((r) => Project.fromMap(r)).toList();
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Sites ----------
  Future<void> insertSite(Site s) async {
    final db = await database;
    await db.insert('sites', s.toMap());
  }

  Future<List<Site>> getSitesForProject(String projectId) async {
    final db = await database;
    final rows = await db.query('sites', where: 'projectId = ?', whereArgs: [projectId], orderBy: 'createdAt DESC');
    return rows.map((r) => Site.fromMap(r)).toList();
  }

  Future<void> deleteSite(String id) async {
    final db = await database;
    await db.delete('sites', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Daily Logs ----------
  Future<void> insertDailyLog(DailyLog log) async {
    final db = await database;
    await db.insert('daily_logs', log.toMap());
  }

  Future<List<DailyLog>> getLogsForSite(String siteId) async {
    final db = await database;
    final rows = await db.query('daily_logs', where: 'siteId = ?', whereArgs: [siteId], orderBy: 'date DESC');
    return rows.map((r) => DailyLog.fromMap(r)).toList();
  }

  Future<void> deleteDailyLog(String id) async {
    final db = await database;
    await db.delete('daily_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDailyLog(DailyLog log) async {
    final db = await database;
    await db.update('daily_logs', log.toMap(), where: 'id = ?', whereArgs: [log.id]);
  }

  /// Marks every daily log as synced. Called after a successful Drive
  /// backup so the dashboard's "Pending Sync" count reflects reality.
  Future<void> markAllLogsSynced() async {
    final db = await database;
    await db.update('daily_logs', {'is_synced': 1});
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM daily_logs WHERE is_synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM daily_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------- Materials & Equipment ----------
  Future<void> insertMaterialItem(MaterialItem item) async {
    final db = await database;
    await db.insert('materials_and_equipment', item.toMap());
  }

  Future<List<MaterialItem>> getMaterialsForLog(String logId) async {
    final db = await database;
    final rows = await db.query('materials_and_equipment', where: 'log_id = ?', whereArgs: [logId]);
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<List<MaterialItem>> getMaterialsForSite(String siteId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.* FROM materials_and_equipment m
      INNER JOIN daily_logs l ON m.log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date DESC
    ''', [siteId]);
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<void> deleteMaterialItem(String id) async {
    final db = await database;
    await db.delete('materials_and_equipment', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMaterialsForLog(String logId) async {
    final db = await database;
    await db.delete('materials_and_equipment', where: 'log_id = ?', whereArgs: [logId]);
  }

  // ---------- Expenses ----------
  Future<void> insertExpense(Expense e) async {
    final db = await database;
    await db.insert('expenses', e.toMap());
  }

  Future<List<Expense>> getExpensesForSite(String siteId) async {
    final db = await database;
    final rows = await db.query('expenses', where: 'siteId = ?', whereArgs: [siteId], orderBy: 'date DESC');
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<List<Expense>> getExpensesForProject(String projectId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.* FROM expenses e
      INNER JOIN sites s ON e.siteId = s.id
      WHERE s.projectId = ?
      ORDER BY e.date DESC
    ''', [projectId]);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<double> getTotalExpensesForProject(String projectId) async {
    final expenses = await getExpensesForProject(projectId);
    return expenses.fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateExpense(Expense e) async {
    final db = await database;
    await db.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }
}
