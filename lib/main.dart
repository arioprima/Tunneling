import 'dart:convert';
import 'package:bitvise/screens/sftp_window_placeholder.dart';
import 'package:flutter/material.dart';
import 'screens/ssh_client_window.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  // Jika proses ini diluncurkan sebagai sub-window (nanti oleh desktop_multi_window),
  // ia akan membawa argumen "multi_window <windowId> <jsonArgs>".
  if (args.isNotEmpty && args.first == 'multi_window') {
    final raw = (args.length > 2 && args[2].isNotEmpty) ? args[2] : '{}';
    final Map<String, dynamic> data = jsonDecode(raw);

    final kind = data['kind'] as String? ?? 'sftp';

    if (kind == 'sftp') {
      // Sementara: placeholder agar project tetap build.
      // Di langkah berikutnya kita ganti dengan UI SFTP asli.
      runApp(
        SftpWindow(
          profile: (data['profile'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
      );
      return;
    }

    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Unknown sub-window'))),
        debugShowCheckedModeBanner: false,
      ),
    );
    return;
  }

  // Mode normal: jalankan aplikasi utama
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        visualDensity: VisualDensity.compact,
        useMaterial3: true,
      ),
      home: const SSHClientWindow(),
      debugShowCheckedModeBanner: false,
    );
  }
}
