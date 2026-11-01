import 'dart:io';
import 'package:flutter/material.dart';
import 'bridge/void_bridge.dart';
import 'platform/tray_hotkey.dart';
import 'screens/notes_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final homeDir = Platform.environment['HOME'] ?? '/var/home/brunosouzar';
  final projectRoot = Directory('$homeDir/projects/void-notes');
  final notesDir = Directory('${projectRoot.path}/notes');

  final bridge = LocalFileVoidBridge(
    notesDirectory: notesDir,
    projectRoot: projectRoot,
  );

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
      title: 'void-notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF141414),
        cardColor: const Color(0xFF282828),
        primaryColor: const Color(0xFF1C594D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1C594D),
          secondary: Color(0xFF224E16),
          surface: Color(0xFF282828),
          onPrimary: Color(0xFFE2E2E2),
          onSurface: Color(0xFFE2E2E2),
          outline: Color(0xFF4C4141),
        ),
      ),
      home: NotesScreen(bridge: bridge),
    );
  }
}
