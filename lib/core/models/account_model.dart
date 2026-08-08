class AccountModel {
  const AccountModel({
    required this.id,
    required this.username,
    required this.nickname,
    required this.status,
    this.role = 'user',
    this.avatar,
  });

  final String id;
  final String username;
  final String nickname;
  final String status;
  final String role;
  final String? avatar;

  static const Object _avatarNotProvided = Object();

  AccountModel copyWith({
    String? id,
    String? username,
    String? nickname,
    String? status,
    String? role,
    Object? avatar = _avatarNotProvided,
  }) {
    return AccountModel(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      status: status ?? this.status,
      role: role ?? this.role,
      avatar: identical(avatar, _avatarNotProvided)
          ? this.avatar
          : avatar as String?,
    );
  }

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : null;
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
    final roleValue =
        json['role'] ??
        json['roles'] ??
        json['userRole'] ??
        profileMap?['role'] ??
        profileMap?['roles'] ??
        profileMap?['userRole'];
    final isAdmin = json['isAdmin'] == true || profileMap?['isAdmin'] == true;
    return AccountModel(
      id: accountId?.isNotEmpty == true ? accountId! : uid ?? '',
      username: json['username']?.toString() ?? '',
      nickname:
          json['nickname']?.toString() ??
          json['displayName']?.toString() ??
          json['username']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'ACTIVE',
      role: isAdmin ? 'admin' : _normalizeRole(roleValue),
      avatar: avatar?.toString().trim().isEmpty == true
          ? null
          : avatar?.toString(),
    );
  }

  static String _normalizeRole(Object? value) {
    if (value is Iterable) {
      final roles = value
          .map((item) => item.toString().trim().toLowerCase())
          .toSet();
      if (roles.contains('admin')) return 'admin';
      if (roles.contains('user')) return 'user';
    }

    return value?.toString().trim().toLowerCase() == 'admin' ? 'admin' : 'user';
  }
}
