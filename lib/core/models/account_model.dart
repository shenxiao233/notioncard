class AccountModel {
  const AccountModel({
    required this.id,
    required this.username,
    required this.nickname,
    required this.status,
    this.avatar,
  });

  final String id;
  final String username;
  final String nickname;
  final String status;
  final String? avatar;

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    final profileMap = profile is Map<String, dynamic> ? profile : null;
    final avatar =
        json['avatar'] ??
        json['avatarUrl'] ??
        json['photo'] ??
        json['image'] ??
        profileMap?['avatar'] ??
        profileMap?['avatarUrl'] ??
        profileMap?['photo'] ??
        profileMap?['image'];
    final accountId = json['id']?.toString().trim();
    final uid = json['uid']?.toString().trim();
    return AccountModel(
      id: accountId?.isNotEmpty == true ? accountId! : uid ?? '',
      username: json['username']?.toString() ?? '',
      nickname:
          json['nickname']?.toString() ?? json['username']?.toString() ?? '',
      status: json['status']?.toString() ?? 'ACTIVE',
      avatar: avatar?.toString().trim().isEmpty == true
          ? null
          : avatar?.toString(),
    );
  }
}
