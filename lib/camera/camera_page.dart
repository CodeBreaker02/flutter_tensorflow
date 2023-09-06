import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tensorflow/assets/assets.dart';
import 'package:tensorflow_models/posenet.dart' as posenet;
import 'package:tensorflow_models/tensorflow_models.dart' as tf_models;

const _poseNetConfig = tf_models.ModelConfig(
  architecture: 'MobileNetV1',
  outputStride: 16,
  inputResolution: 257,
  multiplier: 0.5,
  quantBytes: 2,
);
const _poseConfig = tf_models.SinglePersonInterfaceConfig(
  flipHorizontal: false,
);
const _minPoseConfidence = 0.1;
const _minPartConfidence = 0.5;
const _supportedParts = ['leftEye', 'rightEye'];

class CameraPage extends StatefulWidget {
  const CameraPage({Key? key}) : super(key: key);

  static Route route() {
    return MaterialPageRoute(builder: (_) => const CameraPage());
  }

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _controller = CameraController(
    options: const CameraOptions(
      audio: AudioConstraints(enabled: false),
      video: VideoConstraints(height: 1024, width: 1024),
    ),
  );
  StreamSubscription<CameraImage>? _subscription;
  posenet.PoseNet? _net;
  CameraImage? _image;
  posenet.Pose? _pose;

  @override
  void initState() {
    super.initState();
    Future.wait([
      _initializePoseNet(),
      _initializeCameraController(),
    ]).then((_) {
      _subscription = _controller.imageStream.listen(_onImage);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _net?.dispose();
    super.dispose();
  }

  Future<void> _initializeCameraController() async {
    await _controller.initialize();
    await _controller.play();
  }

  Future<void> _initializePoseNet() async {
    _net = await posenet.load(_poseNetConfig);
  }

  void _onImage(CameraImage image) async {
    _pose = await _net?.estimateSinglePose(
      tf_models.ImageData(
        data: Uint8ClampedList.fromList(image.raw.data),
        width: image.raw.width,
        height: image.raw.height,
      ),
      config: _poseConfig,
    );
    _image = image;
    if (_pose != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final pose = _pose;

    final headPosition = _computeHeadPosition(pose, const Size(1.0, 1.0));

    print('Head position: $headPosition');
    // Check the head position and display a message based on it
    var message = '';
    if (headPosition > 600) {
      message = 'Head is on the left';
    } else if (headPosition < 500) {
      message = 'Head is on the right';
    } else {
      message = 'Head is in the center';
    }
    return Scaffold(
      body: Camera(
        controller: _controller,
        placeholder: (_) => Center(child: CameraPlaceholder()),
        preview: (context, preview) {
          return CameraPreview(
            preview: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (image != null && pose != null)
                  CustomPaint(
                    key: const Key('photoboothView_posePainter_customPainter'),
                    size: Size(image.width.toDouble(), image.height.toDouble()),
                    painter: PosePainter(pose: pose, image: Assets.dash.image),
                  ),
              ],
            ),
            onSnapPressed: () {},
          );
        },
        error: (_, error) => Center(child: CameraError(error: error)),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            message,
            style: const TextStyle(fontSize: 16.0),
          ),
        ),
      ),
    );
  }
}

class CameraPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const CircularProgressIndicator();
}

class CameraPreview extends StatelessWidget {
  const CameraPreview({
    Key? key,
    required this.preview,
    required this.onSnapPressed,
  }) : super(key: key);

  final Widget preview;
  final VoidCallback onSnapPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
      ],
    );
  }
}

class CameraError extends StatelessWidget {
  const CameraError({Key? key, required this.error}) : super(key: key);

  final CameraException error;

  @override
  Widget build(BuildContext context) {
    return Text(error.toLocalizedError(context));
  }
}

extension on CameraException {
  String toLocalizedError(BuildContext context) {
    if (this is CameraNotAllowedException) {
      return "l10n.previewPageCameraNotAllowedText";
    }
    return description;
  }
}

class PosePainter extends CustomPainter {
  const PosePainter({required this.pose, required this.image});

  final posenet.Pose pose;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = _computePositions(pose: pose, image: image);
    for (final position in positions) {
      canvas.drawImage(image, position, Paint());
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.pose.score != pose.score;
  }
}

List<Offset> _computePositions({
  required ui.Image image,
  posenet.Pose? pose,
  Size scale = const Size(1.0, 1.0),
}) {
  final positions = <Offset>[];
  final _pose = pose;
  if (_pose == null) return positions;
  if (_pose.score < _minPoseConfidence) return positions;
  for (final keypoint in _pose.keypoints) {
    if (!_supportedParts.contains(keypoint.part)) continue;
    if (keypoint.score < _minPartConfidence) continue;
    final x = keypoint.position.x.ceilToDouble();
    final y = keypoint.position.y.ceilToDouble();
    final offset = Offset(x * scale.width, y * scale.height);
    final normalizedOffset = Offset(
      ((offset.dx - image.width) + 100),
      ((offset.dy - image.height) - 120),
    );
    positions.add(normalizedOffset);
  }
  return positions;
}

double _computeHeadPosition(posenet.Pose? pose, Size scale) {
  if (pose == null || pose.score < _minPoseConfidence) {
    return 0.0; // Pose not detected or confidence too low
  }

  // Find the positions of the left and right eyes
  posenet.Keypoint? leftEye;
  posenet.Keypoint? rightEye;

  for (final keypoint in pose.keypoints) {
    if (keypoint.part == 'leftEye') {
      leftEye = keypoint;
    } else if (keypoint.part == 'rightEye') {
      rightEye = keypoint;
    }
  }

  // If either eye is not detected or their confidence is too low, return 0.0
  if (leftEye == null ||
      rightEye == null ||
      leftEye.score < _minPartConfidence ||
      rightEye.score < _minPartConfidence) {
    return 0.0;
  }

  // Calculate the horizontal position of the head as the average of left and right eyes
  final headPosition = (leftEye.position.x + rightEye.position.x) / 2.0;
  final scaledHeadPosition = headPosition * scale.width;

  return scaledHeadPosition;
}
