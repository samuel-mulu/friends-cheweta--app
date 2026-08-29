class RealtimeEvent {
  const RealtimeEvent({required this.name, required this.payload});

  final String name;
  final Map<String, dynamic> payload;

  int? get protocolVersion => _asInt(payload['protocolVersion']);
  String? get eventId => payload['eventId']?.toString();
  DateTime? get serverTime => DateTime.tryParse(payload['serverTime']?.toString() ?? '');
  String? get matchId => payload['matchId']?.toString();
  int? get version => _asInt(payload['version']);

  Map<String, dynamic> get data {
    final value = payload['data'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
