class Game {
  const Game({
    required this.id,
    required this.code,
    required this.name,
    required this.enabled,
    this.description,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final bool enabled;

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      enabled: json['enabled'] == true,
    );
  }
}
