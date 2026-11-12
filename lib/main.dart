import 'package:e1547/app/app.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 1000;
  runApp(const App());
}
