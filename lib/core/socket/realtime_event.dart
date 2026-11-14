class RealtimeEvent {
  const RealtimeEvent({required this.name, required this.payload});

  final String name;
  final Map<String, dynamic> payload;

  int? get protocolVersion => _asInt(payload['protocolVersion']);
  String? get eventId => payload['eventId']?.toString();
  DateTime? get serverTime => DateTime.tryParse(payload['serverTime']?.toString() ?? '');
  String? get matchId => payload['matchId']?.toString();
  int? get version => _asInt(payload['version']);

  /// One server command can emit several events (a roll and its auto-played
  /// move, for instance). These identify the burst and this event's place in
  /// it; null from servers that predate them.
  String? get batchId => payload['batchId']?.toString();
  int? get batchIndex => _asInt(payload['batchIndex']);
  int? get batchSize => _asInt(payload['batchSize']);

  /// True when this is the last event of its command's burst (or unknown).
  bool get endsBatch {
    final index = batchIndex;
    final size = batchSize;
    if (index == null || size == null) return true;
    return index >= size - 1;
  }

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
