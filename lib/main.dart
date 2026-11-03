import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:friends_game_app/bootstrap.dart';

Future<void> main() async {
  await dotenv.load(fileName: '.env').catchError((_) {});
  await bootstrap();
}
