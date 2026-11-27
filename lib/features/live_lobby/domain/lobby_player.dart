enum LobbyPlayerState { online, ready, challenged }

class LobbyPlayer {
  const LobbyPlayer({
    required this.userId,
    required this.displayName,
    required this.state,
    this.gameModeId,
    this.stakeAmountMinor,
    this.readyAt,
    this.isSelf = false,
    this.tokensToWin,
    this.autoMatch,
  });

  final String userId;
  final String displayName;
  final LobbyPlayerState state;

  /// The stake (game mode) this player sits at, and its amount.
  final String? gameModeId;
  final int? stakeAmountMinor;
  final DateTime? readyAt;
  final bool isSelf;

  /// What they asked for when they got ready: the Ludo goal ("first to N
  /// home") and whether they are matched automatically. Null while online.
  final int? tokensToWin;
  final bool? autoMatch;

  bool get isReady => state == LobbyPlayerState.ready;
  bool get isBusy => state == LobbyPlayerState.challenged;

  LobbyPlayer copyWith({LobbyPlayerState? state, String? gameModeId, DateTime? readyAt, bool? isSelf}) {
    return LobbyPlayer(
      userId: userId,
      displayName: displayName,
      state: state ?? this.state,
      gameModeId: gameModeId ?? this.gameModeId,
      stakeAmountMinor: stakeAmountMinor,
      readyAt: readyAt ?? this.readyAt,
      isSelf: isSelf ?? this.isSelf,
      tokensToWin: tokensToWin,
      autoMatch: autoMatch,
    );
  }

  factory LobbyPlayer.fromJson(Map<String, dynamic> json, {String? gameModeId}) {
    final goal = int.tryParse(json['tokensToWin']?.toString() ?? '');
    return LobbyPlayer(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      state: _state(json['state']?.toString()),
      gameModeId: json['gameModeId']?.toString() ?? gameModeId,
      stakeAmountMinor: int.tryParse(json['stakeAmountMinor']?.toString() ?? ''),
      readyAt: DateTime.tryParse(json['readyAt']?.toString() ?? ''),
      isSelf: json['isSelf'] == true,
      tokensToWin: goal != null && goal >= 1 && goal <= 4 ? goal : null,
      autoMatch: json['autoMatch'] is bool ? json['autoMatch'] as bool : null,
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
