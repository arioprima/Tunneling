import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'login_tab.dart';
import 'terminal_tab.dart';
import 'sftp_tab.dart';
import 'rdp_tab.dart';
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
  int _selectedSidebarIndex = 0;

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
    try {
      _addLogMessage("Connecting to $host:$port...");
      final socket = await SSHSocket.connect(host, port);
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      setState(() => _isConnected = true);
      _addLogMessage("Connected to $host as $username");

      final result = await _client!.execute("uname -a");
      _addLogMessage(result.toString().trim());
    } catch (e) {
      _addLogMessage("Error: $e");
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
    Future.delayed(Duration(milliseconds: 300), () {
      exit(0);
    });
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
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(-2, 0),
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
                        LoginTab(
                          onConnect: (host, port, user, pass) {
                            _connectSSH(host, port, user, pass);
                          },
                        ),
                        _buildPlaceholderTab('Options', Icons.settings),
                        TerminalTab(),
                        RDPTab(),
                        SFTPScreen(),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.terminal, size: 20, color: primaryColor),
          ),
          SizedBox(width: 12),
          Text(
            'SSH Client Pro',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
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
        preferredSize: Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey[200]),
      ),
    );
  }

  Widget _buildModernSidebar() {
    final sidebarItems = [
      {
        'icon': Icons.save_outlined,
        'title': 'Save Profile',
        'color': warningColor,
      },
      {
        'icon': Icons.dns_outlined,
        'title': 'Server Control',
        'color': primaryColor,
      },
      {'icon': Icons.terminal, 'title': 'New Terminal', 'color': successColor},
      {
        'icon': Icons.folder_outlined,
        'title': 'SFTP Browser',
        'color': Colors.orange,
      },
      {
        'icon': Icons.desktop_windows_outlined,
        'title': 'Remote Desktop',
        'color': Colors.purple,
      },
    ];

    return Container(
      width: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 20),
          ...sidebarItems.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, dynamic> item = entry.value;
            bool isSelected = _selectedSidebarIndex == index;

            return Container(
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedSidebarIndex = index;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: item['color'].withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item['icon'],
                            size: 18,
                            color: item['color'],
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item['title'],
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
            );
          }),
          Spacer(),
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: Colors.white70, size: 20),
                SizedBox(height: 8),
                Text(
                  'SSH Client Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'v1.0.0',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        tabs: [
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
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: secondaryColor),
                SizedBox(width: 8),
                Text(
                  'Console Output',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.clear, size: 16),
                  onPressed: () {
                    setState(() {
                      _logMessages.clear();
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
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
      padding: EdgeInsets.all(16),
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
              label: "Connect",
              color: successColor,
              onPressed: () {
                debugPrint("mencoba login");
                _tabController.animateTo(0);
              },
            ),
          SizedBox(width: 12),
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
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: color.withOpacity(0.3),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildPlaceholderTab(String tabName, IconData icon) {
    return Container(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: primaryColor),
          ),
          SizedBox(height: 24),
          Text(
            tabName,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This feature is coming soon',
            style: TextStyle(fontSize: 14, color: secondaryColor),
          ),
        ],
      ),
    );
  }
}
