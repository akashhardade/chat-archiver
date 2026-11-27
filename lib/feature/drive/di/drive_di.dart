import 'package:get/get.dart';
import 'package:chat_archiver/core/storage/storage_service.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:chat_archiver/feature/drive/data/google_drive_auth_service.dart';
import 'package:chat_archiver/feature/drive/data/google_drive_gateway.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';
import 'package:chat_archiver/feature/drive/domain/drive_gateway.dart';

/// Google Drive auth + gateway.
class DriveDI {
  static void setup() {
    final storage = Get.find<StorageService>();
    final cache = StorageDriveIdCache(storage);
    Get.put<DriveIdCache>(cache, permanent: true);
    final auth = GoogleDriveAuthService(storage: storage, idCache: cache);
    Get.put<DriveAuthService>(auth, permanent: true);
    Get.put<DriveGateway>(
      GoogleDriveGateway(auth: auth, cache: cache),
      permanent: true,
    );
  }
}
