import 'package:flutter/material.dart';

class TopStatusBar extends StatelessWidget {
  final String resolution;
  final int fps;
  final bool isRecording;
  final String recTimecode;
  final bool showGrid;
  final bool isTorchOn;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleTorch;
  final VoidCallback onFlipCamera;
  final ValueChanged<String> onSelectResolution;
  final ValueChanged<int> onSelectFPS;

  const TopStatusBar({
    super.key,
    required this.resolution,
    required this.fps,
    required this.isRecording,
    required this.recTimecode,
    required this.showGrid,
    required this.isTorchOn,
    required this.onToggleGrid,
    required this.onToggleTorch,
    required this.onFlipCamera,
    required this.onSelectResolution,
    required this.onSelectFPS,
  });

  void _showQualityModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    'Resolução',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['4K', '1080p', '720p'].map((res) {
                    final selected = res == resolution;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(res),
                        selected: selected,
                        onSelected: (_) {
                          onSelectResolution(res);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: const Text(
                    'Taxa de Quadros (FPS)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [60, 30, 24].map((f) {
                    final selected = f == fps;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f == 24 ? '24 (Cine)' : '$f FPS'),
                        selected: selected,
                        onSelected: (_) {
                          onSelectFPS(f);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Barra de ferramentas superior da câmera',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pílula de Qualidade (Resolução · FPS)
            Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Qualidade de vídeo: $resolution UHD a $fps quadros por segundo. Toque para alterar.',
              child: InkWell(
                onTap: () => _showQualityModal(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$resolution UHD · ${fps}FPS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),

            // Badge de gravação (container: true, liveRegion: false para evitar spam sonoro contínuo a cada 1s)
            if (isRecording) ...[
              const SizedBox(width: 4),
              Semantics(
                container: true,
                liveRegion: false,
                label: 'Duração da gravação em andamento: $recTimecode',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        recTimecode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Separador
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 1,
              height: 16,
              color: Colors.white.withOpacity(0.2),
            ),

            // Ícone Microfone VU
            Semantics(
              label: 'Microfone ativo para captura estéreo',
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.mic, size: 14, color: Colors.white70),
              ),
            ),

            // Separador
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 1,
              height: 16,
              color: Colors.white.withOpacity(0.2),
            ),

            // Botão Grade 3x3
            Semantics(
              button: true,
              toggled: showGrid,
              label: 'Alternar grade de enquadramento 3x3',
              child: IconButton(
                tooltip: 'Alternar grade de enquadramento 3x3',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.grid_3x3,
                  size: 18,
                  color: showGrid ? Colors.white : Colors.white70,
                ),
                onPressed: onToggleGrid,
              ),
            ),

            // Botão Lanterna (ícone muda de glifo e cor)
            Semantics(
              button: true,
              toggled: isTorchOn,
              label: isTorchOn ? 'Desligar lanterna' : 'Ligar lanterna',
              child: IconButton(
                tooltip: isTorchOn ? 'Desligar lanterna' : 'Ligar lanterna',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
                icon: Icon(
                  isTorchOn ? Icons.flash_on : Icons.flash_off,
                  size: 18,
                  color: isTorchOn ? Colors.amberAccent : Colors.white70,
                ),
                onPressed: onToggleTorch,
              ),
            ),

            // Botão Inverter Câmera
            Semantics(
              button: true,
              label: 'Alternar entre câmera frontal e traseira',
              child: IconButton(
                tooltip: 'Alternar entre câmera frontal e traseira',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.flip_camera_ios,
                  size: 18,
                  color: Colors.white,
                ),
                onPressed: onFlipCamera,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
