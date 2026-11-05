import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/crop_guides_overlay.dart';
import '../widgets/interactive_zoom_dial.dart';
import '../widgets/exposure_slider.dart';
import '../widgets/top_status_bar.dart';
import '../widgets/capture_controls.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;

  // Zoom & Exposição
  double _currentZoom = 1.0;
  double _minZoom = 0.5;
  double _maxZoom = 8.0;
  double _currentExposure = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;

  // Modos e Toggles
  CameraCaptureMode _captureMode = CameraCaptureMode.video;
  String _resolution = '4K';
  int _fps = 30;
  bool _showGrid = true;
  bool _isTorchOn = false;
  bool _isRecording = false;
  int _recSeconds = 0;
  Timer? _recTimer;

  String? _lastCapturedPath;
  String? _liveAnnouncement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCameraController(cameraController.description);
    }
  }

  Future<void> _checkPermissionsAndInit() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus.isGranted && micStatus.isGranted && widget.cameras.isNotEmpty) {
      _initCameraController(widget.cameras[_selectedCameraIndex]);
    } else {
      _announce('Permissão de câmera ou microfone necessária');
    }
  }

  Future<void> _initCameraController(CameraDescription cameraDescription) async {
    final previousController = _controller;
    final controller = CameraController(
      cameraDescription,
      _getResolutionPreset(),
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await previousController?.dispose();

    if (mounted) {
      setState(() {
        _controller = controller;
        _isInitialized = false;
      });
    }

    try {
      await controller.initialize();
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _currentZoom = 1.0.clamp(_minZoom, _maxZoom);
          _currentExposure = 0.0.clamp(_minExposure, _maxExposure);
        });
      }
    } catch (e) {
      debugPrint('Erro ao inicializar câmera: $e');
      _announce('Falha ao iniciar visualizador da câmera');
    }
  }

  ResolutionPreset _getResolutionPreset() {
    if (_resolution == '4K') return ResolutionPreset.ultraHigh;
    if (_resolution == '1080p') return ResolutionPreset.high;
    return ResolutionPreset.medium;
  }

  void _announce(String message) {
    setState(() {
      _liveAnnouncement = message;
    });
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final clamped = zoom.clamp(_minZoom, _maxZoom);
      await _controller!.setZoomLevel(clamped);
      setState(() => _currentZoom = clamped);
    } catch (e) {
      debugPrint('Erro ao ajustar zoom: $e');
    }
  }

  Future<void> _setExposure(double exposure) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final clamped = exposure.clamp(_minExposure, _maxExposure);
      await _controller!.setExposureOffset(clamped);
      setState(() => _currentExposure = clamped);
    } catch (e) {
      debugPrint('Erro ao ajustar exposição: $e');
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final nextTorch = !_isTorchOn;
      await _controller!.setFlashMode(nextTorch ? FlashMode.torch : FlashMode.off);
      setState(() => _isTorchOn = nextTorch);
      _announce(nextTorch ? 'Lanterna ligada' : 'Lanterna desligada');
    } catch (e) {
      debugPrint('Erro ao alternar lanterna: $e');
      _announce('Lanterna indisponível');
    }
  }

  Future<void> _flipCamera() async {
    if (widget.cameras.length < 2) {
      _announce('Apenas uma câmera detectada no dispositivo');
      return;
    }
    _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    await _initCameraController(widget.cameras[_selectedCameraIndex]);
    final isFront = widget.cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
    _announce(isFront ? 'Câmera frontal ativada' : 'Câmera traseira ativada');
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) {
      return;
    }

    try {
      final file = await _controller!.takePicture();
      setState(() => _lastCapturedPath = file.path);
      _announce('Foto capturada com sucesso');
    } catch (e) {
      debugPrint('Erro ao capturar foto: $e');
      _announce('Erro ao capturar foto');
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      // Parar gravação
      try {
        final file = await _controller!.stopVideoRecording();
        _recTimer?.cancel();
        setState(() {
          _isRecording = false;
          _recSeconds = 0;
          _lastCapturedPath = file.path;
        });
        _announce('Gravação de vídeo finalizada e salva');
      } catch (e) {
        debugPrint('Erro ao parar gravação: $e');
      }
    } else {
      // Iniciar gravação
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _recSeconds = 0;
        });
        _announce('Gravação iniciada');

        _recTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recSeconds++);
          }
        });
      } catch (e) {
        debugPrint('Erro ao iniciar gravação: $e');
        _announce('Falha ao iniciar gravação');
      }
    }
  }

  String _formatTimecode(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Preview da Câmera em tela cheia com Semantics
          if (_isInitialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: isLandscape
                    ? _controller!.value.aspectRatio
                    : (1.0 / _controller!.value.aspectRatio),
                child: Semantics(
                  label: 'Visor da câmera ao vivo',
                  image: true,
                  child: CameraPreview(_controller!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white70,
                semanticsLabel: 'Inicializando visualizador da câmera',
              ),
            ),

          // 2. Guias Adaptativas 16:9 e 9:16 com 35% escurecimento lateral
          CropGuidesOverlay(
            isLandscape: isLandscape,
            showGrid: _showGrid,
          ),

          // 3. Região ao vivo acessível com geometria válida e container: true (A11Y-06)
          if (_liveAnnouncement != null)
            Semantics(
              container: true,
              liveRegion: true,
              child: Visibility(
                visible: false,
                maintainSemantics: true,
                child: Text(_liveAnnouncement!),
              ),
            ),

          // 4. UI Adaptativa: Paisagem vs Retrato
          if (isLandscape) _buildLandscapeLayout() else _buildPortraitLayout(),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return SafeArea(
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            // 1. Barra de status superior (Ordem 1.0)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1.0),
                child: Center(
                  child: TopStatusBar(
                    resolution: _resolution,
                    fps: _fps,
                    isRecording: _isRecording,
                    recTimecode: _formatTimecode(_recSeconds),
                    showGrid: _showGrid,
                    isTorchOn: _isTorchOn,
                    onToggleGrid: () => setState(() => _showGrid = !_showGrid),
                    onToggleTorch: _toggleTorch,
                    onFlipCamera: _flipCamera,
                    onSelectResolution: (res) {
                      setState(() => _resolution = res);
                      if (_controller != null) _initCameraController(_controller!.description);
                    },
                    onSelectFPS: (fps) {
                      setState(() => _fps = fps);
                    },
                  ),
                ),
              ),
            ),

            // 2. Slider de exposição na lateral direita (Ordem 2.0)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2.0),
                child: Center(
                  child: ExposureSlider(
                    currentExposure: _currentExposure,
                    onExposureChanged: _setExposure,
                    minExposure: _minExposure,
                    maxExposure: _maxExposure,
                  ),
                ),
              ),
            ),

            // 3. Discador de Zoom logo acima dos controles (Ordem 3.0)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(3.0),
                child: Center(
                  child: InteractiveZoomDial(
                    currentZoom: _currentZoom,
                    onZoomChanged: _setZoom,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                  ),
                ),
              ),
            ),

            // 4. Tríade de Captura na base (Ordem 4.0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(4.0),
                child: CaptureControls(
                  mode: _captureMode,
                  isRecording: _isRecording,
                  lastCapturedImagePath: _lastCapturedPath,
                  onModeChanged: (newMode) {
                    setState(() {
                      _captureMode = newMode;
                      if (newMode == CameraCaptureMode.cine) {
                        _fps = 24;
                      } else if (newMode == CameraCaptureMode.video) {
                        _fps = 30;
                      }
                    });
                  },
                  onShutterPressed: () {
                    if (_captureMode == CameraCaptureMode.foto) {
                      _takePicture();
                    } else {
                      _toggleRecording();
                    }
                  },
                  onQuickPhotoPressed: _takePicture,
                  onGalleryPressed: () {
                    _announce('Galeria de fotos');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return SafeArea(
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            // 1. Coluna Esquerda: Barra superior compacta (Ordem 1.0)
            Positioned(
              top: 10,
              left: 16,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1.0),
                child: TopStatusBar(
                  resolution: _resolution,
                  fps: _fps,
                  isRecording: _isRecording,
                  recTimecode: _formatTimecode(_recSeconds),
                  showGrid: _showGrid,
                  isTorchOn: _isTorchOn,
                  onToggleGrid: () => setState(() => _showGrid = !_showGrid),
                  onToggleTorch: _toggleTorch,
                  onFlipCamera: _flipCamera,
                  onSelectResolution: (res) {
                    setState(() => _resolution = res);
                    if (_controller != null) _initCameraController(_controller!.description);
                  },
                  onSelectFPS: (fps) => setState(() => _fps = fps),
                ),
              ),
            ),

            // 2. Zoom e Exposição na esquerda inferior (Ordem 2.0 e 3.0)
            Positioned(
              bottom: 12,
              left: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(2.0),
                    child: ExposureSlider(
                      currentExposure: _currentExposure,
                      onExposureChanged: _setExposure,
                      minExposure: _minExposure,
                      maxExposure: _maxExposure,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(3.0),
                    child: InteractiveZoomDial(
                      currentZoom: _currentZoom,
                      onZoomChanged: _setZoom,
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                    ),
                  ),
                ],
              ),
            ),

            // 3. Dock Lateral Direito: Modos, Shutter, Galeria e Foto Rápida (130px) (Ordem 4.0)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 130,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(4.0),
                    child: CaptureControls(
                      isLandscape: true,
                      mode: _captureMode,
                      isRecording: _isRecording,
                      lastCapturedImagePath: _lastCapturedPath,
                      onModeChanged: (newMode) {
                        setState(() {
                          _captureMode = newMode;
                          if (newMode == CameraCaptureMode.cine) {
                            _fps = 24;
                          } else if (newMode == CameraCaptureMode.video) {
                            _fps = 30;
                          }
                        });
                      },
                      onShutterPressed: () {
                        if (_captureMode == CameraCaptureMode.foto) {
                          _takePicture();
                        } else {
                          _toggleRecording();
                        }
                      },
                      onQuickPhotoPressed: _takePicture,
                      onGalleryPressed: () {
                        _announce('Galeria de fotos');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
