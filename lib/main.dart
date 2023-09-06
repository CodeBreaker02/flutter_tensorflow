import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tensorflow/app/app.dart';
import 'package:flutter_tensorflow/app/app_bloc_observer.dart';
import 'package:flutter_tensorflow/assets/assets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();
  FlutterError.onError = (details) {
    print(details.exceptionAsString());
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  runZonedGuarded(
    () => Assets.load().then((_) => runApp(const App())),
    (error, stackTrace) {
      print(error.toString());
      log(error.toString(), stackTrace: stackTrace);
    },
  );
}
