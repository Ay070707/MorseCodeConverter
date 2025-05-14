import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:logger/logger.dart';

final logger = Logger();



void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // ✅ Add this

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BluetoothVoiceApp(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class BluetoothVoiceApp extends StatefulWidget {
  const BluetoothVoiceApp({super.key});

  @override
  BluetoothVoiceAppState createState() => BluetoothVoiceAppState();
}

class BluetoothVoiceAppState extends State<BluetoothVoiceApp> {
  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  BluetoothConnection? _connection;
  bool _isConnected = false;
  bool _isListening = false;
  String _receivedData = '';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.microphone.request();
    await Permission.locationWhenInUse.request();
  }

  Future<void> _connectToHC05() async {
    List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    BluetoothDevice? hc05 = devices.firstWhere(
      (d) => d.name == "HC-05",
      orElse: () => devices.first,
    );

    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(hc05.address);
      setState(() {
        _connection = connection;
        _isConnected = true;
      });

      connection.input!.listen((data) {
        setState(() {
          _receivedData += String.fromCharCodes(data);
        });
      });
    } catch (e) {
      logger.e('Connection failed', error: e);
    }
  }

  void _sendMessage() async {
    if (_connection != null && _isConnected && _textController.text.isNotEmpty) {
      _connection!.output.add(utf8.encode('${_textController.text}\n'));
      await _connection!.output.allSent;
      _textController.clear();
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) => logger.i('Speech status: $status'),
      onError: (error) => logger.e('Speech error: $error'),
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _textController.text = result.recognizedWords;
          });
        },
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _connection?.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Voice + Bluetooth to HC-05"),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth_connected),
            onPressed: _connectToHC05,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: "Type or use mic",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isListening ? _stopListening : _startListening,
                  icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                  label: Text(_isListening ? "Stop" : "Speak"),
                ),
                SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _sendMessage,
                  icon: Icon(Icons.send),
                  label: Text("Send"),
                ),
              ],
            ),
            SizedBox(height: 20),
            Text("Received from Arduino:"),
            Container(
              height: 100,
              padding: EdgeInsets.all(8),
              color: Colors.grey[200],
              child: SingleChildScrollView(child: Text(_receivedData)),
            ),
          ],
        ),
      ),
    );
  }
}
