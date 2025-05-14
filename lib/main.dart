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

  List<BluetoothDevice> _devicesList = [];
  String connectionStatus = "Not connected";

  void showSnackBar(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}



  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  BluetoothConnection? _connection;
  bool _isConnected = false;
  bool _isListening = false;
  String _receivedData = '';

  @override
  void initState() {
    super.initState();
    _checkPermissions().then((_) => _loadBondedDevices());
  }


  Future<void> _checkPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request(); // <-- Add this
    await Permission.bluetoothAdvertise.request(); // <-- Optional, for completeness
    await Permission.microphone.request();
    await Permission.locationWhenInUse.request();

    _devicesList = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() {});
  }


  Future<void> _loadBondedDevices() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() {
      _devicesList = devices;
    });
  }

  void _showDevicePicker() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Bluetooth Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: _devicesList.isEmpty
                ? Text("No paired devices found.")
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devicesList.length,
                    itemBuilder: (context, index) {
                      BluetoothDevice device = _devicesList[index];
                      return ListTile(
                        title: Text(device.name ?? "Unknown"),
                        subtitle: Text(device.address),
                        onTap: () {
                          Navigator.pop(context); // close dialog
                          _connectToDevice(device);
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }



  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _connection = connection;
        _isConnected = true;
      });
      showSnackBar("Connected to ${device.name}");

      connection.input!.listen((data) {
        setState(() {
          _receivedData += String.fromCharCodes(data);
        });
      });
    } catch (e) {
      logger.e('Connection failed', error: e);
      showSnackBar("Failed to connect to ${device.name}");
    }
  }



  void _sendMessage() async {
    if (!_isConnected || _connection == null) {
      showSnackBar("Not connected to a device.");
      return;
    }

    final message = _textController.text.trim();

    if (message.isNotEmpty) {
      try {
        _connection!.output.add(utf8.encode('$message\n')); // Send to Arduino
        await _connection!.output.allSent;

        logger.i("Sent to Arduino: $message");
 // ✅ Log to terminal
        _textController.clear(); // Clear the input field
      } catch (e) {
        logger.e("Failed to send message", error: e);
        showSnackBar("Error sending data.");
      }
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
        title: Text("Morse_Project_App"),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth_searching),
            onPressed: _showDevicePicker,
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


            Text(
              _isConnected ? "Connected to Bluetooth device" : "Not connected",
              style: TextStyle(color: _isConnected ? Colors.green : Colors.red),
            ),
            SizedBox(height: 10),

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
