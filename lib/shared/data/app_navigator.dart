import 'package:flutter/material.dart';

abstract final class AppNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  static BuildContext? get currentContext => key.currentContext;
}
