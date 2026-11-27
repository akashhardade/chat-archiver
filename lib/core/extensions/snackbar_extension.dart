import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum SnackBarType { success, error, warning, info }

extension SnackBarExtension on GetInterface {
  void showSnackBar({
    required String message,
    String? title,
    SnackBarType type = SnackBarType.success,
  }) {
    hideSnackBar();
    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        backgroundColor = Colors.green[400]!;
        icon = Icons.check_circle_outline;
        title ??= 'Success';
        break;
      case SnackBarType.error:
        backgroundColor = Colors.red[400]!;
        icon = Icons.error_outline;
        title ??= 'Error';
        break;
      case SnackBarType.warning:
        backgroundColor = Colors.orange[400]!;
        icon = Icons.warning_amber_outlined;
        textColor = Colors.black87;
        title ??= 'Warning';
        break;
      case SnackBarType.info:
        backgroundColor = Colors.blue[400]!;
        icon = Icons.info_outline;
        title ??= 'Info';
        break;
    }

    Get.snackbar(
      title,
      message,
      icon: Icon(icon, color: textColor),
      backgroundColor: backgroundColor,
      colorText: textColor,
      borderRadius: 8,
      margin: const EdgeInsets.all(16),
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
    );
  }

  void showSuccessSnackBar({required String message, String? title}) {
    showSnackBar(message: message, title: title, type: SnackBarType.success);
  }

  void showErrorSnackBar({required String message, String? title}) {
    showSnackBar(message: message, title: title, type: SnackBarType.error);
  }

  void showWarningSnackBar({required String message, String? title}) {
    showSnackBar(message: message, title: title, type: SnackBarType.warning);
  }

  void showInfoSnackBar({required String message, String? title}) {
    showSnackBar(message: message, title: title, type: SnackBarType.info);
  }

  void showCustomSnackBar({
    required String message,
    required String title,
    required Color backgroundColor,
    required Color textColor,
    required IconData icon,
  }) {
    hideSnackBar();
    Get.snackbar(
      title,
      message,
      icon: Icon(icon, color: textColor),
      backgroundColor: backgroundColor,
      colorText: textColor,
      borderRadius: 8,
      margin: const EdgeInsets.all(16),
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
    );
  }

  void hideSnackBar() {
    if (Get.isSnackbarOpen) {
      Get.closeCurrentSnackbar();
    }
  }
}
