import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Client',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.compact,
      ),
      home: SSHClientWindow(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SSHClientWindow extends StatefulWidget {
  const SSHClientWindow({super.key});

  @override
  _SSHClientWindowState createState() => _SSHClientWindowState();
}

class _SSHClientWindowState extends State<SSHClientWindow>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _hostController = TextEditingController(
    text: '192.168.43.138',
  );
  final TextEditingController _portController = TextEditingController(
    text: '22',
  );
  final TextEditingController _usernameController = TextEditingController(
    text: 'h2s',
  );
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _spnController = TextEditingController();
  final TextEditingController _obfuscationController = TextEditingController();

  bool _enableObfuscation = false;
  bool _gssKerberos = false;
  bool _requestDelegation = false;
  bool _gssapiKeyex = true;
  bool _storePassword = false;
  bool _enablePasswordFallback = true;
  String _authMethod = 'password';
  String _elevation = 'Default';

  final List<String> _logMessages = [
    '11:58:35.318  First key exchange completed. Cipher: aes128-ctr, MAC: hmac-sha1 (Group 16, 4096-bit). Session encryption and integrity: aes256-gcm, compression: none.',
    '11:58:40.637  Attempting password authentication.',
    '11:58:40.665  Authentication completed.',
    '11:58:40.682  Enabled FTP-to-SFTP bridge on 127.0.0.1:21.',
    '11:58:40.889  Terminal channel opened.',
    '11:58:40.889  SFTP channel opened.',
    '11:58:40.932  Host key has been saved to the global database. Algorithm: ECDSA/nistp256, size: 256 bits, SHA-256 fingerprint: dUcd1wQmhRdcv7AG6Lm61G5VID9UNlV2MWtQA9a4.',
    '11:58:40.945  Host key has been saved to the global database. Algorithm: Ed25519, size: 256 bits, SHA-256 fingerprint: 6GchpERZRCequyW39U/mdV46JBL2pJGqfaTTUhDaU.',
    '11:58:40.945  Host key synchronization completed with 2 keys saved to global settings. Number of keys received: 3.',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _spnController.dispose();
    _obfuscationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.computer, size: 20),
            SizedBox(width: 8),
            Text('h2s@192.168.43.138:22 - Bitvise SSH Client'),
          ],
        ),
        backgroundColor: Colors.grey[100],
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Row(
        children: [
          // Left Sidebar
          Container(
            width: 140,
            color: Colors.grey[50],
            child: Column(
              children: [
                _buildSidebarItem(icon: Icons.save, title: 'Save profile as'),
                _buildSidebarItem(
                  icon: Icons.storage,
                  title: 'Bitvise SSH Server Control Panel',
                ),
                _buildSidebarItem(
                  icon: Icons.terminal,
                  title: 'New terminal console',
                ),
                _buildSidebarItem(icon: Icons.folder, title: 'New SFTP window'),
                _buildSidebarItem(
                  icon: Icons.desktop_windows,
                  title: 'New Remote Desktop',
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  color: Colors.grey[100],
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey[600],
                    indicatorColor: Colors.blue,
                    tabs: [
                      Tab(text: 'Login'),
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
                ),
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLoginTab(),
                      _buildPlaceholderTab('Options'),
                      _buildPlaceholderTab('Terminal'),
                      _buildPlaceholderTab('RDP'),
                      _buildPlaceholderTab('SFTP'),
                      _buildPlaceholderTab('Services'),
                      _buildPlaceholderTab('C2S'),
                      _buildPlaceholderTab('S2C'),
                      _buildPlaceholderTab('SSH'),
                    ],
                  ),
                ),
                // Log Area
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.white,
                          child: ListView.builder(
                            padding: EdgeInsets.all(8),
                            itemCount: _logMessages.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 1),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _logMessages[index],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[100],
                                foregroundColor: Colors.black,
                              ),
                              child: Text('Log out'),
                            ),
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[200],
                                foregroundColor: Colors.black,
                              ),
                              child: Text('Exit'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({required IconData icon, required String title}) {
    return Container(
      margin: EdgeInsets.all(4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          child: Container(
            padding: EdgeInsets.all(8),
            child: Column(
              children: [
                Icon(icon, size: 32, color: Colors.blue[700]),
                SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Server Section
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(width: 60, child: Text('Host')),
                    SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 60, child: Text('Port')),
                    SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Checkbox(
                      value: _enableObfuscation,
                      onChanged: (value) {
                        setState(() {
                          _enableObfuscation = value!;
                        });
                      },
                    ),
                    Text('Enable obfuscation'),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 60, child: Text('Obfuscation keyword')),
                    SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _obfuscationController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                Text(
                  'Kerberos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(width: 60, child: Text('SPN')),
                    SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _spnController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                CheckboxListTile(
                  title: Text('GSS Kerberos key exchange'),
                  value: _gssKerberos,
                  onChanged: (value) {
                    setState(() {
                      _gssKerberos = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: Text('Request delegation'),
                  value: _requestDelegation,
                  onChanged: (value) {
                    setState(() {
                      _requestDelegation = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: Text('gssapi-keyex authentication'),
                  value: _gssapiKeyex,
                  onChanged: (value) {
                    setState(() {
                      _gssapiKeyex = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(onPressed: () {}, child: Text('Proxy settings')),
                    SizedBox(width: 16),
                    TextButton(
                      onPressed: () {},
                      child: Text('Host key manager'),
                    ),
                    SizedBox(width: 16),
                    TextButton(
                      onPressed: () {},
                      child: Text('Client key manager'),
                    ),
                    Spacer(),
                    TextButton(onPressed: () {}, child: Text('Help')),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 32),
          // Authentication Section
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Authentication',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(width: 80, child: Text('Username')),
                    SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 80, child: Text('Initial method')),
                    SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _authMethod,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'password',
                            child: Text('password'),
                          ),
                          DropdownMenuItem(
                            value: 'publickey',
                            child: Text('publickey'),
                          ),
                          DropdownMenuItem(
                            value: 'keyboard-interactive',
                            child: Text('keyboard-interactive'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _authMethod = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                CheckboxListTile(
                  title: Text('Store encrypted password in profile'),
                  value: _storePassword,
                  onChanged: (value) {
                    setState(() {
                      _storePassword = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 80, child: Text('Password')),
                    SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                CheckboxListTile(
                  title: Text('Enable password over kbdi fallback'),
                  value: _enablePasswordFallback,
                  onChanged: (value) {
                    setState(() {
                      _enablePasswordFallback = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 80, child: Text('Elevation')),
                    SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _elevation,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'Default',
                            child: Text('Default'),
                          ),
                          DropdownMenuItem(value: 'None', child: Text('None')),
                          DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _elevation = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(String tabName) {
    return Center(
      child: Text(
        '$tabName Tab Content',
        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
      ),
    );
  }
}
