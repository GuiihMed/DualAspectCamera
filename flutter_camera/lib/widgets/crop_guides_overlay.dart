import 'package:flutter/material.dart';

class CropGuidesOverlay extends StatelessWidget {
  final bool isLandscape;
  final bool showGrid;

  const CropGuidesOverlay({
    super.key,
    required this.isLandscape,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      ignoringSemantics: false, // Permite que a árvore semântica seja gerada para leitores de tela
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final totalHeight = constraints.maxHeight;

          double guideWidth;
          double guideHeight;

          if (isLandscape) {
            // Em Paisagem, a guia ativa é 9:16 vertical no centro
            guideHeight = totalHeight;
            guideWidth = guideHeight * (9.0 / 16.0);
            if (guideWidth > totalWidth) {
              guideWidth = totalWidth;
              guideHeight = guideWidth * (16.0 / 9.0);
            }
          } else {
            // Em Retrato, a guia ativa é 16:9 horizontal no centro
            guideWidth = totalWidth;
            guideHeight = guideWidth * (9.0 / 16.0);
            if (guideHeight > totalHeight) {
              guideHeight = totalHeight;
              guideWidth = guideHeight * (16.0 / 9.0);
            }
          }

          final sideGutterWidth = (totalWidth - guideWidth) / 2.0;
          final topGutterHeight = (totalHeight - guideHeight) / 2.0;

          return Stack(
            children: [
              // Escurecimento lateral / superior (35% preto)
              if (isLandscape && sideGutterWidth > 0) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sideGutterWidth,
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: sideGutterWidth,
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ] else if (!isLandscape && topGutterHeight > 0) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: topGutterHeight,
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: topGutterHeight,
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ],

              // Caixa de Enquadramento Central
              Positioned(
                left: sideGutterWidth > 0 ? sideGutterWidth : 0,
                top: topGutterHeight > 0 ? topGutterHeight : 0,
                width: guideWidth,
                height: guideHeight,
                child: CustomPaint(
                  painter: _CropGuidePainter(showGrid: showGrid, isLandscape: isLandscape),
                  child: Stack(
                    children: [
                      // Badge indicando proporção com Semantics acessível
                      Positioned(
                        top: 12,
                        left: isLandscape ? null : 16,
                        right: isLandscape ? 16 : null,
                        child: Semantics(
                          container: true,
                          label: isLandscape
                              ? 'Guia de enquadramento vertical ativa proporção 9 por 16'
                              : 'Guia de enquadramento horizontal ativa proporção 16 por 9',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Text(
                              isLandscape ? '9:16' : '16:9',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CropGuidePainter extends CustomPainter {
  final bool showGrid;
  final bool isLandscape;

  _CropGuidePainter({required this.showGrid, required this.isLandscape});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Linhas de borda tracejadas
    if (isLandscape) {
      _drawDashedLine(canvas, const Offset(0, 0), Offset(0, size.height), borderPaint);
      _drawDashedLine(canvas, Offset(size.width, 0), Offset(size.width, size.height), borderPaint);
    } else {
      _drawDashedLine(canvas, const Offset(0, 0), Offset(size.width, 0), borderPaint);
      _drawDashedLine(canvas, Offset(0, size.height), Offset(size.width, size.height), borderPaint);
    }

    // Cantoneiras Brancas
    final bracketPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const bSize = 14.0;
    // Canto Superior Esquerdo
    canvas.drawLine(const Offset(4, 4), const Offset(4 + bSize, 4), bracketPaint);
    canvas.drawLine(const Offset(4, 4), const Offset(4, 4 + bSize), bracketPaint);

    // Canto Superior Direito
    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4 - bSize, 4), bracketPaint);
    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4, 4 + bSize), bracketPaint);

    // Canto Inferior Esquerdo
    canvas.drawLine(Offset(4, size.height - 4), Offset(4 + bSize, size.height - 4), bracketPaint);
    canvas.drawLine(Offset(4, size.height - 4), Offset(4, size.height - 4 - bSize), bracketPaint);

    // Canto Inferior Direito
    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4 - bSize, size.height - 4), bracketPaint);
    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4, 4 + bSize), bracketPaint);

    // Retículo Central
    final reticlePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.0;
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    canvas.drawLine(Offset(cx - 8, cy), Offset(cx - 2, cy), reticlePaint);
    canvas.drawLine(Offset(cx + 2, cy), Offset(cx + 8, cy), reticlePaint);
    canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy - 2), reticlePaint);
    canvas.drawLine(Offset(cx, cy + 2), Offset(cx, cy + 8), reticlePaint);

    // Grade dos Terços (3x3)
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      final stepX = size.width / 3.0;
      final stepY = size.height / 3.0;

      for (int i = 1; i <= 2; i++) {
        _drawDashedLine(canvas, Offset(stepX * i, 0), Offset(stepX * i, size.height), gridPaint);
        _drawDashedLine(canvas, Offset(0, stepY * i), Offset(size.width, stepY * i), gridPaint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 4.0;
    const dashSpace = 4.0;
    final totalDist = (p2 - p1).distance;
    final unitVector = (p2 - p1) / totalDist;

    double currentDist = 0.0;
    while (currentDist < totalDist) {
      final start = p1 + unitVector * currentDist;
      final endDist = (currentDist + dashLength).clamp(0.0, totalDist);
      final end = p1 + unitVector * endDist;
      canvas.drawLine(start, end, paint);
      currentDist += dashLength + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _CropGuidePainter oldDelegate) {
    return oldDelegate.showGrid != showGrid || oldDelegate.isLandscape != isLandscape;
  }
}
