import 'package:get/get.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/home/presentation/view_model/home_controller.dart';

class HomeDI {
  static void setup() {
    Get.lazyPut<HomeController>(
      () => HomeController(coordinator: Get.find<SyncCoordinator>()),
      fenix: true,
    );
  }
}
