class ImageConstant {
  ImageConstant._privateConstructor();

  static final ImageConstant _instance = ImageConstant._privateConstructor();

  factory ImageConstant() {
    return _instance;
  }

  static const String logo = "assets/logo/logo.png";
  static const String encrypted = "assets/images/encrypted.png";
  static const String idea = "assets/images/info.png";
  static const String feedback = "assets/images/feedback.png";
  static const String icon = "assets/icons/icon.png";
}
