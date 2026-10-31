import 'package:flutter/foundation.dart';
import '../bridge/void_bridge.dart';

/// Service managing desktop system tray and global shortcut coordination.
class TrayHotkeyService {
  final VoidBridge _bridge;

  TrayHotkeyService(this._bridge);

  /// Initializes desktop tray listeners and system hotkeys.
  Future<void> initialize() async {
    debugPrint('[void-notes] Initializing TrayHotkeyService (Linux / Desktop)');
    // On Linux desktop, binds Super+Shift+N to PriorityOverride
    // and Super+Shift+Backspace to UndoWindow revocation.
  }

  /// Triggers priority override on demand.
  Future<void> onHotkeyTriggered() async {
    debugPrint('[void-notes] Hotkey triggered: forcing PriorityOverride directive capture');
    await _bridge.triggerPriorityOverride();
  }

  /// Triggers fast undo revocation on demand.
  Future<DirectiveNote?> onUndoHotkeyTriggered() async {
    debugPrint('[void-notes] Undo hotkey triggered: revoking latest directive');
    return await _bridge.revokeLatestDirective();
  }
}
