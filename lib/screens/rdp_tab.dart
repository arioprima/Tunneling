import 'package:flutter/material.dart';

class RDPTab extends StatelessWidget {
  const RDPTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.desktop_windows, size: 100, color: Colors.blue),
          SizedBox(height: 20),
          Text(
            'Remote Desktop Connection',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text('Start RDP Session'),
          ),
          SizedBox(height: 20),
          Text(
            'Configure RDP settings in the Options tab',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
