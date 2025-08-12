import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';

import 'login_tab.dart';
import 'terminal_tab.dart';
import 'sftp_tab.dart';
import 'rdp_tab.dart';
import 'dart:convert';
import 'package:file_selector/file_selector.dart' as fs;
import '../widgets/log_viewer.dart';

class SSHClientWindow extends StatefulWidget {
  const SSHClientWindow({super.key});

  @override
  _SSHClientWindowState createState() => _SSHClientWindowState();
}

class _SSHClientWindowState extends State<SSHClientWindow>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _logMessages = [];
  SSHClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _selectedSidebarIndex = 0;

  // key untuk akses state LoginTab
  final GlobalKey<LoginTabState> _loginKey = GlobalKey<LoginTabState>();

  // Modern color scheme
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color secondaryColor = Color(0xFF64748B);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color successColor = Color(0xFF10B981);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
  }

  @override
  void dispose() {
    _disconnectSSH();
    _tabController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    setState(() {
      final time = TimeOfDay.now().format(context);
      _logMessages.add("$time  $message");
    });
  }

  Future<void> _connectSSH(
    String host,
    int port,
    String username,
    String password,
  ) async {
    if (_isConnecting) return;
    _isConnecting = true;
    setState(() {});
    try {
      _addLogMessage("Connecting to $host:$port as $username ...");

      final socket = await SSHSocket.connect(host, port);
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        // TODO: tambahkan verifikasi host key untuk keamanan production.
      );

      setState(() => _isConnected = true);
      _addLogMessage("✅ SSH connected to $host as $username");

      final result = await _client!.execute("uname -a");
      _addLogMessage("Remote: ${result.toString().trim()}");

      // _tabController.animateTo(2); // pindah ke Terminal
    } catch (e) {
      _addLogMessage("❌ SSH Error: $e");
      setState(() {
        _isConnected = false;
        _client = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal connect: $e')));
      }
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  void _disconnectSSH() {
    if (_client != null) {
      _client!.close();
      _addLogMessage("Connection closed.");
      setState(() {
        _isConnected = false;
        _client = null;
      });
    }
  }

  void _exitApp() {
    _addLogMessage("Exiting application...");
    Future.delayed(const Duration(milliseconds: 300), () {
      exit(0);
    });
  }

  void _connectFromLoginTab() {
    final creds = _loginKey.currentState?.readCredentials();
    if (creds == null) return; // validasi sudah ditangani di LoginTab
    // UI fokus dulu: hanya password flow.
    if ((creds['method'] ?? 'password') != 'password') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo UI: sementara dukung method password dulu.'),
        ),
      );
    }
    _connectSSH(
      creds['host'] as String,
      creds['port'] as int,
      creds['username'] as String,
      (creds['password'] ?? '') as String,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: Row(
        children: [
          _buildModernSidebar(),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(-2, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildModernTabBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // 0: Login (tanpa tombol)
                        LoginTab(key: _loginKey, isConnecting: _isConnecting),
                        // 1: Options
                        _buildPlaceholderTab('Options', Icons.settings),
                        // 2: Terminal
                        const TerminalTab(),
                        // 3: RDP
                        const RDPTab(),
                        // 4: SFTP
                        _buildSftpTab(),
                        // 5..8 placeholders
                        _buildPlaceholderTab(
                          'Services',
                          Icons.miscellaneous_services,
                        ),
                        _buildPlaceholderTab('C2S', Icons.arrow_forward),
                        _buildPlaceholderTab('S2C', Icons.arrow_back),
                        _buildPlaceholderTab('SSH', Icons.security),
                      ],
                    ),
                  ),
                  _buildLogSection(),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSftpTab() {
    if (!_isConnected || _client == null) {
      return _buildNeedConnection('SFTP');
    }
    return SFTPScreen(client: _client!);
  }

  Widget _buildNeedConnection(String feature) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, size: 40, color: secondaryColor),
          const SizedBox(height: 12),
          Text(
            'Connect dulu untuk memakai $feature',
            style: const TextStyle(fontSize: 14, color: secondaryColor),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _tabController.animateTo(0),
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Pergi ke Login'),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.terminal, size: 20, color: primaryColor),
          ),
          const SizedBox(width: 12),
          const Text(
            'SSH Client Pro',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isConnected ? successColor : secondaryColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected
                      ? (_isConnecting ? 'Connected (busy)' : 'Connected')
                      : (_isConnecting ? 'Connecting...' : 'Disconnected'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: surfaceColor,
      foregroundColor: Colors.black87,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey[200]),
      ),
    );
  }

  /// ————————————————————————————————————————————————————————————————
  /// Sidebar: Bitvise-like dynamic menu
  /// ————————————————————————————————————————————————————————————————

  Widget _buildModernSidebar() {
    final items = _isConnected
        ? _sidebarItemsForConnected()
        : _sidebarItemsForDisconnected();

    // Pastikan selected index valid ketika state berubah (connect/disconnect)
    if (_selectedSidebarIndex >= items.length) {
      _selectedSidebarIndex = 0;
    }

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _isConnected ? 'Quick Actions' : 'Profile',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = _selectedSidebarIndex == index;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: Tooltip(
                  message: item.title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedSidebarIndex = index);
                      item.onTap?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(color: Colors.white.withOpacity(0.2))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: item.color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item.icon, size: 18, color: item.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Connected session' : 'No active session',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'SSH Client Pro\nv1.0.0',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_SidebarItem> _sidebarItemsForDisconnected() => [
    _SidebarItem(
      icon: Icons.folder_open,
      title: 'Load Profile',
      color: Colors.teal,
      onTap: _uiLoadProfile,
    ),
    _SidebarItem(
      icon: Icons.save_outlined,
      title: 'Save Profile As…',
      color: warningColor,
      onTap: _uiSaveProfileAs,
    ),
    _SidebarItem(
      icon: Icons.note_add_outlined,
      title: 'New Profile',
      color: primaryColor,
      onTap: _uiNewProfile,
    ),
    _SidebarItem(
      icon: Icons.restore,
      title: 'Reset Profile',
      color: Colors.redAccent,
      onTap: _uiResetProfile,
    ),
  ];

  List<_SidebarItem> _sidebarItemsForConnected() => [
    _SidebarItem(
      icon: Icons.save_outlined,
      title: 'Save Profile As…',
      color: warningColor,
      onTap: _uiSaveProfileAs,
    ),
    _SidebarItem(
      icon: Icons.terminal,
      title: 'New Terminal Console',
      color: successColor,
      onTap: () {
        _tabController.animateTo(2);
        _addLogMessage('New Terminal opened');
      },
    ),
    _SidebarItem(
      icon: Icons.folder_outlined,
      title: 'New SFTP Window',
      color: Colors.orange,
      onTap: () {
        _tabController.animateTo(4);
        _addLogMessage('New SFTP window opened');
      },
    ),
    _SidebarItem(
      icon: Icons.desktop_windows_outlined,
      title: 'New Remote Desktop',
      color: Colors.purple,
      onTap: () {
        _tabController.animateTo(3);
        _addLogMessage('New RDP opened');
      },
    ),
  ];

  // ——— Sidebar actions (UI-only for now) ———
  void _uiLoadProfile() async {
    try {
      // Buka file dialog
      final fs.XFile? file = await fs.openFile(
        acceptedTypeGroups: const [
          fs.XTypeGroup(
            label: 'SSH Client Pro Profile',
            extensions: ['sshp', 'json', 'tlp', 'bscp'], // dukung ekstensi ini
          ),
        ],
      );

      if (file == null) {
        _addLogMessage('Load Profile: dibatalkan');
        return;
      }

      final content = await file.readAsString();

      // Coba parse JSON
      late final Map<String, dynamic> map;
      try {
        map = json.decode(content) as Map<String, dynamic>;
      } on FormatException {
        _addLogMessage('❌ Format file tidak dikenal (bukan JSON).');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File profile bukan JSON yang didukung.'),
            ),
          );
        }
        return;
      }

      // Bangun objek profile
      final profile = SSHProfile.fromJson(map);

      // Oper ke LoginTab supaya field terisi
      _loginKey.currentState?.applyProfile({
        'profileName': profile.name,
        'host': profile.host,
        'port': profile.port,
        'username': profile.username,
        'method': profile.method,
        'password': profile.password,
        'privateKeyPath': profile.privateKeyPath,
      });

      _addLogMessage('✅ Profile dimuat: ${profile.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile dimuat: ${profile.name}')),
        );
        // Opsional: tampilkan form Login agar user bisa cek/ubah
        _tabController.animateTo(0);
      }
    } catch (e) {
      _addLogMessage('❌ Gagal load profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal load profile: $e')));
      }
    }
  }

  void _uiSaveProfileAs() async {
    final data = _loginKey.currentState?.readCredentials();
    if (data == null) {
      _addLogMessage('Save Profile As: form belum lengkap');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lengkapi form Login dahulu untuk menyimpan profile.',
            ),
          ),
        );
      }
      _tabController.animateTo(0);
      return;
    }

    final profile = SSHProfile(
      name: (data['profileName'] as String?)?.trim().isNotEmpty == true
          ? data['profileName'] as String
          : '${data['username']}@${data['host']}',
      host: data['host'] as String,
      port: data['port'] as int,
      username: data['username'] as String,
      method: (data['method'] as String?) ?? 'password',
      password: (data['password'] as String?)?.isNotEmpty == true
          ? data['password'] as String
          : null,
      privateKeyPath: data['privateKeyPath'] as String?,
      autoSwitchAfterConnect: false,
    );

    try {
      final encoded = const JsonEncoder.withIndent(
        '  ',
      ).convert(profile.toJson());
      final fileName = '${profile.name}.sshp';

      // 🔧 API baru:
      final fs.FileSaveLocation? loc = await fs.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          fs.XTypeGroup(
            label: 'SSH Client Pro Profile',
            extensions: ['sshp', 'json', 'tlp', 'bscp'],
          ),
        ],
      );
      if (loc == null) {
        _addLogMessage('Save Profile As: dibatalkan');
        return;
      }

      final xfile = fs.XFile.fromData(
        utf8.encode(encoded),
        name: fileName,
        mimeType: 'application/json',
      );
      await xfile.saveTo(loc.path);

      _addLogMessage('✅ Profile tersimpan: ${loc.path}');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile saved:\n${loc.path}')));
      }
    } catch (e) {
      _addLogMessage('❌ Gagal menyimpan profile: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan profile: $e')));
      }
    }
  }

  void _uiNewProfile() {
    // Reset form login ke default (UI)
    _tabController.animateTo(0);
    _addLogMessage('New Profile: reset form ke default');
    // Tidak memanggil setState di LoginTab; biasanya kita expose method di LoginTabState untuk clear.
    // Untuk demo, cukup informasikan ke pengguna.
  }

  void _uiResetProfile() {
    _tabController.animateTo(0);
    _addLogMessage('Reset Profile: kembali ke nilai awal');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset Profile (UI only) – coming soon')),
    );
  }

  /// ————————————————————————————————————————————————————————————————
  /// BOTTOM: Logs & Actions
  /// ————————————————————————————————————————————————————————————————

  Widget _buildModernTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: primaryColor,
        unselectedLabelColor: secondaryColor,
        indicatorColor: primaryColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.login, size: 16),
                SizedBox(width: 6),
                Text('Login'),
              ],
            ),
          ),
          Tab(text: 'Options'),
          Tab(text: 'Terminal'),
          Tab(text: 'RDP'),
          Tab(text: 'SFTP'),
          Tab(text: 'Services'),
          Tab(text: 'C2S'),
          Tab(text: 'S2C'),
          Tab(text: 'SSH'),
        ],
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      height: 120,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: secondaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Console Output',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    setState(() {
                      _logMessages.clear();
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(child: LogViewer(logMessages: _logMessages)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isConnected)
            _buildActionButton(
              icon: Icons.logout,
              label: "Disconnect",
              color: errorColor,
              onPressed: _disconnectSSH,
            )
          else
            _buildActionButton(
              icon: Icons.login,
              label: _isConnecting ? "Connecting..." : "Connect",
              color: successColor,
              onPressed: _isConnecting
                  ? null
                  : () {
                      if (_tabController.index != 0) {
                        _tabController.animateTo(0);
                      }
                      _connectFromLoginTab();
                    },
            ),
          const SizedBox(width: 12),
          _buildActionButton(
            icon: Icons.close,
            label: "Exit",
            color: secondaryColor,
            onPressed: _exitApp,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: color.withOpacity(0.3),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildPlaceholderTab(String tabName, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: primaryColor),
          ),
          const SizedBox(height: 24),
          Text(
            tabName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This feature is coming soon',
            style: TextStyle(fontSize: 14, color: secondaryColor),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;
  const _SidebarItem({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });
}

class SSHProfile {
  final String name;
  final String host;
  final int port;
  final String username;
  final String method; // 'password' | 'key' (future)
  final String? password; // ⚠️ plain text kalau diisi
  final String? privateKeyPath;
  final bool autoSwitchAfterConnect;

  SSHProfile({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.method,
    this.password,
    this.privateKeyPath,
    this.autoSwitchAfterConnect = false,
  });

  Map<String, dynamic> toJson() => {
    'version': 1,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'method': method,
    'password': password, // boleh null
    'privateKeyPath': privateKeyPath,
    'ui': {'autoSwitchAfterConnect': autoSwitchAfterConnect},
  };

  factory SSHProfile.fromJson(Map<String, dynamic> json) => SSHProfile(
    name: (json['name'] as String?) ?? 'Unnamed',
    host: json['host'] as String,
    port: (json['port'] as num).toInt(),
    username: json['username'] as String,
    method: (json['method'] as String?) ?? 'password',
    password: json['password'] as String?,
    privateKeyPath: json['privateKeyPath'] as String?,
    autoSwitchAfterConnect:
        (json['ui']?['autoSwitchAfterConnect'] as bool?) ?? false,
  );
}
