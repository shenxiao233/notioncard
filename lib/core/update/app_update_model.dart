class AppUpdateManifest {
  const AppUpdateManifest({
    required this.versionName,
    required this.buildNumber,
    required this.notes,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.mandatory,
    this.releaseUrl,
    this.iosStoreUrl,
    this.patchUrl,
    this.patchSha256,
    this.patchSizeBytes,
    this.patchFromBuildNumber,
  });

  final String versionName;
  final int buildNumber;
  final String notes;
  final String? downloadUrl;
  final String? sha256;
  final int? sizeBytes;
  final bool mandatory;
  final String? releaseUrl;
  final String? iosStoreUrl;

  // Reserved for a future native binary-delta implementation. A self-hosted
  // APK still needs the full APK as a safe fallback.
  final String? patchUrl;
  final String? patchSha256;
  final int? patchSizeBytes;
  final int? patchFromBuildNumber;

  bool get hasDownload => downloadUrl != null && downloadUrl!.isNotEmpty;
  bool get hasSha256 =>
      sha256 != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256!);
  bool get canDownload => hasDownload && hasSha256;
  bool get hasPatch => patchUrl != null && patchUrl!.isNotEmpty;
}
