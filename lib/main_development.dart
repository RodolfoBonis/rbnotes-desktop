import 'package:rbnotes/app/app.dart';
import 'package:rbnotes/bootstrap.dart';
import 'package:rbnotes/core/config/app_config.dart';

Future<void> main() => bootstrap(RbNotesApp.new, flavor: Flavor.development);
