class WebDavCredentials {
  const WebDavCredentials({required this.password});

  final String password;

  Map<String, dynamic> toJson() => {'password': password};

  factory WebDavCredentials.fromJson(Map<String, dynamic> json) =>
      WebDavCredentials(password: json['password'] as String? ?? '');
}

class S3Credentials {
  const S3Credentials({required this.accessKey, required this.secretKey});

  final String accessKey;
  final String secretKey;

  Map<String, dynamic> toJson() => {
    'accessKey': accessKey,
    'secretKey': secretKey,
  };

  factory S3Credentials.fromJson(Map<String, dynamic> json) => S3Credentials(
    accessKey: json['accessKey'] as String? ?? '',
    secretKey: json['secretKey'] as String? ?? '',
  );
}

class SyncCredentials {
  const SyncCredentials({this.webDav, this.selfHostedToken, this.s3});

  final WebDavCredentials? webDav;
  final String? selfHostedToken;
  final S3Credentials? s3;

  Map<String, dynamic> toJson() => {
    if (webDav != null) 'webDav': webDav!.toJson(),
    if (selfHostedToken != null) 'selfHostedToken': selfHostedToken,
    if (s3 != null) 's3': s3!.toJson(),
  };

  factory SyncCredentials.fromJson(Map<String, dynamic> json) {
    final webDav = json['webDav'];
    final s3 = json['s3'];
    return SyncCredentials(
      webDav: webDav is Map
          ? WebDavCredentials.fromJson(Map<String, dynamic>.from(webDav))
          : null,
      selfHostedToken: json['selfHostedToken'] as String?,
      s3: s3 is Map
          ? S3Credentials.fromJson(Map<String, dynamic>.from(s3))
          : null,
    );
  }
}

abstract interface class SyncCredentialStore {
  Future<SyncCredentials> read();
  Future<void> write(SyncCredentials credentials);
}
