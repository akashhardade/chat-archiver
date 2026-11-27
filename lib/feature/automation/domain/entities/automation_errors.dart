/// Native error codes (see `doc/AUTOMATION_CHANNEL.md`) and plain-language
/// descriptions for the UI.
class AutomationErrorCodes {
  AutomationErrorCodes._();

  static const whatsappNotInstalled = 'whatsapp_not_installed';
  static const searchNotFound = 'search_not_found';
  static const groupNotFound = 'group_not_found';
  static const wrongChat = 'wrong_chat';
  static const menuNotFound = 'menu_not_found';
  static const exportNotFound = 'export_not_found';
  static const shareTargetNotFound = 'share_target_not_found';
  static const shareNotReceived = 'share_not_received';
  static const timeout = 'timeout';
  static const cancelled = 'cancelled';
  static const screenLocked = 'screen_locked';
  static const unexpectedScreen = 'unexpected_screen';

  static const String _support =
      'If it happens again, use Settings > Diagnostics and send the capture to support.';

  static const Map<String, String> _messages = {
    whatsappNotInstalled:
        'WhatsApp is not installed on this phone. Install WhatsApp and sign in, then tap Sync now.',
    searchNotFound:
        'Could not use the WhatsApp search box (WhatsApp may have changed its layout). Tap Sync now to try again. $_support',
    groupNotFound:
        'No chat with exactly this title was found in WhatsApp. Open Settings > Groups and correct the title (same capital letters, spaces and emoji), then tap Sync now.',
    wrongChat:
        'WhatsApp opened a different chat, or two chats have this exact title, so nothing was exported. Make the group title unique in WhatsApp or correct it in Settings > Groups.',
    menuNotFound:
        'Could not find the chat menu in WhatsApp (WhatsApp may have changed its layout). Tap Sync now to try again. $_support',
    exportNotFound:
        'Could not find "Export chat" in WhatsApp (WhatsApp may have changed its layout, or exporting is turned off for this group). Tap Sync now to try again. $_support',
    shareTargetNotFound:
        'Could not find "Save to Chat Archiver" in the share menu. Tap Sync now to try again. $_support',
    shareNotReceived:
        'WhatsApp did not deliver the export in time. It is retried automatically on the next run, or tap Sync now.',
    timeout:
        'WhatsApp took too long to respond. It is retried automatically on the next run, or tap Sync now.',
    cancelled:
        'The sync was stopped before it finished. Tap Sync now to run it again.',
    screenLocked:
        'The phone was locked during the sync. Tap Sync now and keep the phone unlocked, without touching it, until it finishes.',
    unexpectedScreen:
        'WhatsApp showed a screen the automation did not expect (for example a pop-up or an update notice). Open WhatsApp once, close any message it shows, then tap Sync now. $_support',
  };

  /// Codes that mean the user must fix something (title, WhatsApp install)
  /// rather than simply retry.
  static const Set<String> needsAttention = {
    groupNotFound,
    searchNotFound,
    wrongChat,
    whatsappNotInstalled,
  };

  static bool isCode(String? value) =>
      value != null && _messages.containsKey(value);

  /// Plain-language text for a native error code. Values that are not codes
  /// (already human text, e.g. upload errors) are returned unchanged.
  static String describe(String? errorOrCode) {
    if (errorOrCode == null || errorOrCode.isEmpty) return '';
    return _messages[errorOrCode] ?? errorOrCode;
  }
}
