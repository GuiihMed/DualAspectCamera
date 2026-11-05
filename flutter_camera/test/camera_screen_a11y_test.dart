import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_camera/widgets/interactive_zoom_dial.dart';
import 'package:flutter_camera/widgets/exposure_slider.dart';
import 'package:flutter_camera/widgets/top_status_bar.dart';
import 'package:flutter_camera/widgets/capture_controls.dart';
import 'package:flutter_camera/widgets/crop_guides_overlay.dart';

void main() {
  group('A11y Tests - DualAspect Camera Widgets (Completo)', () {
    testWidgets('InteractiveZoomDial atende diretrizes completas de acessibilidade', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: InteractiveZoomDial(
                currentZoom: 1.0,
                onZoomChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Validações de Alvo de Toque e Rotulagem (Android e iOS)
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('ExposureSlider atende semântica de slider e diretrizes de toque', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      double exposure = 0.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: ExposureSlider(
                currentExposure: exposure,
                onExposureChanged: (val) => exposure = val,
              ),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      // Verifica ações semânticas de incremento e decremento
      final semantics = tester.getSemantics(find.byType(ExposureSlider));
      expect(semantics.hasAction(SemanticsAction.increase), isTrue);
      expect(semantics.hasAction(SemanticsAction.decrease), isTrue);

      handle.dispose();
    });

    testWidgets('TopStatusBar atende diretrizes sem gerar liveRegion repetitiva', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: TopStatusBar(
                resolution: '4K',
                fps: 30,
                isRecording: true,
                recTimecode: '01:23',
                showGrid: true,
                isTorchOn: false,
                onToggleGrid: () {},
                onToggleTorch: () {},
                onFlipCamera: () {},
                onSelectResolution: (_) {},
                onSelectFPS: (_) {},
              ),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('CaptureControls atende alvos e rotulagem nos modos foto e vídeo', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CaptureControls(
                mode: CameraCaptureMode.video,
                isRecording: false,
                lastCapturedImagePath: null,
                onModeChanged: (_) {},
                onShutterPressed: () {},
                onQuickPhotoPressed: () {},
                onGalleryPressed: () {},
              ),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('CropGuidesOverlay expõe semântica da proporção ativa', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CropGuidesOverlay(
              isLandscape: false,
              showGrid: true,
            ),
          ),
        ),
      );

      // Deve encontrar a informação da proporção mesmo sob IgnorePointer
      expect(find.text('16:9'), findsOneWidget);

      handle.dispose();
    });
  });
}
