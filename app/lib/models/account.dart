final class Account {
  const Account({
    required this.id,
    required this.email,
    required this.displayName,
    required this.emailVerified,
  });

  final String id;
  final String email;
  final String displayName;
  final bool emailVerified;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'email_verified': emailVerified,
  };

  @override
  String toString() => 'Account(id: $id)';
}
