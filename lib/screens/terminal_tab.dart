import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  _TerminalTabState createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final List<String> _terminalOutput = [];
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _terminalOutput.add('Welcome to SSH Terminal');
    _terminalOutput.add('Type "help" for available commands');
  }

  void _executeCommand(String command) {
    if (command.isEmpty) return;

    setState(() {
      _terminalOutput.add('\$ $command');
    });

    // Simulate command execution
    Future.delayed(Duration(milliseconds: 100), () {
      String response = '';

      switch (command.trim()) {
        case 'help':
          response = 'Available commands: ls, pwd, echo, clear, exit';
          break;
        case 'ls':
          response = 'Documents\nDownloads\nPictures\nfile.txt';
          break;
        case 'pwd':
          response = '/home/user';
          break;
        case 'clear':
          setState(() {
            _terminalOutput.clear();
          });
          return;
        case 'exit':
          setState(() {
            _isConnected = false;
            _terminalOutput.add('Disconnected from server');
          });
          return;
        default:
          response = 'Command executed: $command';
      }

      setState(() {
        _terminalOutput.add(response);
        _scrollToBottom();
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!_isConnected)
          Padding(
            padding: EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isConnected = true;
                  _terminalOutput.add('Connected to SSH server');
                });
              },
              child: Text('Connect to Terminal'),
            ),
          ),
        Expanded(
          child: Container(
            color: Colors.black,
            padding: EdgeInsets.all(8),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _terminalOutput.length,
              itemBuilder: (context, index) {
                return Text(
                  _terminalOutput[index],
                  style: TextStyle(
                    color: Colors.green,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                );
              },
            ),
          ),
        ),
        Container(
          color: Colors.grey[200],
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    hintText: 'Enter command...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (cmd) {
                    _executeCommand(cmd);
                    _commandController.clear();
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.send),
                onPressed: () {
                  _executeCommand(_commandController.text);
                  _commandController.clear();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
