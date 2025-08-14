import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'ssh_client_window.dart' show SSHProfile;

class SftpWindow extends StatefulWidget {
  final Map<String, dynamic> profile;
  final WindowController controller;

  const SftpWindow({
    super.key,
    required this.profile,
    required this.controller,
  });

  @override
  State<SftpWindow> createState() => _SftpWindowState();
}

class _SftpWindowState extends State<SftpWindow> {
  SSHClient? _ssh;
  SftpClient? _sftp;

  String _localPath = _defaultLocalHome();
  String _remotePath = '/';

  final _localPathCtrl = TextEditingController();
  final _remotePathCtrl = TextEditingController();

  List<_FileItem> _localAll = [];
  List<_FileItem> _localFiles = [];
  List<_FileItem> _remoteAll = [];
  List<_FileItem> _remoteFiles = [];

  String _localFilter = '';
  String _remoteFilter = '';

  int? _selectedLocal;
  int? _selectedRemote;

  Set<int> _selLocal = {};
  Set<int> _selRemote = {};
  int? _anchorLocal, _anchorRemote;

  bool _busy = false;
  String? _bannerError;
  String? _status;
  double? _progress;

  late SSHProfile _profile;
  bool _profileReady = false;

  // ===== modifier keys =====
  bool get _shiftDown {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool get _ctrlCmdDown {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  @override
  void initState() {
    super.initState();

    ErrorWidget.builder = (details) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'Terjadi error:\n${details.exceptionAsString()}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    };
    PlatformDispatcher.instance.onError = (e, st) {
      _setBanner('Error: $e');
      return true;
    };

    try {
      _profile = SSHProfile.fromJson(widget.profile);
      _profileReady = true;
    } catch (e) {
      _profileReady = false;
      _setBanner('Profil SSH tidak valid: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_profileReady) _connect();
    });
  }

  @override
  void dispose() {
    _sftp?.close();
    _ssh?.close();
    _localPathCtrl.dispose();
    _remotePathCtrl.dispose();
    super.dispose();
  }

  // ------------------- CONNECT -------------------
  static String _defaultLocalHome() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? Directory.current.path;
    }
    return Platform.environment['HOME'] ?? Directory.current.path;
  }

  String _expandHome(String path) {
    if (path.startsWith('~')) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['UserProfile'] ??
          '';
      if (home.isNotEmpty) return path.replaceFirst('~', home);
    }
    return path;
  }

  Future<String> _promptSecret({
    String title = 'Authentication',
    String placeholder = 'Passphrase',
  }) async {
    final ctrl = TextEditingController();
    String? value;
    if (!mounted) return '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(hintText: placeholder),
          onSubmitted: (_) => Navigator.of(ctx).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              value = '';
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              value = ctrl.text;
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return value ?? '';
  }

  Future<List<SSHKeyPair>> _loadKeyPairs() async {
    final keyPath = _profile.privateKeyPath;
    if (keyPath == null || keyPath.trim().isEmpty) return const [];

    final full = _expandHome(keyPath.trim());
    final file = File(full);
    if (!file.existsSync()) {
      throw 'File private key tidak ditemukan: $full';
    }

    final pem = await file.readAsString();

    try {
      return SSHKeyPair.fromPem(pem, null);
    } catch (_) {
      final pass = await _promptSecret(
        title: 'Private key passphrase',
        placeholder: 'Masukkan passphrase',
      );
      if (pass.isEmpty) rethrow;
      return SSHKeyPair.fromPem(pem, pass);
    }
  }

  void _syncPathCtrls() {
    _localPathCtrl.text = _localPath;
    _remotePathCtrl.text = _remotePath;
  }

  Future<void> _connect() async {
    _setBanner(null);
    _setBusy(true, status: 'Connecting to ${_profile.host} ...');
    try {
      final sock = await SSHSocket.connect(_profile.host, _profile.port);

      final keypairs = await _loadKeyPairs().catchError((e) {
        _setBanner('Private key error: $e');
        return <SSHKeyPair>[];
      });

      final ssh = SSHClient(
        sock,
        username: _profile.username,
        identities: keypairs.isEmpty ? null : keypairs,
        onPasswordRequest: () => _profile.password ?? '',
      );

      final sftp = await ssh.sftp();

      String remoteHome = (await _sshRun(
        ssh,
        r'printf %s "$HOME"',
      )).replaceAll('\r', '').replaceAll('\n', '').trim();
      if (remoteHome.isEmpty) remoteHome = '/';

      Future<bool> canList(String path) async {
        try {
          await sftp.listdir(path);
          return true;
        } catch (_) {
          return false;
        }
      }

      if (!await canList(remoteHome)) {
        final alt = '/home/${_profile.username}';
        remoteHome = await canList(alt) ? alt : '/';
      }

      _ssh = ssh;
      _sftp = sftp;
      _remotePath = p.posix.normalize(remoteHome);

      await Future.wait([_loadLocal(), _loadRemote()]);
      _syncPathCtrls();
      _setStatus('Connected: ${_profile.username}@${_profile.host}');
    } on SSHAuthFailError catch (e) {
      _setBanner('SFTP auth gagal: ${e.message}');
    } catch (e) {
      _setBanner('SFTP Error: $e');
    } finally {
      _setBusy(false);
    }
  }

  Future<String> _sshRun(SSHClient ssh, String cmd) async {
    String bytesToString(dynamic v) {
      if (v is String) return v;
      if (v is List<int>) return String.fromCharCodes(v);
      if (v is Uint8List) return String.fromCharCodes(v);
      try {
        final out = (v as dynamic).stdout;
        if (out is List<int>) return String.fromCharCodes(out);
        if (out is Uint8List) return String.fromCharCodes(out);
      } catch (_) {}
      return v?.toString() ?? '';
    }

    try {
      final r = await (ssh as dynamic).run(cmd);
      return bytesToString(r).trim();
    } catch (_) {}
    try {
      final r = await (ssh as dynamic).execute(cmd);
      return bytesToString(r).trim();
    } catch (_) {}
    return '';
  }

  // ------------------- LOAD LISTS -------------------
  Future<void> _loadLocal() async {
    var dir = Directory(_localPath);
    if (!await dir.exists()) {
      _localPath = _defaultLocalHome();
      dir = Directory(_localPath);
    }
    final items = <_FileItem>[];

    if (!_isLocalRoot(_localPath)) {
      items.add(_FileItem.up(p.normalize(p.join(_localPath, '..'))));
    }

    for (final e in dir.listSync()) {
      final st = e.statSync();
      final isDir = st.type == FileSystemEntityType.directory;
      items.add(
        _FileItem(
          name: p.basename(e.path),
          path: e.path,
          isDir: isDir,
          size: isDir ? 0 : st.size,
          modified: st.modified,
        ),
      );
    }

    _localAll = items;
    _localFiles = _applyFilter(items, _localFilter);
    _selectedLocal = null;
    _selLocal.clear();
    _anchorLocal = null;
    _syncPathCtrls();
    if (mounted) setState(() {});
  }

  bool _isLocalRoot(String path) {
    if (Platform.isWindows) {
      return RegExp(r'^[a-zA-Z]:[\\/]{0,1}$').hasMatch(path) ||
          RegExp(r'^[a-zA-Z]:\\$').hasMatch(path);
    }
    return p.normalize(path) == '/';
  }

  Future<void> _loadRemote() async {
    final sftp = _sftp;
    if (sftp == null) return;

    final items = <_FileItem>[];
    final isRoot = _remotePath == '/' || _remotePath.isEmpty;
    if (!isRoot) {
      items.add(
        _FileItem.up(p.posix.normalize(p.posix.join(_remotePath, '..'))),
      );
    }

    final names = await sftp.listdir(_remotePath);
    for (final n in names) {
      final name = n.filename;
      if (name == '.' || name == '..') continue;
      final full = p.posix.normalize(p.posix.join(_remotePath, name));

      bool isDir = false;
      try {
        final ln = (n as dynamic).longname as String?;
        if (ln != null && ln.isNotEmpty && ln[0].toLowerCase() == 'd') {
          isDir = true;
        }
      } catch (_) {}

      if (!isDir) {
        try {
          await sftp.listdir(full);
          isDir = true;
        } catch (_) {
          isDir = false;
        }
      }

      int size = 0;
      try {
        final st = await sftp.stat(full);
        size = st.size ?? 0;
      } catch (_) {}

      items.add(
        _FileItem(
          name: name,
          path: full,
          isDir: isDir,
          size: size,
          modified: null,
        ),
      );
    }

    _remoteAll = items;
    _remoteFiles = _applyFilter(items, _remoteFilter);
    _selectedRemote = null;
    _selRemote.clear();
    _anchorRemote = null;
    _syncPathCtrls();
    if (mounted) setState(() {});
  }

  List<_FileItem> _applyFilter(List<_FileItem> src, String f) {
    f = f.trim().toLowerCase();
    if (f.isEmpty) return List<_FileItem>.from(src);
    return src.where((e) => e.name.toLowerCase().contains(f)).toList();
  }

  // ------------------- PATH BAR -------------------
  Future<void> _setLocalPath(String v) async {
    final d = Directory(v);
    if (await d.exists()) {
      _localPath = p.normalize(v);
      await _loadLocal();
    } else {
      _toast('Folder tidak ada: $v');
      _localPathCtrl.text = _localPath;
    }
  }

  Future<void> _setRemotePath(String v) async {
    final sftp = _sftp;
    if (sftp == null) return;
    final np = p.posix.normalize(v);
    try {
      await sftp.listdir(np);
      _remotePath = np;
      await _loadRemote();
    } catch (_) {
      _toast('Remote path tidak valid: $v');
      _remotePathCtrl.text = _remotePath;
    }
  }

  // ------------------- REMOTE ACTIONS -------------------
  Future<void> _remoteMkdir() async {
    final name = await _prompt('New folder name');
    if (name == null || name.trim().isEmpty) return;
    final path = p.posix.normalize(p.posix.join(_remotePath, name.trim()));
    await _guard(() async {
      await _sftp!.mkdir(path);
      await _loadRemote();
    }, 'Mkdir "$name"');
  }

  Future<void> _remoteRename(_FileItem it) async {
    final newName = await _prompt('Rename', initial: it.name);
    if (newName == null || newName.trim().isEmpty || newName == it.name) return;
    final parent = p.posix.dirname(it.path);
    final to = p.posix.normalize(p.posix.join(parent, newName.trim()));
    await _guard(() async {
      await _sftp!.rename(it.path, to);
      await _loadRemote();
    }, 'Rename "${it.name}"');
  }

  Future<void> _remoteDeletePath(String path) async {
    if (await _remoteIsDir(path)) {
      final entries = await _sftp!.listdir(path);
      for (final e in entries) {
        final name = e.filename;
        if (name == '.' || name == '..') continue;
        final child = p.posix.join(path, name);
        await _remoteDeletePath(child);
      }
      await _sftp!.rmdir(path);
    } else {
      await _sftp!.remove(path);
    }
  }

  Future<void> _remoteDeleteSelected() async {
    final items = _getRemoteSelection();
    if (items.isEmpty) return;
    final ok = await _confirm(
      'Hapus ${items.length} item di Remote?\nTindakan ini tidak bisa dibatalkan.',
    );
    if (!ok) return;
    await _guard(() async {
      for (final it in items) {
        if (it.isUp) continue;
        await _remoteDeletePath(it.path);
      }
      await _loadRemote();
    }, 'Delete');
  }

  // ------------------- LOCAL ACTIONS -------------------
  Future<void> _localMkdir() async {
    final name = await _prompt('New folder name');
    if (name == null || name.trim().isEmpty) return;
    final path = p.normalize(p.join(_localPath, name.trim()));
    await _guard(() async {
      await Directory(path).create(recursive: true);
      await _loadLocal();
    }, 'Mkdir "$name"');
  }

  Future<void> _localRename(_FileItem it) async {
    final newName = await _prompt('Rename', initial: it.name);
    if (newName == null || newName.trim().isEmpty || newName == it.name) return;
    final parent = p.dirname(it.path);
    final to = p.normalize(p.join(parent, newName.trim()));
    await _guard(() async {
      if (it.isDir) {
        await Directory(it.path).rename(to);
      } else {
        await File(it.path).rename(to);
      }
      await _loadLocal();
    }, 'Rename "${it.name}"');
  }

  Future<void> _localDeleteSelected() async {
    final items = _getLocalSelection();
    if (items.isEmpty) return;
    final ok = await _confirm(
      'Hapus ${items.length} item di Local?\nTindakan ini tidak bisa dibatalkan.',
    );
    if (!ok) return;
    await _guard(() async {
      for (final it in items) {
        if (it.isUp) continue;
        if (it.isDir) {
          await Directory(it.path).delete(recursive: true);
        } else {
          await File(it.path).delete();
        }
      }
      await _loadLocal();
    }, 'Delete');
  }

  // ------------------- TRANSFERS -------------------
  Stream<Uint8List> _localFileChunkStream(
    File file, {
    int chunkSize = 64 * 1024,
    void Function(int sent)? onProgress,
  }) async* {
    final raf = file.openSync();
    int sent = 0;
    try {
      while (true) {
        final data = raf.readSync(chunkSize);
        if (data.isEmpty) break;
        sent += data.length;
        onProgress?.call(sent);
        yield Uint8List.fromList(data);
      }
    } finally {
      raf.closeSync();
    }
  }

  Future<void> _uploadFile(
    File localFile,
    String remoteName, {
    String? toDir,
  }) async {
    final sftp = _sftp!;
    final total = await localFile.length();
    final remoteFilePath = p.posix.normalize(
      p.posix.join(toDir ?? _remotePath, remoteName),
    );

    await _guard(() async {
      final f = await sftp.open(
        remoteFilePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );

      final stream = _localFileChunkStream(
        localFile,
        onProgress: (sent) {
          if (total > 0) {
            _progress = sent / total;
            _setStatus(
              'Uploading $remoteName (${_fmtSize(sent)}/${_fmtSize(total)})',
            );
            if (mounted) setState(() {});
          }
        },
      );

      await f.write(stream, offset: 0);
      await f.close();

      _progress = null;
      _setStatus('Upload selesai: $remoteName');
      await _loadRemote();
    }, 'Upload "$remoteName"');
  }

  Future<void> _downloadFile(String remotePath, File localFile) async {
    final sftp = _sftp!;
    await _guard(() async {
      int? size;
      try {
        final st = await sftp.stat(remotePath);
        size = st.size;
      } catch (_) {}

      final f = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      final dyn = f as dynamic;

      final sink = localFile.openWrite();
      int received = 0;
      int offset = 0;

      try {
        const chunkSize = 64 * 1024;
        while (true) {
          final data = await dyn.read(length: chunkSize, offset: offset);
          if (data == null) break;
          if (data is Uint8List && data.isEmpty) break;

          final bytes = data is Uint8List
              ? data
              : Uint8List.fromList((data as List<int>).toList());
          sink.add(bytes);
          offset += bytes.length;

          received += bytes.length;
          if (size != null && size > 0) {
            _progress = received / size;
            _setStatus(
              'Downloading ${p.basename(remotePath)} (${_fmtSize(received)}/${_fmtSize(size)})',
            );
            if (mounted) setState(() {});
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        await f.close();
      }

      _progress = null;
      _setStatus('Download selesai: ${p.basename(remotePath)}');
      await _loadLocal();
    }, 'Download "${p.basename(remotePath)}"');
  }

  Future<bool> _remoteIsDir(String path) async {
    try {
      await _sftp!.listdir(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _uploadDirectory(String localDir, String remoteDir) async {
    await _guard(() async {
      try {
        await _sftp!.mkdir(remoteDir);
      } catch (_) {}
      final entries = Directory(localDir).listSync(followLinks: false);
      for (final e in entries) {
        final name = p.basename(e.path);
        final remoteChild = p.posix.join(remoteDir, name);
        if (FileSystemEntity.isDirectorySync(e.path)) {
          await _uploadDirectory(e.path, remoteChild);
        } else if (FileSystemEntity.isFileSync(e.path)) {
          await _uploadFile(File(e.path), name, toDir: remoteDir);
        }
      }
    }, 'Upload folder "${p.basename(localDir)}"');
  }

  Future<void> _downloadDirectory(
    String remoteDir,
    String localParentDir,
  ) async {
    await _guard(() async {
      final target = Directory(p.join(localParentDir, p.basename(remoteDir)));
      await target.create(recursive: true);

      final names = await _sftp!.listdir(remoteDir);
      for (final n in names) {
        final name = n.filename;
        if (name == '.' || name == '..') continue;
        final remoteChild = p.posix.join(remoteDir, name);

        if (await _remoteIsDir(remoteChild)) {
          await _downloadDirectory(remoteChild, target.path);
        } else {
          final toFile = File(p.join(target.path, name));
          await _downloadFile(remoteChild, toFile);
        }
      }
    }, 'Download folder "${p.basename(remoteDir)}"');
  }

  // -------- COPY berdasarkan MULTI-SELECT --------
  Future<void> _copyLocalSelectionToRemote() async {
    final items = _getLocalSelection();
    if (items.isEmpty) {
      _toast('Tidak ada item Local yang dipilih.');
      return;
    }
    for (final it in items) {
      if (it.isDir) {
        final remoteTarget = p.posix.join(_remotePath, it.name);
        await _uploadDirectory(it.path, remoteTarget);
      } else {
        await _uploadFile(File(it.path), it.name);
      }
    }
  }

  Future<void> _copyRemoteSelectionToLocal() async {
    final items = _getRemoteSelection();
    if (items.isEmpty) {
      _toast('Tidak ada item Remote yang dipilih.');
      return;
    }
    for (final it in items) {
      if (it.isDir || await _remoteIsDir(it.path)) {
        await _downloadDirectory(it.path, _localPath);
      } else {
        final to = File(p.join(_localPath, it.name));
        await _downloadFile(it.path, to);
      }
    }
  }

  // ------------------- NAVIGASI -------------------
  Future<void> _openLocal(_FileItem item) async {
    if (item.isUp || item.isDir) {
      _localPath = item.path;
      await _loadLocal();
    }
  }

  Future<void> _openRemote(_FileItem item) async {
    if (item.isUp) {
      _remotePath = item.path;
      await _loadRemote();
      return;
    }
    bool isDir = item.isDir;
    if (!isDir) {
      try {
        await _sftp!.listdir(item.path);
        isDir = true;
      } catch (_) {
        isDir = false;
      }
    }
    if (isDir) {
      _remotePath = item.path;
      await _loadRemote();
    }
  }

  // ------------------- SELEKSI -------------------
  void _tapSelect({required bool isRemote, required int index}) {
    final files = isRemote ? _remoteFiles : _localFiles;
    final sel = isRemote ? _selRemote : _selLocal;

    if (index < 0 || index >= files.length) return;
    if (files[index].isUp) return;

    int? anchor = isRemote ? _anchorRemote : _anchorLocal;

    if (_shiftDown && anchor != null && anchor >= 0 && anchor < files.length) {
      final start = anchor < index ? anchor : index;
      final end = anchor < index ? index : anchor;
      final range = {
        for (int i = start; i <= end; i++)
          if (!files[i].isUp) i,
      };
      if (_ctrlCmdDown) {
        sel.addAll(range);
      } else {
        sel
          ..clear()
          ..addAll(range);
      }
    } else if (_ctrlCmdDown) {
      if (sel.contains(index)) {
        sel.remove(index);
      } else {
        sel.add(index);
      }
      anchor = index;
    } else {
      sel
        ..clear()
        ..add(index);
      anchor = index;
    }

    if (isRemote) {
      _selectedRemote = index;
      _anchorRemote = anchor;
    } else {
      _selectedLocal = index;
      _anchorLocal = anchor;
    }
    setState(() {});
  }

  // ---- paksa seleksi saat klik-kanan pada item yang belum terseleksi
  void _forceSelect({required bool isRemote, required int index}) {
    if (isRemote) {
      if (index < 0 || index >= _remoteFiles.length) return;
      if (_remoteFiles[index].isUp) return;
      _selRemote = {index};
      _selectedRemote = index;
      _anchorRemote = index;
    } else {
      if (index < 0 || index >= _localFiles.length) return;
      if (_localFiles[index].isUp) return;
      _selLocal = {index};
      _selectedLocal = index;
      _anchorLocal = index;
    }
    if (mounted) setState(() {});
  }

  // ---- helpers untuk selection list ----
  List<_FileItem> _getLocalSelection({int? ensureIndex}) {
    if (ensureIndex != null && !_selLocal.contains(ensureIndex)) {
      _selLocal = {ensureIndex};
      _selectedLocal = ensureIndex;
      _anchorLocal = ensureIndex;
      setState(() {});
    }
    return _selLocal.isNotEmpty
        ? _selLocal
              .where((i) => i >= 0 && i < _localFiles.length)
              .map((i) => _localFiles[i])
              .where((it) => !it.isUp)
              .toList()
        : (_selectedLocal != null ? [_localFiles[_selectedLocal!]] : []);
  }

  List<_FileItem> _getRemoteSelection({int? ensureIndex}) {
    if (ensureIndex != null && !_selRemote.contains(ensureIndex)) {
      _selRemote = {ensureIndex};
      _selectedRemote = ensureIndex;
      _anchorRemote = ensureIndex;
      setState(() {});
    }
    return _selRemote.isNotEmpty
        ? _selRemote
              .where((i) => i >= 0 && i < _remoteFiles.length)
              .map((i) => _remoteFiles[i])
              .where((it) => !it.isUp)
              .toList()
        : (_selectedRemote != null ? [_remoteFiles[_selectedRemote!]] : []);
  }

  // ------------------- UI HELPERS -------------------
  void _setBusy(bool v, {String? status}) {
    _busy = v;
    if (status != null) _status = status;
    if (mounted) setState(() {});
  }

  void _setStatus(String s) {
    _status = s;
    if (mounted) setState(() {});
  }

  void _setBanner(String? s) {
    _bannerError = s;
    if (mounted) setState(() {});
  }

  Future<void> _guard(Future<void> Function() task, String what) async {
    try {
      _setBusy(true, status: '$what ...');
      await task();
    } on SftpStatusError catch (e) {
      String msg = e.toString();
      if (msg.contains('code 2')) {
        msg = '$what gagal: path tidak ada / salah. Periksa hak akses & path.';
      } else if (msg.contains('code 3')) {
        msg = '$what gagal: permission denied.';
      }
      _setBanner(msg);
    } catch (e) {
      _setBanner('$what gagal: $e');
    } finally {
      _setBusy(false);
      _progress = null;
    }
  }

  Future<String?> _prompt(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    bool ok = false;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tidak'),
          ),
          ElevatedButton(
            onPressed: () {
              ok = true;
              Navigator.pop(context);
            },
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    return ok;
  }

  Future<void> _showPropertiesLocal(_FileItem it) async {
    final FileStat? st = it.isDir ? null : File(it.path).statSync();
    final size = it.isDir ? null : st?.size;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Properties (Local)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name : ${it.name}'),
            Text('Path : ${it.path}'),
            Text('Type : ${it.isDir ? "Folder" : "File"}'),
            Text('Size : ${it.isDir ? "-" : _fmtSize(size ?? 0)}'),
            if (it.modified != null)
              Text('Modified : ${_fmtTime(it.modified!)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPropertiesRemote(_FileItem it) async {
    int? sz;
    DateTime? mtime;
    try {
      final st = await _sftp!.stat(it.path);
      sz = st.size;
      final mt = st.modifyTime;
      if (mt != null) {
        mtime = DateTime.fromMillisecondsSinceEpoch(
          mt * 1000,
          isUtc: true,
        ).toLocal();
      }
    } catch (_) {}
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Properties (Remote)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name : ${it.name}'),
            Text('Path : ${it.path}'),
            Text('Type : ${it.isDir ? "Folder" : "File"}'),
            Text('Size : ${it.isDir ? "-" : _fmtSize(sz ?? 0)}'),
            if (mtime != null) Text('Modified : ${_fmtTime(mtime)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmtSize(int bytes) {
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    double s = bytes.toDouble();
    int i = 0;
    while (s >= 1024 && i < u.length - 1) {
      s /= 1024;
      i++;
    }
    final prec = (s < 10 && i > 0) ? 1 : 0;
    return '${s.toStringAsFixed(prec)} ${u[i]}';
  }

  static String _fmtTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  // ------------------- CONTEXT MENUS -------------------
  Future<void> _showLocalContextMenu({required Offset pos, int? index}) async {
    final items = _getLocalSelection(ensureIndex: index);
    final single = items.length == 1 ? items.first : null;
    final isOnItem =
        index != null &&
        index >= 0 &&
        index < _localFiles.length &&
        !_localFiles[index].isUp;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (isOnItem && (single?.isDir ?? true))
          const PopupMenuItem(value: 'open', child: Text('Open')),
        if (isOnItem)
          const PopupMenuItem(value: 'upload', child: Text('Upload to Remote')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'newFolder', child: Text('New Folder')),
        if (isOnItem && items.length == 1)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (isOnItem)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'selectAll', child: Text('Select All')),
        const PopupMenuItem(value: 'clearSel', child: Text('Clear Selection')),
        if (isOnItem) const PopupMenuDivider(),
        if (isOnItem)
          const PopupMenuItem(value: 'props', child: Text('Properties')),
      ],
    );

    switch (result) {
      case 'open':
        if (single != null) await _openLocal(single);
        break;
      case 'upload':
        await _copyLocalSelectionToRemote();
        break;
      case 'newFolder':
        await _localMkdir();
        break;
      case 'rename':
        if (single != null) await _localRename(single);
        break;
      case 'delete':
        await _localDeleteSelected();
        break;
      case 'refresh':
        await _loadLocal();
        break;
      case 'selectAll':
        setState(() {
          _selLocal = {
            for (int i = 0; i < _localFiles.length; i++)
              if (!_localFiles[i].isUp) i,
          };
        });
        break;
      case 'clearSel':
        setState(() => _selLocal.clear());
        break;
      case 'props':
        if (single != null) await _showPropertiesLocal(single);
        break;
      default:
        break;
    }
  }

  Future<void> _showRemoteContextMenu({required Offset pos, int? index}) async {
    final items = _getRemoteSelection(ensureIndex: index);
    final single = items.length == 1 ? items.first : null;
    final isOnItem =
        index != null &&
        index >= 0 &&
        index < _remoteFiles.length &&
        !_remoteFiles[index].isUp;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (isOnItem && (single?.isDir ?? true))
          const PopupMenuItem(value: 'open', child: Text('Open')),
        if (isOnItem)
          const PopupMenuItem(
            value: 'download',
            child: Text('Download to Local'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'newFolder', child: Text('New Folder')),
        if (isOnItem && items.length == 1)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (isOnItem)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'selectAll', child: Text('Select All')),
        const PopupMenuItem(value: 'clearSel', child: Text('Clear Selection')),
        if (isOnItem) const PopupMenuDivider(),
        if (isOnItem)
          const PopupMenuItem(value: 'props', child: Text('Properties')),
      ],
    );

    switch (result) {
      case 'open':
        if (single != null) await _openRemote(single);
        break;
      case 'download':
        await _copyRemoteSelectionToLocal();
        break;
      case 'newFolder':
        await _remoteMkdir();
        break;
      case 'rename':
        if (single != null) await _remoteRename(single);
        break;
      case 'delete':
        await _remoteDeleteSelected();
        break;
      case 'refresh':
        await _loadRemote();
        break;
      case 'selectAll':
        setState(() {
          _selRemote = {
            for (int i = 0; i < _remoteFiles.length; i++)
              if (!_remoteFiles[i].isUp) i,
          };
        });
        break;
      case 'clearSel':
        setState(() => _selRemote.clear());
        break;
      case 'props':
        if (single != null) await _showPropertiesRemote(single);
        break;
      default:
        break;
    }
  }

  // ------------------- BUILD -------------------
  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _sftp == null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            height: 50,
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildToolbarButton(
                  icon: Icons.upload,
                  tooltip: 'Upload file',
                  onPressed: disabled
                      ? null
                      : () async {
                          final x = await fs.openFile();
                          if (x != null) {
                            await _uploadFile(File(x.path), p.basename(x.path));
                          }
                        },
                ),
                _buildToolbarButton(
                  icon: Icons.download,
                  tooltip: 'Download file',
                  onPressed: disabled
                      ? null
                      : () async {
                          final idx = _selectedRemote;
                          if (idx == null) return;
                          final it = _remoteFiles[idx];
                          if (!it.isUp && !it.isDir) {
                            final to = File(p.join(_localPath, it.name));
                            await _downloadFile(it.path, to);
                          }
                        },
                ),
                const SizedBox(width: 16),
                _buildToolbarButton(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onPressed: disabled
                      ? null
                      : () async {
                          await Future.wait([_loadLocal(), _loadRemote()]);
                          _setStatus('Refreshed');
                        },
                ),
                _buildToolbarButton(
                  icon: Icons.arrow_forward,
                  tooltip: 'Copy Local → Remote',
                  onPressed: disabled ? null : _copyLocalSelectionToRemote,
                ),
                _buildToolbarButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Copy Remote → Local',
                  onPressed: disabled ? null : _copyRemoteSelectionToLocal,
                ),
                const Spacer(),
                if (_busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  if (_progress != null) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(value: _progress),
                    ),
                  ],
                ],
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _status!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_bannerError != null)
            Container(
              color: Colors.red[100],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Text(
                _bannerError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          Expanded(
            child: Row(
              children: [
                // Local panel
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 35,
                          color: Colors.grey[50],
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              const Text(
                                'Local files',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'Filter:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 150,
                                height: 25,
                                child: TextField(
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    isDense: true,
                                  ),
                                  onChanged: (v) {
                                    _localFilter = v;
                                    _applyLocalFilter();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        _pathBar(
                          isRemote: false,
                          ctrl: _localPathCtrl,
                          onSubmit: _setLocalPath,
                          onPick: () async {
                            final dir = await fs.getDirectoryPath();
                            if (dir != null) {
                              _localPath = dir;
                              await _loadLocal();
                              _syncPathCtrls();
                            }
                          },
                          onBack: () async {
                            _localPath = p.normalize(p.join(_localPath, '..'));
                            await _loadLocal();
                          },
                          onHome: () async {
                            _localPath = _defaultLocalHome();
                            await _loadLocal();
                          },
                          onRefresh: _loadLocal,
                          actions: [
                            IconButton(
                              tooltip: 'Select All',
                              icon: const Icon(Icons.select_all, size: 16),
                              onPressed: () => setState(() {
                                _selLocal = {
                                  for (int i = 0; i < _localFiles.length; i++)
                                    if (!_localFiles[i].isUp) i,
                                };
                              }),
                            ),
                            IconButton(
                              tooltip: 'Clear Selection',
                              icon: const Icon(Icons.deselect, size: 16),
                              onPressed: () =>
                                  setState(() => _selLocal.clear()),
                            ),
                            IconButton(
                              tooltip: 'New folder',
                              icon: const Icon(
                                Icons.create_new_folder,
                                size: 16,
                              ),
                              onPressed: _localMkdir,
                            ),
                          ],
                        ),
                        Expanded(
                          child: _fileList(
                            files: _localFiles,
                            selectedIndex: _selectedLocal,
                            selectedSet: _selLocal,
                            onSelect: (i) => _selectLocal(i),
                            onDoubleTap: (f) => _doubleClickLocal(f),
                            onItemContextMenu: (i, pos) {
                              _forceSelect(isRemote: false, index: i);
                              _showLocalContextMenu(pos: pos, index: i);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Container(width: 1, color: Colors.grey[400]),

                // Remote panel
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 35,
                          color: Colors.green[50],
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              const Text(
                                'Remote files',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'Filter:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 150,
                                height: 25,
                                child: TextField(
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    isDense: true,
                                  ),
                                  onChanged: (v) {
                                    _remoteFilter = v;
                                    _applyRemoteFilter();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        _pathBar(
                          isRemote: true,
                          ctrl: _remotePathCtrl,
                          onSubmit: _setRemotePath,
                          onBack: () async {
                            _remotePath = p.posix.normalize(
                              p.posix.join(_remotePath, '..'),
                            );
                            await _loadRemote();
                          },
                          onHome: () async {
                            try {
                              final home = (await _sshRun(
                                _ssh!,
                                r'printf %s "$HOME"',
                              )).trim();
                              _remotePath = home.isEmpty
                                  ? '/'
                                  : p.posix.normalize(home);
                            } catch (_) {
                              _remotePath = '/';
                            }
                            await _loadRemote();
                          },
                          onRefresh: _loadRemote,
                          actions: [
                            IconButton(
                              tooltip: 'Select All',
                              icon: const Icon(Icons.select_all, size: 16),
                              onPressed: () => setState(() {
                                _selRemote = {
                                  for (int i = 0; i < _remoteFiles.length; i++)
                                    if (!_remoteFiles[i].isUp) i,
                                };
                              }),
                            ),
                            IconButton(
                              tooltip: 'Clear Selection',
                              icon: const Icon(Icons.deselect, size: 16),
                              onPressed: () =>
                                  setState(() => _selRemote.clear()),
                            ),
                            IconButton(
                              tooltip: 'New folder',
                              icon: const Icon(
                                Icons.create_new_folder,
                                size: 16,
                              ),
                              onPressed: _remoteMkdir,
                            ),
                          ],
                        ),
                        Expanded(
                          child: _fileList(
                            files: _remoteFiles,
                            selectedIndex: _selectedRemote,
                            selectedSet: _selRemote,
                            onSelect: (i) => _selectRemote(i),
                            onDoubleTap: (f) => _doubleClickRemote(f),
                            onItemContextMenu: (i, pos) {
                              _forceSelect(isRemote: true, index: i);
                              _showRemoteContextMenu(pos: pos, index: i);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Status bar
          Container(
            height: 25,
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (_status != null)
                  Text(_status!, style: const TextStyle(fontSize: 11)),
                const Spacer(),
                Text(
                  'Local: ${_localFiles.length - (_localFiles.isNotEmpty && _localFiles.first.isUp ? 1 : 0)} items',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 16),
                Text(
                  'Remote: ${_remoteFiles.length - (_remoteFiles.isNotEmpty && _remoteFiles.first.isUp ? 1 : 0)} items',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _pathBar({
    required bool isRemote,
    required TextEditingController ctrl,
    required FutureOr<void> Function(String) onSubmit,
    FutureOr<void> Function()? onPick,
    required FutureOr<void> Function() onBack,
    required FutureOr<void> Function() onHome,
    required FutureOr<void> Function() onRefresh,
    List<Widget> actions = const [],
  }) {
    return Container(
      height: 35,
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 16),
            onPressed: () => onBack(),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () => onRefresh(),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.home, size: 16),
            onPressed: () => onHome(),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (onPick != null && !isRemote)
            IconButton(
              icon: const Icon(Icons.folder_open, size: 16),
              onPressed: () => onPick(),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 25,
              child: TextField(
                controller: ctrl,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  isDense: true,
                ),
                onSubmitted: (v) => onSubmit(v),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ...actions,
        ],
      ),
    );
  }

  Widget _fileList({
    required List<_FileItem> files,
    required int? selectedIndex,
    required Set<int> selectedSet,
    required void Function(int) onSelect,
    required void Function(_FileItem) onDoubleTap,
    required void Function(int index, Offset globalPos) onItemContextMenu,
  }) {
    return Column(
      children: [
        Container(
          height: 28,
          color: Colors.grey[200],
          child: Row(
            children: const [
              SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  'Name',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Size',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Type',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Date Modified',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              final selected = selectedSet.contains(i);
              final isCurrent = selectedIndex == i;

              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (e.kind == PointerDeviceKind.mouse &&
                      (e.buttons & kSecondaryMouseButton) != 0) {
                    onItemContextMenu(
                      i,
                      e.position,
                    ); // parent akan _forceSelect
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (d) =>
                      onItemContextMenu(i, d.globalPosition),
                  onSecondaryTapUp: (d) =>
                      onItemContextMenu(i, d.globalPosition),
                  child: InkWell(
                    onTap: () => onSelect(i),
                    onDoubleTap: () => onDoubleTap(f),
                    child: Container(
                      height: 22,
                      color: selected
                          ? Colors.blue.withOpacity(0.15)
                          : (isCurrent
                                ? Colors.blue.withOpacity(0.08)
                                : (i % 2 == 0
                                      ? Colors.grey[50]
                                      : Colors.white)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(
                            f.isUp
                                ? Icons.arrow_upward
                                : (f.isDir
                                      ? Icons.folder
                                      : Icons.insert_drive_file),
                            size: 14,
                            color: f.isDir
                                ? Colors.orange[600]
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 3,
                            child: Text(
                              f.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              f.isDir ? '' : _fmtSize(f.size),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              f.isDir ? 'File folder' : 'File',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              f.modified == null ? '' : _fmtTime(f.modified!),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _applyLocalFilter() {
    _localFiles = _applyFilter(_localAll, _localFilter);
    _selLocal.clear();
    _anchorLocal = null;
    setState(() {});
  }

  void _applyRemoteFilter() {
    _remoteFiles = _applyFilter(_remoteAll, _remoteFilter);
    _selRemote.clear();
    _anchorRemote = null;
    setState(() {});
  }

  void _selectLocal(int i) {
    _tapSelect(isRemote: false, index: i);
  }

  void _selectRemote(int i) {
    _tapSelect(isRemote: true, index: i);
  }

  void _doubleClickLocal(_FileItem f) {
    _openLocal(f);
  }

  void _doubleClickRemote(_FileItem f) {
    _openRemote(f);
  }
}

// ---------- models ----------
class _FileItem {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;
  final bool isUp;

  _FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
    this.isUp = false,
  });

  factory _FileItem.up(String toPath) => _FileItem(
    name: '..',
    path: toPath,
    isDir: true,
    size: 0,
    modified: null,
    isUp: true,
  );
}
