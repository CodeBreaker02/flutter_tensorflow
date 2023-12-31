import 'package:flutter/material.dart';
import 'package:flutter_tensorflow/camera/camera_page.dart';

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CameraPage(),
    );
  }
}
