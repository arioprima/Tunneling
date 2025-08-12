import 'package:flutter/material.dart';

class SFTPScreen extends StatelessWidget {
  final List<Map<String, dynamic>> files = [
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

  const SFTPScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(icon: Icon(Icons.refresh), onPressed: () {}),
              IconButton(icon: Icon(Icons.arrow_upward), onPressed: () {}),
              IconButton(icon: Icon(Icons.download), onPressed: () {}),
              IconButton(icon: Icon(Icons.create_new_folder), onPressed: () {}),
              IconButton(icon: Icon(Icons.delete), onPressed: () {}),
              Spacer(),
              Text('Remote path: /home/user'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final item = files[index];
              return ListTile(
                leading: Icon(
                  item['type'] == 'folder'
                      ? Icons.folder
                      : Icons.insert_drive_file,
                ),
                title: Text(item['name']),
                subtitle: Text('${item['size']} • ${item['modified']}'),
                trailing: Icon(Icons.more_vert),
                onTap: () {},
              );
            },
          ),
        ),
      ],
    );
  }
}
