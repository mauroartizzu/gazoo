class Settings {
  final Duration idleTimeout;
  final bool autoStartLastServer;
  final String? lastServerId;
  final bool darkMode;
  final bool verboseLogging;

  const Settings({
    required this.idleTimeout,
    required this.autoStartLastServer,
    this.lastServerId,
    required this.darkMode,
    required this.verboseLogging,
  });

  static const Settings defaults = Settings(
    idleTimeout: Duration(seconds: 60),
    autoStartLastServer: false,
    lastServerId: null,
    darkMode: false,
    verboseLogging: false,
  );

  Settings copyWith({
    Duration? idleTimeout,
    bool? autoStartLastServer,
    String? lastServerId,
    bool? darkMode,
    bool? verboseLogging,
  }) {
    return Settings(
      idleTimeout: idleTimeout ?? this.idleTimeout,
      autoStartLastServer: autoStartLastServer ?? this.autoStartLastServer,
      lastServerId: lastServerId ?? this.lastServerId,
      darkMode: darkMode ?? this.darkMode,
      verboseLogging: verboseLogging ?? this.verboseLogging,
    );
  }

  Map<String, dynamic> toJson() => {
        'idleTimeoutSeconds': idleTimeout.inSeconds,
        'autoStartLastServer': autoStartLastServer,
        'lastServerId': lastServerId,
        'darkMode': darkMode,
        'verboseLogging': verboseLogging,
      };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        idleTimeout: Duration(seconds: json['idleTimeoutSeconds'] as int? ?? 60),
        autoStartLastServer: json['autoStartLastServer'] as bool? ?? false,
        lastServerId: json['lastServerId'] as String?,
        darkMode: json['darkMode'] as bool? ?? false,
        verboseLogging: json['verboseLogging'] as bool? ?? false,
      );
}
