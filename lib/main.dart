import 'package:flutter/material.dart';
import 'screens/ssh_client_window.dart';

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
