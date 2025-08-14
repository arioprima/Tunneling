import 'dart:convert';
import 'dart:ui';
import 'package:bitvise/screens/sftp_window_placeholder.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'screens/ssh_client_window.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.isNotEmpty && args.first == 'multi_window') {
    // 🟢 Registrasi plugin untuk engine tambahan (wajib di Linux)
    DartPluginRegistrant.ensureInitialized();

    final int windowId = (args.length > 1) ? int.parse(args[1]) : 0;
    final Map<String, dynamic> data = (args.length > 2 && args[2].isNotEmpty)
        ? (jsonDecode(args[2]) as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final controller = WindowController.fromWindowId(windowId);
    runApp(
      _SftpSubApp(
        controller: controller,
        profile: (data['profile'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
    return;
  }

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

class _SftpSubApp extends StatelessWidget {
  const _SftpSubApp({required this.controller, required this.profile});

  final WindowController controller;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: SftpWindow(profile: profile, controller: controller),
      color: Colors.white,
    );
  }
}
