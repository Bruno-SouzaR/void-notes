import 'package:flutter/material.dart';
import 'bridge/void_bridge.dart';
import 'platform/tray_hotkey.dart';
import 'screens/notes_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Instantiate bridge and hotkey controller
  final bridge = MockVoidBridge();
  final hotkeyService = TrayHotkeyService(bridge);
  await hotkeyService.initialize();

  runApp(VoidApp(bridge: bridge));
}

class VoidApp extends StatelessWidget {
  final VoidBridge bridge;

  const VoidApp({Key? key, required this.bridge}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V.O.I.D.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        primaryColor: const Color(0xFF161922),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.amber,
          surface: Color(0xFF161922),
        ),
      ),
      home: NotesScreen(bridge: bridge),
    );
  }
}
