import 'package:flutter/material.dart';

class InteractiveZoomDial extends StatefulWidget {
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final double minZoom;
  final double maxZoom;

  const InteractiveZoomDial({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    this.minZoom = 0.5,
    this.maxZoom = 8.0,
  });

  @override
  State<InteractiveZoomDial> createState() => _InteractiveZoomDialState();
}

class _InteractiveZoomDialState extends State<InteractiveZoomDial> {
  bool _isDragging = false;
  double _dragStartZoom = 1.0;
  double _dragStartX = 0.0;

  static const List<double> _presetLevels = [0.5, 1.0, 2.0, 3.0, 5.0];

  String _formatLevel(double level) {
    if (level == 0.5) return '.5';
    return level.toInt().toString();
  }

  String _getSemanticsLabel(double level, bool isSelected) {
    String desc;
    if (level == 0.5) {
      desc = 'Zoom 0.5x Ultra-Wide';
    } else if (level == 1.0) {
      desc = 'Zoom 1x Grande-Angular';
    } else {
      desc = 'Zoom ${level.toInt()}x Telefoto';
    }
    return isSelected ? '$desc selecionado' : 'Ajustar para $desc';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Controle de Zoom Óptico e Digital',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador flutuante ao arrastar
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _isDragging ? 1.0 : 0.0,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(
                '${widget.currentZoom.toStringAsFixed(1)}×',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Pílula de botões com suporte a gesto de arrasto horizontal
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() {
                _isDragging = true;
                _dragStartX = details.localPosition.dx;
                _dragStartZoom = widget.currentZoom;
              });
            },
            onHorizontalDragUpdate: (details) {
              final delta = details.localPosition.dx - _dragStartX;
              final targetZoom = (_dragStartZoom + delta * 0.02)
                  .clamp(widget.minZoom, widget.maxZoom);
              widget.onZoomChanged(targetZoom);
            },
            onHorizontalDragEnd: (_) {
              setState(() => _isDragging = false);
            },
            onHorizontalDragCancel: () {
              setState(() => _isDragging = false);
            },
            child: Container(
              padding: const EdgeInsets.all(4),
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
                children: _presetLevels.map((level) {
                  final isSelected = (widget.currentZoom - level).abs() < 0.25;

                  return Semantics(
                    button: true,
                    selected: isSelected,
                    excludeSemantics: true, // Evita concatenação duplicada do Text filho
                    label: _getSemanticsLabel(level, isSelected),
                    child: InkWell(
                      onTap: () => widget.onZoomChanged(level),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        // Alvo mínimo de 48x48 dp
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        alignment: Alignment.center,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          constraints: BoxConstraints(
                            minWidth: isSelected ? 32 : 28,
                            minHeight: isSelected ? 32 : 28,
                          ),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _formatLevel(level),
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white70,
                                fontFamily: 'monospace',
                                fontSize: isSelected ? 12 : 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
