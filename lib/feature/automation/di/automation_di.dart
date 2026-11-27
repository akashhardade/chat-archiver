import 'package:get/get.dart';
import 'package:chat_archiver/feature/automation/data/method_channel_automation_bridge.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';

/// Native automation bridge (MethodChannel + EventChannel).
class AutomationDI {
  static void setup() {
    // Created eagerly: the constructor registers the handler for native ->
    // Dart `onProcessPending` calls.
    Get.put<AutomationBridge>(MethodChannelAutomationBridge(), permanent: true);
  }
}
