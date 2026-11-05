import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'screens/camera_screen.dart';

List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set immersive full-screen display
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  try {
    globalCameras = await availableCameras();
  } catch (e) {
    debugPrint('Erro ao listar câmeras disponíveis: $e');
  }

  runApp(const DualAspectApp());
}

class DualAspectApp extends StatelessWidget {
  const DualAspectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DualAspect Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFFE50914),
          surface: Color(0xFF141414),
        ),
        useMaterial3: true,
      ),
      home: CameraScreen(cameras: globalCameras),
    );
  }
}
