import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/app/app.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await PreferencesStorage.create();

  runApp(
    ProviderScope(
      overrides: [preferencesStorageProvider.overrideWithValue(preferences)],
      child: const FriendsGameApp(),
    ),
  );
}
