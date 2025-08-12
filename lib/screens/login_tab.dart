import 'package:flutter/material.dart';

class LoginTab extends StatefulWidget {
  final bool isConnecting;

  const LoginTab({super.key, this.isConnecting = false});

  @override
  LoginTabState createState() => LoginTabState();
}

class LoginTabState extends State<LoginTab> {
  // Controllers
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '22',
  );
  final TextEditingController _usernameController = TextEditingController();

  // Password method
  final TextEditingController _passwordController = TextEditingController();

  // Public key method
  final TextEditingController _keyPathController = TextEditingController();
  final TextEditingController _keyPassphraseController =
      TextEditingController();

  // Kerberos / obfuscation (kept as-is)
  final TextEditingController _spnController = TextEditingController();
  final TextEditingController _obfuscationController = TextEditingController();

  bool _enableObfuscation = false;
  bool _gssKerberos = false;
  bool _requestDelegation = false;
  bool _gssapiKeyex = true;
  bool _storePassword = false; // only relevant when method == password
  bool _enablePasswordFallback = true; // relevant when method == publickey

  /// Bitvise-like: start with "none" until user chooses a method
  String _authMethod =
      'none'; // 'none' | 'password' | 'publickey' | 'keyboard-interactive'
  String _elevation = 'Default';

  static const Map<String, String> _authLabels = {
    'none': 'None',
    'password': 'Password',
    'publickey': 'Public key',
    'keyboard-interactive': 'Keyboard-interactive',
  };

  @override
  void initState() {
    super.initState();
  }

  void applyProfile(Map<String, dynamic> p) {
    // helper untuk baca nested key "kerberos"
    Map<String, dynamic> kerb(Map<String, dynamic> src) =>
        (src['kerberos'] is Map<String, dynamic>)
        ? (src['kerberos'] as Map<String, dynamic>)
        : const {};

    setState(() {
      // server
      _hostController.text = (p['host'] ?? '') as String;
      final portVal = p['port'];
      _portController.text = (portVal is int)
          ? portVal.toString()
          : (portVal is String ? portVal : '22').toString();
      _usernameController.text = (p['username'] ?? '') as String;

      // obfuscation
      final obf = (p['obfuscation']);
      if (obf == null || (obf is String && obf.isEmpty)) {
        _enableObfuscation = false;
        _obfuscationController.clear();
      } else {
        _enableObfuscation = true;
        _obfuscationController.text = obf as String;
      }

      // kerberos
      final k = kerb(p);
      _spnController.text = (k['spn'] ?? '') as String;
      _gssKerberos = (k['gssKerberos'] as bool?) ?? false;
      _requestDelegation = (k['requestDelegation'] as bool?) ?? false;
      _gssapiKeyex = (k['gssapiKeyex'] as bool?) ?? true;

      // elevation (opsional)
      _elevation = (p['elevation'] as String?) ?? 'Default';

      // auth method
      final method = (p['method'] as String?) ?? 'none';
      switch (method) {
        case 'password':
          _authMethod = 'password';
          _passwordController.text = (p['password'] ?? '') as String;
          _storePassword = (p['storePassword'] as bool?) ?? false;
          // bersihkan field PK agar UI rapi
          _keyPathController.clear();
          _keyPassphraseController.clear();
          _enablePasswordFallback = true;
          break;

        case 'publickey':
          _authMethod = 'publickey';
          _keyPathController.text = (p['privateKeyPath'] ?? '') as String;
          _keyPassphraseController.text = (p['passphrase'] ?? '') as String;
          _enablePasswordFallback =
              (p['enablePasswordFallback'] as bool?) ?? true;
          // fallback password (opsional)
          _passwordController.text = (p['fallbackPassword'] ?? '') as String;
          // bersihkan field password utama agar tidak rancu
          _storePassword = false;
          break;

        case 'keyboard-interactive':
          _authMethod = 'keyboard-interactive';
          // clear semua secret supaya aman
          _passwordController.clear();
          _keyPathController.clear();
          _keyPassphraseController.clear();
          _storePassword = false;
          _enablePasswordFallback = true;
          break;

        default:
          _authMethod = 'none';
          _passwordController.clear();
          _keyPathController.clear();
          _keyPassphraseController.clear();
          _storePassword = false;
          _enablePasswordFallback = true;
          break;
      }
    });
  }

  /// Dipanggil parent saat tombol Connect ditekan.
  /// Mengembalikan null kalau validasi gagal (dan sudah tampilkan snackbar).
  Map<String, dynamic>? readCredentials() {
    final host = _hostController.text.trim();
    final user = _usernameController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;

    if (host.isEmpty || user.isEmpty) {
      _toast('Host dan Username wajib diisi');
      return null;
    }
    if (port <= 0 || port > 65535) {
      _toast('Port tidak valid');
      return null;
    }

    switch (_authMethod) {
      case 'none':
        _toast('Pilih Initial method terlebih dahulu');
        return null;
      case 'password':
        return {
          'host': host,
          'port': port,
          'username': user,
          'method': 'password',
          'password': _passwordController.text,
          // tambahan flag UI
          'storePassword': _storePassword,
          'elevation': _elevation,
          'obfuscation': _enableObfuscation
              ? _obfuscationController.text
              : null,
          'kerberos': {
            'spn': _spnController.text,
            'gssKerberos': _gssKerberos,
            'requestDelegation': _requestDelegation,
            'gssapiKeyex': _gssapiKeyex,
          },
        };
      case 'publickey':
        if (_keyPathController.text.trim().isEmpty) {
          _toast('Path private key (.pem/.ppk) wajib diisi');
          return null;
        }
        return {
          'host': host,
          'port': port,
          'username': user,
          'method': 'publickey',
          'privateKeyPath': _keyPathController.text.trim(),
          'passphrase': _keyPassphraseController.text,
          'enablePasswordFallback': _enablePasswordFallback,
          // optional fallback password if UI menyiapkannya (tidak wajib)
          'fallbackPassword': _enablePasswordFallback
              ? _passwordController.text
              : null,
          'elevation': _elevation,
          'obfuscation': _enableObfuscation
              ? _obfuscationController.text
              : null,
          'kerberos': {
            'spn': _spnController.text,
            'gssKerberos': _gssKerberos,
            'requestDelegation': _requestDelegation,
            'gssapiKeyex': _gssapiKeyex,
          },
        };
      case 'keyboard-interactive':
        return {
          'host': host,
          'port': port,
          'username': user,
          'method': 'keyboard-interactive',
          'elevation': _elevation,
          'obfuscation': _enableObfuscation
              ? _obfuscationController.text
              : null,
          'kerberos': {
            'spn': _spnController.text,
            'gssKerberos': _gssKerberos,
            'requestDelegation': _requestDelegation,
            'gssapiKeyex': _gssapiKeyex,
          },
        };
      default:
        _toast('Metode tidak dikenali');
        return null;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey.shade50, Colors.grey.shade50],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildServerSection(theme)),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _buildAuthenticationSection(theme)),
              ],
            ),
            // ⛔️ tombol Connect dihilangkan — tombol ada di file 1 (footer)
          ],
        ),
      ),
    );
  }

  Widget _buildServerSection(ThemeData theme) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.blue.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Server', Icons.dns),
            const SizedBox(height: 16),
            _buildInputRow(
              'Host',
              _hostController,
              flex: true,
              enabled: !widget.isConnecting,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _buildInputRow(
                    'Port',
                    _portController,
                    width: 100,
                    enabled: !widget.isConnecting,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildCompactCheckbox(
                    'Enable obfuscation',
                    _enableObfuscation,
                    widget.isConnecting
                        ? null
                        : (value) =>
                              setState(() => _enableObfuscation = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInputRow(
              'Obfuscation keyword',
              _obfuscationController,
              enabled: !widget.isConnecting && _enableObfuscation,
              flex: true,
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Kerberos', Icons.security),
            const SizedBox(height: 16),
            _buildInputRow(
              'SPN',
              _spnController,
              flex: true,
              enabled: !widget.isConnecting,
            ),
            const SizedBox(height: 12),
            _buildCompactCheckbox(
              'GSS Kerberos key exchange',
              _gssKerberos,
              widget.isConnecting
                  ? null
                  : (value) => setState(() => _gssKerberos = value!),
            ),
            _buildCompactCheckbox(
              'Request delegation',
              _requestDelegation,
              widget.isConnecting
                  ? null
                  : (value) => setState(() => _requestDelegation = value!),
            ),
            _buildCompactCheckbox(
              'gssapi-keyex authentication',
              _gssapiKeyex,
              widget.isConnecting
                  ? null
                  : (value) => setState(() => _gssapiKeyex = value!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticationSection(ThemeData theme) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.indigo.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Authentication', Icons.person_outline),
            const SizedBox(height: 16),
            _buildInputRow(
              'Username',
              _usernameController,
              flex: true,
              enabled: !widget.isConnecting,
            ),
            const SizedBox(height: 12),
            // Initial method (starts with None)
            _buildDropdownRow(
              'Initial method',
              _authMethod,
              _authLabels.keys.toList(),
              widget.isConnecting
                  ? null
                  : (value) {
                      setState(() {
                        _authMethod = value!;
                        // Reset related fields when switching methods
                        _passwordController.clear();
                        _keyPathController.clear();
                        _keyPassphraseController.clear();
                      });
                    },
              labelBuilder: (val) => _authLabels[val] ?? val,
            ),
            const SizedBox(height: 12),
            // Dynamic fields based on selected method
            ..._buildAuthMethodFields(),
            const SizedBox(height: 12),
            // Elevation (left as-is)
            _buildDropdownRow(
              'Elevation',
              _elevation,
              const ['Default', 'None', 'Auto'],
              widget.isConnecting
                  ? null
                  : (value) => setState(() => _elevation = value!),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAuthMethodFields() {
    final disabled = widget.isConnecting;
    switch (_authMethod) {
      case 'password':
        return [
          _buildInputRow(
            'Password',
            _passwordController,
            obscureText: true,
            flex: true,
            enabled: !disabled,
          ),
          const SizedBox(height: 8),
          _buildCompactCheckbox(
            'Store encrypted password in profile',
            _storePassword,
            disabled ? null : (v) => setState(() => _storePassword = v!),
          ),
        ];
      case 'publickey':
        return [
          _buildInputRow(
            'Private key path (.pem/.ppk)',
            _keyPathController,
            flex: true,
            enabled: !disabled,
          ),
          const SizedBox(height: 8),
          _buildInputRow(
            'Key passphrase (opsional)',
            _keyPassphraseController,
            obscureText: true,
            flex: true,
            enabled: !disabled,
          ),
          const SizedBox(height: 8),
          _buildCompactCheckbox(
            'Enable password over kbdi fallback',
            _enablePasswordFallback,
            disabled
                ? null
                : (v) => setState(() => _enablePasswordFallback = v!),
          ),
          if (_enablePasswordFallback) ...[
            const SizedBox(height: 8),
            _buildInputRow(
              'Fallback password (opsional)',
              _passwordController,
              obscureText: true,
              flex: true,
              enabled: !disabled,
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: disabled
                  ? null
                  : () {
                      // Hindari dependency tambahan agar file tetap compile.
                      // Jika ingin file picker, tambahkan package `file_picker`
                      // dan gunakan FilePicker.platform.pickFiles() di sini.
                      _toast(
                        'Tambahkan package file_picker untuk browse file.',
                      );
                    },
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse…'),
            ),
          ),
        ];
      case 'keyboard-interactive':
        return [
          const Text(
            'Keyboard-interactive tidak membutuhkan input awal.\n'
            'Saat koneksi, server akan mengirim prompt (mis. OTP/Password AD).',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ];
      case 'none':
      default:
        return [
          const Text(
            'Pilih Initial method untuk menampilkan isian yang sesuai.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ];
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: Colors.blue.shade700, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildInputRow(
    String label,
    TextEditingController controller, {
    bool obscureText = false,
    bool enabled = true,
    bool flex = false,
    double? width,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: flex ? double.infinity : width,
          height: 36,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            enabled: enabled,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: Colors.blue, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              filled: true,
              fillColor: enabled ? Colors.white : Colors.grey.shade50,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownRow(
    String label,
    String value,
    List<String> items,
    Function(String?)? onChanged, {
    String Function(String)? labelBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: Theme(
            // ← lokal saja, hanya untuk dropdown ini
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(surfaceTint: Colors.transparent),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: DropdownButtonFormField<String>(
              value: value,
              dropdownColor: Colors.white, // menu popup-nya putih
              menuMaxHeight: 280, // opsional: biar gak terlalu tinggi
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Colors.blue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        labelBuilder != null ? labelBuilder(item) : item,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCheckbox(
    String title,
    bool value,
    Function(bool?)? onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged,
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _keyPathController.dispose();
    _keyPassphraseController.dispose();
    _spnController.dispose();
    _obfuscationController.dispose();
    super.dispose();
  }
}
