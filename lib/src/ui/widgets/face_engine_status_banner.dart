import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/on_device_face_recognition_service.dart';

class FaceEngineStatusBanner extends StatelessWidget {
  const FaceEngineStatusBanner({
    super.key,
    required this.info,
    this.margin = EdgeInsets.zero,
  });

  final FaceEngineStatusInfo info;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final color = _bannerColor(info.state);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          _buildLeading(info.state, color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              info.message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeading(FaceEngineState state, Color color) {
    if (state == FaceEngineState.ready) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    if (state == FaceEngineState.error) {
      return Icon(Icons.error_outline, color: color, size: 18);
    }

    return SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Color _bannerColor(FaceEngineState state) {
    switch (state) {
      case FaceEngineState.ready:
        return Colors.green;
      case FaceEngineState.error:
        return Colors.redAccent;
      case FaceEngineState.loading:
        return Colors.orangeAccent;
    }
  }
}
