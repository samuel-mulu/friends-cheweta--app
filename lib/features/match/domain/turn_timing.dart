/// Per-turn clock from the server (Dama, Karta): who is on the clock, until
/// when, and away strikes per player.
class TurnTiming {
  const TurnTiming({this.version = 0, this.playerId, this.turnEndsAt, this.strikes = const {}, this.maxStrikes = 3});
  final int version;
  final String? playerId;
  final DateTime? turnEndsAt;
  final Map<String, int> strikes;
  final int maxStrikes;

  factory TurnTiming.fromJson(Map<String, dynamic> json) => TurnTiming(
        version: _int(json['version']),
        playerId: json['playerId']?.toString(),
        turnEndsAt: DateTime.tryParse(json['turnEndsAt']?.toString() ?? ''),
        strikes: (json['strikes'] is Map ? Map<String, dynamic>.from(json['strikes'] as Map) : const <String, dynamic>{})
            .map((key, value) => MapEntry(key, _int(value))),
        maxStrikes: json['maxStrikes'] == null ? 3 : _int(json['maxStrikes']),
      );

  TurnTiming copyWith({int? version, String? playerId, DateTime? turnEndsAt, bool clearClock = false, Map<String, int>? strikes, int? maxStrikes}) =>
      TurnTiming(
        version: version ?? this.version,
        playerId: clearClock ? null : playerId ?? this.playerId,
        turnEndsAt: clearClock ? null : turnEndsAt ?? this.turnEndsAt,
        strikes: strikes ?? this.strikes,
        maxStrikes: maxStrikes ?? this.maxStrikes,
      );
}

int _int(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
