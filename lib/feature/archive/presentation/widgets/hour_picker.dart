import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/utils/time_format.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';

/// Dropdown for the morning hour (0-23).
class HourPicker extends StatelessWidget {
  const HourPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SyncCoordinator>();
    return Obx(
      () => DropdownButtonFormField<int>(
        initialValue: c.morningHour.value,
        decoration: InputDecoration(
          labelText: TranslatorConst.timeLabel.tr,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(value: h, child: Text(TimeFormat.hour(h))),
        ],
        onChanged: (h) {
          if (h != null) c.setMorningHour(h);
        },
      ),
    );
  }
}
