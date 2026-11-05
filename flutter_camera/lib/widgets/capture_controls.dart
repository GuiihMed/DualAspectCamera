import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CameraCaptureMode { foto, video, cine }

class CaptureControls extends StatelessWidget {
  final CameraCaptureMode mode;
  final bool isRecording;
  final String? lastCapturedImagePath;
  final ValueChanged<CameraCaptureMode> onModeChanged;
  final VoidCallback onShutterPressed;
  final VoidCallback onQuickPhotoPressed;
  final VoidCallback onGalleryPressed;
  final bool isLandscape;

  const CaptureControls({
    super.key,
    required this.mode,
    required this.isRecording,
    required this.lastCapturedImagePath,
    required this.onModeChanged,
    required this.onShutterPressed,
    required this.onQuickPhotoPressed,
    required this.onGalleryPressed,
    this.isLandscape = false,
  });

  String _modeLabel(CameraCaptureMode m) {
    switch (m) {
      case CameraCaptureMode.foto:
        return 'FOTO';
      case CameraCaptureMode.video:
        return 'VÍDEO';
      case CameraCaptureMode.cine:
        return 'CINE';
    }
  }

  String _shutterSemanticsLabel() {
    if (isRecording) return 'Parar gravação de vídeo';
    if (mode == CameraCaptureMode.foto) return 'Capturar foto';
    if (mode == CameraCaptureMode.cine) return 'Iniciar gravação de vídeo cinema 24 quadros por segundo';
    return 'Iniciar gravação de vídeo';
  }

  Color _shutterColor() {
    if (mode == CameraCaptureMode.foto) return Colors.white;
    if (mode == CameraCaptureMode.cine) return const Color(0xFFDC2626);
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final modeSelector = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: CameraCaptureMode.values.map((m) {
        final isSelected = m == mode;
        final label = _modeLabel(m);

        return Semantics(
          button: true,
          selected: isSelected,
          excludeSemantics: true, // Evita concatenação duplicada do Text filho
          label: isSelected ? 'Modo $label ativo' : 'Alternar para modo $label',
          child: InkWell(
            onTap: isRecording ? null : () => onModeChanged(m),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(minWidth: 54, minHeight: 48),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );

    final shutterButton = Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.space ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          onShutterPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      builder: (context, hasFocus) {
        return Semantics(
          button: true,
          label: _shutterSemanticsLabel(),
          child: GestureDetector(
            onTap: onShutterPressed,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasFocus ? Colors.amberAccent : Colors.white.withOpacity(0.85),
                  width: hasFocus ? 4.0 : 2.5,
                ),
                boxShadow: hasFocus
                    ? [const BoxShadow(color: Colors.amber, blurRadius: 10, spreadRadius: 2)]
                    : null,
              ),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: isRecording ? 28 : 56,
                height: isRecording ? 28 : 56,
                decoration: BoxDecoration(
                  color: _shutterColor(),
                  borderRadius: BorderRadius.circular(isRecording ? 6 : 28),
                ),
              ),
            ),
          ),
        );
      },
    );

    final galleryButton = Semantics(
      button: true,
      label: 'Abrir galeria de mídia',
      child: InkWell(
        onTap: onGalleryPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: lastCapturedImagePath != null && File(lastCapturedImagePath!).existsSync()
                ? Image.file(
                    File(lastCapturedImagePath!),
                    fit: BoxFit.cover,
                  )
                : const Icon(Icons.photo_library_outlined, size: 20, color: Colors.white70),
          ),
        ),
      ),
    );

    final quickPhotoButton = Semantics(
      button: true,
      label: 'Capturar foto rápida em alta resolução',
      child: InkWell(
        onTap: onQuickPhotoPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.camera_alt_outlined, size: 20, color: Colors.white),
          ),
        ),
      ),
    );

    if (isLandscape) {
      // Disposição ergonômica lateral em Paisagem (largura total 130px)
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          modeSelector,
          const SizedBox(height: 12),
          shutterButton,
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              galleryButton,
              const SizedBox(width: 8),
              quickPhotoButton,
            ],
          ),
        ],
      );
    }

    // Disposição padrão em Retrato
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        modeSelector,
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              galleryButton,
              shutterButton,
              quickPhotoButton,
            ],
          ),
        ),
      ],
    );
  }
}
