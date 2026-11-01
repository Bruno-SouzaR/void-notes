import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'bridge/void_bridge.dart';
import 'platform/tray_hotkey.dart';
import 'screens/notes_screen.dart';
import 'theme/void_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);

  final homeDir = Platform.environment['HOME'] ?? Directory.current.path;
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

  const VoidApp({super.key, required this.bridge});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'void-notes',
      debugShowCheckedModeBanner: false,
      theme: VoidTheme.darkTheme,
      home: NotesScreen(bridge: bridge),
    );
  }
}
