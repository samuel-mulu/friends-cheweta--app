import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a basic Material smoke widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Friends Game Hub')),
      ),
    );

    expect(find.text('Friends Game Hub'), findsOneWidget);
  });
}
