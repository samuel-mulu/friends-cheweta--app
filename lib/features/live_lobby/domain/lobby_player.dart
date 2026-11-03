enum LobbyPlayerState { online, ready, challenged }

class LobbyPlayer {
  const LobbyPlayer({
    required this.userId,
    required this.displayName,
    required this.state,
    this.readyAt,
    this.isSelf = false,
  });

  final String userId;
  final String displayName;
  final LobbyPlayerState state;
  final DateTime? readyAt;
  final bool isSelf;

  bool get isReady => state == LobbyPlayerState.ready;
  bool get isBusy => state == LobbyPlayerState.challenged;

  LobbyPlayer copyWith({LobbyPlayerState? state, DateTime? readyAt, bool? isSelf}) {
    return LobbyPlayer(
      userId: userId,
      displayName: displayName,
      state: state ?? this.state,
      readyAt: readyAt ?? this.readyAt,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  factory LobbyPlayer.fromJson(Map<String, dynamic> json) {
    return LobbyPlayer(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      state: _state(json['state']?.toString()),
      readyAt: DateTime.tryParse(json['readyAt']?.toString() ?? ''),
      isSelf: json['isSelf'] == true,
    );
  }

  static LobbyPlayerState _state(String? value) {
    return switch (value) {
      'READY' => LobbyPlayerState.ready,
      'CHALLENGED' => LobbyPlayerState.challenged,
      _ => LobbyPlayerState.online,
    };
  }
}
