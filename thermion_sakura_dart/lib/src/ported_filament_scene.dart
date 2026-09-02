import 'package:thermion_dart/thermion_dart.dart';

import 'sakura_app.dart';

@Deprecated('Use SakuraApp')
typedef SakuraFilamentScene = SakuraApp;

@Deprecated('Use SakuraApp.create')
Future<SakuraApp> buildPortedFilamentScene(ThermionViewer viewer) =>
    SakuraApp.create(viewer);
