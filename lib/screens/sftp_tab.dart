// sftp_tab.dart
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';

class SFTPScreen extends StatelessWidget {
  final SSHClient client; // diterima dari parent (belum dipakai di UI dummy)
  const SFTPScreen({super.key, required this.client});

  static const List<Map<String, String>> files = [
    {
      'name': 'Documents',
      'type': 'folder',
      'size': '--',
      'modified': '2023-10-15',
    },
    {
      'name': 'Downloads',
      'type': 'folder',
      'size': '--',
      'modified': '2023-10-14',
    },
    {
      'name': 'Pictures',
      'type': 'folder',
      'size': '--',
      'modified': '2023-10-13',
    },
    {
      'name': 'report.pdf',
      'type': 'file',
      'size': '2.4 MB',
      'modified': '2023-10-12',
    },
    {
      'name': 'notes.txt',
      'type': 'file',
      'size': '15 KB',
      'modified': '2023-10-11',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  /* nanti implement real refresh */
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: () {
                  /* cd .. */
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  /* download */
                },
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder),
                onPressed: () {
                  /* mkdir */
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  /* delete */
                },
              ),
              const Spacer(),
              const Text('Remote path: /home/user'),
            ],
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final item = files[index];
              final isFolder = item['type'] == 'folder';
              return ListTile(
                leading: Icon(
                  isFolder ? Icons.folder : Icons.insert_drive_file,
                ),
                title: Text(item['name'] ?? ''),
                subtitle: Text('${item['size']} • ${item['modified']}'),
                trailing: const Icon(Icons.more_vert),
                onTap: () {
                  // nanti: kalau folder -> cd ke folder tsb, kalau file -> preview/aksi lain
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
