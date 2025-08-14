// lib/screens/sftp_window_placeholder.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:path/path.dart' as p;

import 'ssh_client_window.dart' show SSHProfile;

class SftpWindow extends StatefulWidget {
  final Map<String, dynamic> profile;
  const SftpWindow({super.key, required this.profile});

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

  int? _selectedLocal; // untuk aksi single (rename/delete)
  int? _selectedRemote;

  // === Multi-select states (tanpa checkbox) ===
  Set<int> _selLocal = {};
  Set<int> _selRemote = {};

  // Anchor untuk Shift+klik rentang
  int? _anchorLocal, _anchorRemote;

  bool _busy = false;
  String? _bannerError;
  String? _status;
  double? _progress;

  late final SSHProfile _profile;

  // ==== helper status tombol modifier ====
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
    _profile = SSHProfile.fromJson(widget.profile);
    _connect();
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

  void _syncPathCtrls() {
    _localPathCtrl.text = _localPath;
    _remotePathCtrl.text = _remotePath;
  }

  Future<void> _connect() async {
    _setBanner(null);
    _setBusy(true, status: 'Connecting to ${_profile.host} ...');
    try {
      final sock = await SSHSocket.connect(_profile.host, _profile.port);
      final ssh = SSHClient(
        sock,
        username: _profile.username,
        onPasswordRequest: () => _profile.password ?? '',
      );

      await _sshRun(ssh, 'echo CONNECTED');

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
        if (await canList(alt)) {
          remoteHome = alt;
        } else {
          remoteHome = '/';
        }
      }

      _ssh = ssh;
      _sftp = sftp;
      _remotePath = p.posix.normalize(remoteHome);

      await Future.wait([_loadLocal(), _loadRemote()]);
      _syncPathCtrls();
      _setStatus('Connected: ${_profile.username}@${_profile.host}');
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
    _selLocal.clear(); // reset multi-select agar index tidak nyasar
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

      items.add(
        _FileItem(
          name: name,
          path: full,
          isDir: isDir,
          size: 0,
          modified: null,
        ),
      );
    }

    _remoteAll = items;
    _remoteFiles = _applyFilter(items, _remoteFilter);
    _selectedRemote = null;
    _selRemote.clear(); // reset multi-select
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

  Future<void> _pickLocalDir() async {
    final picked = await fs.getDirectoryPath(initialDirectory: _localPath);
    if (picked != null) await _setLocalPath(picked);
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

  Future<void> _remoteRename() async {
    final idx = _selectedRemote;
    if (idx == null) return;
    final item = _remoteFiles[idx];
    if (item.isUp) return;
    final newName = await _prompt('Rename to', initial: item.name);
    if (newName == null || newName.trim().isEmpty) return;
    final to = p.posix.normalize(p.posix.join(_remotePath, newName.trim()));
    await _guard(() async {
      await _sftp!.rename(item.path, to);
      await _loadRemote();
    }, 'Rename "${item.name}"');
  }

  Future<void> _remoteDelete() async {
    final idx = _selectedRemote;
    if (idx == null) return;
    final item = _remoteFiles[idx];
    if (item.isUp) return;
    final ok = await _confirm('Delete "${item.name}"?');
    if (!ok) return;
    await _guard(() async {
      try {
        await _sftp!.rmdir(item.path);
      } catch (_) {
        await _sftp!.remove(item.path);
      }
      await _loadRemote();
    }, 'Delete "${item.name}"');
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

  Future<void> _localRename() async {
    final idx = _selectedLocal;
    if (idx == null) return;
    final item = _localFiles[idx];
    if (item.isUp) return;
    final newName = await _prompt('Rename to', initial: item.name);
    if (newName == null || newName.trim().isEmpty) return;
    final to = p.normalize(p.join(_localPath, newName.trim()));
    await _guard(() async {
      if (item.isDir) {
        await Directory(item.path).rename(to);
      } else {
        await File(item.path).rename(to);
      }
      await _loadLocal();
    }, 'Rename "${item.name}"');
  }

  Future<void> _localDelete() async {
    final idx = _selectedLocal;
    if (idx == null) return;
    final item = _localFiles[idx];
    if (item.isUp) return;
    final ok = await _confirm('Delete "${item.name}"?');
    if (!ok) return;
    await _guard(() async {
      if (item.isDir) {
        await Directory(item.path).delete(recursive: true);
      } else {
        await File(item.path).delete();
      }
      await _loadLocal();
    }, 'Delete "${item.name}"');
  }

  // ------------------- TRANSFERS (COPY, bukan move) -------------------
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

      // <- KUNCI: tulis dari Stream<Uint8List>, bukan Uint8List langsung
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
        size = st.size?.toInt();
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
              'Downloading ${p.basename(remotePath)} '
              '(${_fmtSize(received)}/${_fmtSize(size)})',
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

  // -------- COPY berdasarkan MULTI-SELECT (tanpa checkbox) --------
  Future<void> _copyLocalSelectionToRemote() async {
    final List<_FileItem> items = _selLocal.isNotEmpty
        ? _selLocal
              .where((i) => i >= 0 && i < _localFiles.length)
              .map((i) => _localFiles[i])
              .where((it) => !it.isUp)
              .toList()
        : (_selectedLocal != null ? [_localFiles[_selectedLocal!]] : []);

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
    final List<_FileItem> items = _selRemote.isNotEmpty
        ? _selRemote
              .where((i) => i >= 0 && i < _remoteFiles.length)
              .map((i) => _remoteFiles[i])
              .where((it) => !it.isUp)
              .toList()
        : (_selectedRemote != null ? [_remoteFiles[_selectedRemote!]] : []);

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

  // ------------------- SELEKSI: klik, Shift+klik, Ctrl/Cmd+klik -------------------
  void _tapSelect({required bool isRemote, required int index}) {
    final files = isRemote ? _remoteFiles : _localFiles;
    final sel = isRemote ? _selRemote : _selLocal;

    if (index < 0 || index >= files.length) return;
    if (files[index].isUp) return; // abaikan '..'

    int? anchor = isRemote ? _anchorRemote : _anchorLocal;

    if (_shiftDown && anchor != null && anchor >= 0 && anchor < files.length) {
      final start = anchor < index ? anchor : index;
      final end = anchor < index ? index : anchor;
      final range = {
        for (int i = start; i <= end; i++)
          if (!files[i].isUp) i,
      };
      if (_ctrlCmdDown) {
        sel.addAll(range); // extend selection
      } else {
        sel
          ..clear()
          ..addAll(range); // replace selection
      }
    } else if (_ctrlCmdDown) {
      // toggle item tunggal
      if (sel.contains(index)) {
        sel.remove(index);
      } else {
        sel.add(index);
      }
      anchor = index;
    } else {
      // klik biasa → single selection
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

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return ok ?? false;
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

  // ------------------- BUILD -------------------
  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _sftp == null;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Column(
          children: [
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
            Container(
              height: 44,
              color: Colors.grey[50],
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Upload (pilih file)',
                    icon: const Icon(Icons.upload),
                    onPressed: disabled
                        ? null
                        : () async {
                            final x = await fs.openFile();
                            if (x != null) {
                              await _uploadFile(
                                File(x.path),
                                p.basename(x.path),
                              );
                            }
                          },
                  ),
                  IconButton(
                    tooltip: 'Download (file terpilih di remote)',
                    icon: const Icon(Icons.download),
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
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: disabled
                        ? null
                        : () async {
                            await Future.wait([_loadLocal(), _loadRemote()]);
                            _setStatus('Refreshed');
                          },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copy selected Local → Remote',
                    icon: const Icon(Icons.arrow_circle_right_outlined),
                    onPressed: disabled ? null : _copyLocalSelectionToRemote,
                  ),
                  IconButton(
                    tooltip: 'Copy selected Remote → Local',
                    icon: const Icon(Icons.arrow_circle_left_outlined),
                    onPressed: disabled ? null : _copyRemoteSelectionToLocal,
                  ),
                  if (_busy) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    if (_progress != null) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(value: _progress),
                      ),
                    ],
                  ],
                  const Spacer(),
                  if (_status != null)
                    Text(
                      _status!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  // Local
                  Expanded(
                    child: _panel(
                      isRemote: false,
                      title: 'Local files',
                      files: _localFiles,
                      selectedIndex: _selectedLocal,
                      onSelect: (i) => _tapSelect(isRemote: false, index: i),
                      selectedSet: _selLocal,
                      onDoubleTap: (it) => _openLocal(it),
                      pathBar: _pathBar(
                        isRemote: false,
                        ctrl: _localPathCtrl,
                        onSubmit: _setLocalPath,
                        onPick: _pickLocalDir,
                        onBack: () async {
                          if (!_isLocalRoot(_localPath)) {
                            _localPath = p.normalize(p.join(_localPath, '..'));
                            await _loadLocal();
                          }
                        },
                        onHome: () async {
                          _localPath = _defaultLocalHome();
                          await _loadLocal();
                        },
                        onRefresh: _loadLocal,
                        actions: [
                          IconButton(
                            tooltip: 'Select All',
                            icon: const Icon(Icons.select_all),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _selLocal = {
                                      for (
                                        int i = 0;
                                        i < _localFiles.length;
                                        i++
                                      )
                                        if (!_localFiles[i].isUp) i,
                                    };
                                  }),
                          ),
                          IconButton(
                            tooltip: 'Clear Selection',
                            icon: const Icon(Icons.deselect),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _selLocal.clear()),
                          ),
                          IconButton(
                            tooltip: 'Copy selected to Remote',
                            icon: const Icon(Icons.arrow_circle_right_outlined),
                            onPressed: _busy
                                ? null
                                : _copyLocalSelectionToRemote,
                          ),
                          IconButton(
                            tooltip: 'New folder',
                            icon: const Icon(Icons.create_new_folder),
                            onPressed: _busy ? null : _localMkdir,
                          ),
                          IconButton(
                            tooltip: 'Rename (single)',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            onPressed: _busy ? null : _localRename,
                          ),
                          IconButton(
                            tooltip: 'Delete (single)',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : _localDelete,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.grey[300]),
                  // Remote
                  Expanded(
                    child: _panel(
                      isRemote: true,
                      title: 'Remote files',
                      files: _remoteFiles,
                      selectedIndex: _selectedRemote,
                      onSelect: (i) => _tapSelect(isRemote: true, index: i),
                      selectedSet: _selRemote,
                      onDoubleTap: (it) => _openRemote(it),
                      pathBar: _pathBar(
                        isRemote: true,
                        ctrl: _remotePathCtrl,
                        onSubmit: _setRemotePath,
                        onBack: () async {
                          if (!(_remotePath == '/' || _remotePath.isEmpty)) {
                            _remotePath = p.posix.normalize(
                              p.posix.join(_remotePath, '..'),
                            );
                            await _loadRemote();
                          }
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
                            icon: const Icon(Icons.select_all),
                            onPressed: disabled
                                ? null
                                : () => setState(() {
                                    _selRemote = {
                                      for (
                                        int i = 0;
                                        i < _remoteFiles.length;
                                        i++
                                      )
                                        if (!_remoteFiles[i].isUp) i,
                                    };
                                  }),
                          ),
                          IconButton(
                            tooltip: 'Clear Selection',
                            icon: const Icon(Icons.deselect),
                            onPressed: disabled
                                ? null
                                : () => setState(() => _selRemote.clear()),
                          ),
                          IconButton(
                            tooltip: 'Copy selected to Local',
                            icon: const Icon(Icons.arrow_circle_left_outlined),
                            onPressed: disabled
                                ? null
                                : _copyRemoteSelectionToLocal,
                          ),
                          IconButton(
                            tooltip: 'New folder',
                            icon: const Icon(Icons.create_new_folder),
                            onPressed: disabled ? null : _remoteMkdir,
                          ),
                          IconButton(
                            tooltip: 'Rename (single)',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            onPressed: disabled ? null : _remoteRename,
                          ),
                          IconButton(
                            tooltip: 'Delete (single)',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: disabled ? null : _remoteDelete,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 16),
          onPressed: () => onBack(),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 16),
          onPressed: () => onRefresh(),
        ),
        IconButton(
          icon: const Icon(Icons.home, size: 16),
          onPressed: () => onHome(),
        ),
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: ctrl,
              onSubmitted: onSubmit,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (onPick != null)
          IconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            onPressed: () => onPick(),
          ),
        ...actions,
      ],
    );
  }

  Widget _panel({
    required bool isRemote,
    required String title,
    required List<_FileItem> files,
    required int? selectedIndex,
    required void Function(int) onSelect,
    required Set<int> selectedSet, // state multi-select
    required void Function(_FileItem) onDoubleTap,
    required Widget pathBar,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + filter
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isRemote ? Colors.green[700] : Colors.blue[700],
                ),
              ),
              const Spacer(),
              const Text('Filter:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                height: 26,
                child: TextField(
                  onChanged: (v) {
                    if (isRemote) {
                      _remoteFilter = v;
                      _remoteFiles = _applyFilter(_remoteAll, _remoteFilter);
                      _selRemote.clear();
                      _anchorRemote = null;
                    } else {
                      _localFilter = v;
                      _localFiles = _applyFilter(_localAll, _localFilter);
                      _selLocal.clear();
                      _anchorLocal = null;
                    }
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // Path bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pathBar,
        ),

        // Columns header (tanpa checkbox)
        Container(
          height: 25,
          color: Colors.grey[100],
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
                  'Modified',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(width: 8),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              final selected = selectedSet.contains(i);

              return InkWell(
                onTap: () => onSelect(i),
                onDoubleTap: () => onDoubleTap(f),
                child: Container(
                  height: 24,
                  color: selected
                      ? Colors.blue.withOpacity(0.12)
                      : (selectedIndex == i
                            ? Colors.blue.withOpacity(0.06)
                            : null),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(
                        f.isUp
                            ? Icons.arrow_upward
                            : (f.isDir
                                  ? Icons.folder
                                  : Icons.insert_drive_file),
                        size: 16,
                        color: f.isDir ? Colors.amber[700] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
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
                          f.isDir ? '--' : _fmtSize(f.size),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          f.isDir ? 'Folder' : 'File',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          f.modified == null ? '--' : _fmtTime(f.modified!),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Hint
        Container(
          height: 28,
          color: Colors.grey[50],
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            isRemote
                ? 'Shift+klik untuk pilih rentang, Ctrl/Cmd+klik untuk toggle. Klik ▶︎/◀︎ untuk copy. Double-click folder untuk masuk. (Remote → Local pakai ◀︎)'
                : 'Shift+klik untuk pilih rentang, Ctrl/Cmd+klik untuk toggle. Klik ▶︎/◀︎ untuk copy. Double-click folder untuk masuk. (Local → Remote pakai ▶︎)',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
      ],
    );
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
