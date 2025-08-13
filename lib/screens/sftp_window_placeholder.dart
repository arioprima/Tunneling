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

  Future<void> _remoteRename(_FileItem item) async {
    final newName = await _prompt('Rename to', initial: item.name);
    if (newName == null || newName.trim().isEmpty || newName == item.name) {
      return;
    }
    final newPath = p.posix.normalize(
      p.posix.join(_remotePath, newName.trim()),
    );
    await _guard(() async {
      await _sftp!.rename(item.path, newPath);
      await _loadRemote();
    }, 'Rename "${item.name}"');
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

  Future<void> _localRename(_FileItem item) async {
    final newName = await _prompt('Rename to', initial: item.name);
    if (newName == null || newName.trim().isEmpty || newName == item.name) {
      return;
    }
    final newPath = p.normalize(p.join(_localPath, newName.trim()));
    await _guard(() async {
      final entity = item.isDir ? Directory(item.path) : File(item.path);
      await entity.rename(newPath);
      await _loadLocal();
    }, 'Rename "${item.name}"');
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
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white, // default background putih
      ),
      home: Scaffold(
        body: Column(
          children: [
            Container(
              color: Colors.white,
              height: 30,
              // color: Colors.grey[200],
              child: Row(
                children: [
                  _buildMenuButton('Window'),
                  _buildMenuButton('Local'),
                  _buildMenuButton('Remote'),
                  _buildMenuButton('Upload queue'),
                  _buildMenuButton('Download queue'),
                  _buildMenuButton('Log'),
                ],
              ),
            ),

            Container(
              height: 50,
              color: Colors.grey[100],
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _buildToolbarButton(
                    icon: Icons.folder_open,
                    tooltip: 'Browse',
                    onPressed: disabled ? null : () {},
                  ),
                  _buildToolbarButton(
                    icon: Icons.upload,
                    tooltip: 'Upload queue',
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
                  _buildToolbarButton(
                    icon: Icons.download,
                    tooltip: 'Download queue',
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
                  _buildToolbarButton(
                    icon: Icons.list_alt,
                    tooltip: 'Log',
                    onPressed: disabled ? null : () {},
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
                  // Local files panel
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
                          // Path navigation bar
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
                              _localPath = p.normalize(
                                p.join(_localPath, '..'),
                              );
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
                                onPressed: disabled
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
                                icon: const Icon(Icons.deselect, size: 16),
                                onPressed: disabled
                                    ? null
                                    : () => setState(() => _selLocal.clear()),
                              ),
                              IconButton(
                                tooltip: 'New folder',
                                icon: const Icon(
                                  Icons.create_new_folder,
                                  size: 16,
                                ),
                                onPressed: disabled ? null : _localMkdir,
                              ),
                            ],
                          ),
                          // File list
                          Expanded(
                            child: _fileList(
                              files: _localFiles,
                              selectedIndex: _selectedLocal,
                              selectedSet: _selLocal,
                              onSelect: (i) => _selectLocal(i),
                              onDoubleTap: (f) => _doubleClickLocal(f),
                              onNewFolder: _localMkdir,
                              onRename: (f) => _localRename(f),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Vertical divider
                  Container(width: 1, color: Colors.grey[400]),

                  // Remote files panel
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
                          // Path navigation bar
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
                                icon: const Icon(Icons.deselect, size: 16),
                                onPressed: disabled
                                    ? null
                                    : () => setState(() => _selRemote.clear()),
                              ),
                              IconButton(
                                tooltip: 'New folder',
                                icon: const Icon(
                                  Icons.create_new_folder,
                                  size: 16,
                                ),
                                onPressed: disabled ? null : _remoteMkdir,
                              ),
                            ],
                          ),
                          // File list
                          Expanded(
                            child: _fileList(
                              files: _remoteFiles,
                              selectedIndex: _selectedRemote,
                              selectedSet: _selRemote,
                              onSelect: (i) => _selectRemote(i),
                              onDoubleTap: (f) => _doubleClickRemote(f),
                              onNewFolder: _remoteMkdir,
                              onRename: (f) => _remoteRename(f),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
      ),
    );
  }

  Widget _buildMenuButton(String text) {
    return InkWell(
      onTap: () {
        // Menu functionality can be implemented here
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: const TextStyle(fontSize: 12)),
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
          if (onPick != null)
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

  Future<void> _showFileContextMenu(
    Offset position,
    _FileItem item, {
    required Future<void> Function() onNewFolder,
    required Future<void> Function(_FileItem) onRename,
  }) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'mkdir', child: Text('New Folder')),
        if (!item.isUp)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
      ],
    );
    if (result == 'mkdir') {
      await onNewFolder();
    } else if (result == 'rename') {
      await onRename(item);
    }
  }

  Widget _fileList({
    required List<_FileItem> files,
    required int? selectedIndex,
    required Set<int> selectedSet,
    required void Function(int) onSelect,
    required void Function(_FileItem) onDoubleTap,
    required Future<void> Function() onNewFolder,
    required Future<void> Function(_FileItem) onRename,
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

        // File list
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              final selected = selectedSet.contains(i);
              final isCurrent = selectedIndex == i;
              return GestureDetector(
                onSecondaryTapDown: (d) {
                  onSelect(i);
                  _showFileContextMenu(
                    d.globalPosition,
                    f,
                    onNewFolder: onNewFolder,
                    onRename: onRename,
                  );
                },
                child: InkWell(
                  onTap: () => onSelect(i),
                  onDoubleTap: () => onDoubleTap(f),
                  child: Container(
                    height: 22,
                    color: selected
                        ? Colors.blue.withOpacity(0.15)
                        : (isCurrent
                            ? Colors.blue.withOpacity(0.08)
                            : (i % 2 == 0 ? Colors.grey[50] : Colors.white)),
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
                          color: f.isDir ? Colors.orange[600] : Colors.grey[600],
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
