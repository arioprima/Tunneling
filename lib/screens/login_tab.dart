import 'package:flutter/material.dart';

class LoginTab extends StatefulWidget {
  final Function(String host, int port, String username, String password)
  onConnect;

  const LoginTab({super.key, required this.onConnect});

  @override
  _LoginTabState createState() => _LoginTabState();
}

class _LoginTabState extends State<LoginTab> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server Section
            Expanded(flex: 2, child: _buildServerSection(theme)),
            const SizedBox(width: 16),
            // Authentication Section
            Expanded(flex: 1, child: _buildAuthenticationSection(theme)),
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
            _buildInputRow('Host', _hostController, flex: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _buildInputRow('Port', _portController, width: 100),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildCompactCheckbox(
                    'Enable obfuscation',
                    _enableObfuscation,
                    (value) => setState(() => _enableObfuscation = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInputRow(
              'Obfuscation keyword',
              _obfuscationController,
              enabled: _enableObfuscation,
              flex: true,
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Kerberos', Icons.security),
            const SizedBox(height: 16),
            _buildInputRow('SPN', _spnController, flex: true),
            const SizedBox(height: 12),
            _buildCompactCheckbox(
              'GSS Kerberos key exchange',
              _gssKerberos,
              (value) => setState(() => _gssKerberos = value!),
            ),
            _buildCompactCheckbox(
              'Request delegation',
              _requestDelegation,
              (value) => setState(() => _requestDelegation = value!),
            ),
            _buildCompactCheckbox(
              'gssapi-keyex authentication',
              _gssapiKeyex,
              (value) => setState(() => _gssapiKeyex = value!),
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
            _buildInputRow('Username', _usernameController, flex: true),
            const SizedBox(height: 12),
            _buildInputRow(
              'Password',
              _passwordController,
              obscureText: true,
              flex: true,
            ),
            const SizedBox(height: 12),
            _buildDropdownRow(
              'Initial method',
              _authMethod,
              ['password', 'publickey', 'keyboard-interactive'],
              (value) => setState(() => _authMethod = value!),
            ),
            const SizedBox(height: 12),
            _buildCompactCheckbox(
              'Store encrypted password in profile',
              _storePassword,
              (value) => setState(() => _storePassword = value!),
            ),
            _buildCompactCheckbox(
              'Enable password over kbdi fallback',
              _enablePasswordFallback,
              (value) => setState(() => _enablePasswordFallback = value!),
            ),
            const SizedBox(height: 12),
            _buildDropdownRow('Elevation', _elevation, [
              'Default',
              'None',
              'Auto',
            ], (value) => setState(() => _elevation = value!)),
          ],
        ),
      ),
    );
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue, width: 1.5),
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
    Function(String?) onChanged,
  ) {
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
          child: DropdownButtonFormField<String>(
            value: value,
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue, width: 1.5),
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
                    child: Text(item, style: const TextStyle(fontSize: 14)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCheckbox(
    String title,
    bool value,
    Function(bool?) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => onChanged(!value),
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
    _spnController.dispose();
    _obfuscationController.dispose();
    super.dispose();
  }
}
