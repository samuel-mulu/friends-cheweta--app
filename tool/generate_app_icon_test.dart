// Renders the app mark into the Android launcher icons.
// Run after changing the logo:  flutter test tool/generate_app_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';

const _densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};

void main() {
  test('generate Android launcher icons', () async {
    for (final entry in _densities.entries) {
      final size = entry.value.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Launchers apply their own mask, so the legacy icon is rounded itself.
      const AppLogoPainter().paint(canvas, Size.square(size));
      final image = await recorder.endRecording().toImage(entry.value, entry.value);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
    }
  });
}
