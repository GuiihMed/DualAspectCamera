import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ExposureSlider extends StatefulWidget {
  final double currentExposure;
  final ValueChanged<double> onExposureChanged;
  final double minExposure;
  final double maxExposure;

  const ExposureSlider({
    super.key,
    required this.currentExposure,
    required this.onExposureChanged,
    this.minExposure = -2.0,
    this.maxExposure = 2.0,
  });

  @override
  State<ExposureSlider> createState() => _ExposureSliderState();
}

class _ExposureSliderState extends State<ExposureSlider> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    const trackHeight = 160.0;
    final totalRange = widget.maxExposure - widget.minExposure;
    final normalized = (widget.currentExposure - widget.minExposure) / (totalRange == 0 ? 1 : totalRange);
    final clampedNorm = normalized.clamp(0.0, 1.0);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final next = (widget.currentExposure + 0.2).clamp(widget.minExposure, widget.maxExposure);
            widget.onExposureChanged(next);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final prev = (widget.currentExposure - 0.2).clamp(widget.minExposure, widget.maxExposure);
            widget.onExposureChanged(prev);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      builder: (context, hasFocus) {
        return Semantics(
          slider: true,
          label: 'Controle de Exposição e Luminosidade',
          value: '${widget.currentExposure >= 0 ? "+" : ""}${widget.currentExposure.toStringAsFixed(1)} EV',
          onIncrease: () {
            final next = (widget.currentExposure + 0.5).clamp(widget.minExposure, widget.maxExposure);
            widget.onExposureChanged(next);
          },
          onDecrease: () {
            final prev = (widget.currentExposure - 0.5).clamp(widget.minExposure, widget.maxExposure);
            widget.onExposureChanged(prev);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: trackHeight + 32),
            decoration: hasFocus
                ? BoxDecoration(
                    border: Border.all(color: Colors.amberAccent, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                setState(() => _isDragging = true);
              },
              onVerticalDragUpdate: (details) {
                // Arrastar para cima aumenta EV
                final deltaNorm = -details.primaryDelta! / trackHeight;
                final newExposure = (widget.currentExposure + deltaNorm * totalRange)
                    .clamp(widget.minExposure, widget.maxExposure);
                widget.onExposureChanged(newExposure);
              },
              onVerticalDragEnd: (_) {
                setState(() => _isDragging = false);
              },
              onVerticalDragCancel: () {
                setState(() => _isDragging = false);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bubble com valor EV
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isDragging || hasFocus ? 1.0 : 0.0,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${widget.currentExposure >= 0 ? "+" : ""}${widget.currentExposure.toStringAsFixed(1)} EV',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Trilho minimalista com Thumb
                  SizedBox(
                    width: 32,
                    height: trackHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Trilho de alto contraste
                        Container(
                          width: 2,
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),

                        // Thumb com ícone do sol
                        Positioned(
                          bottom: (trackHeight - 28) * clampedNorm,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.wb_sunny_outlined,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
