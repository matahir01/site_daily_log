import 'dart:async';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';

/// Backs up and restores the app's local SQLite database directly to/from
/// the signed-in user's *hidden* Google Drive "App Data" folder.
///
/// Using `drive.appdata` (rather than full Drive access) means:
///  - Zero backend cost: no Firebase/Supabase/custom server, just the
///    user's own free Google Drive quota.
///  - The backup file is invisible in the user's normal Drive UI and can
///    only be read/written by this app.
///  - No server-side component to host, maintain, or pay for.
class GoogleDriveService {
  GoogleDriveService._internal();
  static final GoogleDriveService instance = GoogleDriveService._internal();

  static const _backupFileName = 'site_daily_log_backup.db';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? _currentUser;

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  /// Attempts a silent sign-in (e.g. on app start) without showing the
  /// account picker. Returns null if no previous session exists.
  Future<GoogleSignInAccount?> signInSilently() async {
    _currentUser = await _googleSignIn.signInSilently();
    return _currentUser;
  }

  /// Shows the Google account picker and requests Drive App Data access.
  Future<GoogleSignInAccount?> signIn() async {
    _currentUser = await _googleSignIn.signIn();
    return _currentUser;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<drive.DriveApi> _getDriveApi() async {
    var user = _currentUser ?? await _googleSignIn.signInSilently();
    user ??= await _googleSignIn.signIn();
    if (user == null) {
      throw Exception('Google sign-in was cancelled or failed.');
    }
    _currentUser = user;
    final authHeaders = await user.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  Future<String?> _findBackupFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name = '$_backupFileName' and trashed = false",
    );
    if (list.files == null || list.files!.isEmpty) return null;
    return list.files!.first.id;
  }

  /// Uploads the current local database to the app's Drive App Data
  /// folder, replacing any previous backup. Marks all daily logs as
  /// synced on success.
  Future<void> backup() async {
    final api = await _getDriveApi();

    final dbPath = await DatabaseHelper.instance.getDbPath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('No local database found to back up yet.');
    }

    final length = await dbFile.length();
    final media = drive.Media(dbFile.openRead(), length);
    final existingId = await _findBackupFileId(api);

    if (existingId != null) {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      final metadata = drive.File()
        ..name = _backupFileName
        ..parents = ['appDataFolder'];
      await api.files.create(metadata, uploadMedia: media);
    }

    await DatabaseHelper.instance.markAllLogsSynced();
  }

  /// Downloads the most recent backup from Drive App Data and replaces
  /// the local database with it. The app must reopen the database (or be
  /// restarted) after this completes — [DatabaseHelper.database] will
  /// transparently reopen and run any pending migrations.
  Future<void> restore() async {
    final api = await _getDriveApi();
    final fileId = await _findBackupFileId(api);
    if (fileId == null) {
      throw Exception('No backup was found in Google Drive for this account.');
    }

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }

    // Close the current connection before overwriting the file on disk —
    // sqflite keeps a native handle open that must be released first.
    await DatabaseHelper.instance.closeForRestore();
    final dbPath = await DatabaseHelper.instance.getDbPath();
    await File(dbPath).writeAsBytes(bytes, flush: true);

    // Reopen (runs onUpgrade automatically if the restored file is from
    // an older schema version than this build expects).
    await DatabaseHelper.instance.database;
  }

  /// Returns the Drive-reported last-modified time of the backup, or null
  /// if no backup exists yet. Useful for showing "Last backed up: ..." UI.
  Future<DateTime?> getLastBackupTime() async {
    final api = await _getDriveApi();
    final list = await api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name = '$_backupFileName' and trashed = false",
    );
    if (list.files == null || list.files!.isEmpty) return null;
    return list.files!.first.modifiedTime;
  }
}

/// Adapter that injects Google OAuth headers from `google_sign_in` into
/// every request made by the `googleapis` Drive client.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
