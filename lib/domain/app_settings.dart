enum AppearancePreference { system, light, dark }

enum RefreshInterval {
  fifteenMinutes(15),
  thirtyMinutes(30),
  sixtyMinutes(60);

  const RefreshInterval(this.minutes);

  final int minutes;
  Duration get duration => Duration(minutes: minutes);
}

class AppSettings {
  const AppSettings({
    this.appearance = AppearancePreference.system,
    this.refreshInterval = RefreshInterval.thirtyMinutes,
  });

  final AppearancePreference appearance;
  final RefreshInterval refreshInterval;

  AppSettings copyWith({
    AppearancePreference? appearance,
    RefreshInterval? refreshInterval,
  }) {
    return AppSettings(
      appearance: appearance ?? this.appearance,
      refreshInterval: refreshInterval ?? this.refreshInterval,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'appearance': appearance.name,
      'refreshInterval': refreshInterval.name,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      return const AppSettings();
    }
    return AppSettings(
      appearance: AppearancePreference.values.firstWhere(
        (value) => value.name == json['appearance'],
        orElse: () => AppearancePreference.system,
      ),
      refreshInterval: RefreshInterval.values.firstWhere(
        (value) => value.name == json['refreshInterval'],
        orElse: () => RefreshInterval.thirtyMinutes,
      ),
    );
  }
}
