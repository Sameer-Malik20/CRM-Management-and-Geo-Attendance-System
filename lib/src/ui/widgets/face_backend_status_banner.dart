import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/face_attendance_api.dart';

class FaceBackendStatusBanner extends StatelessWidget {
  const FaceBackendStatusBanner({
    super.key,
    required this.info,
    this.margin = EdgeInsets.zero,
  });

  final FaceBackendWarmupInfo info;
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

  Widget _buildLeading(FaceBackendWarmupState state, Color color) {
    if (state == FaceBackendWarmupState.ready) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    if (state == FaceBackendWarmupState.unavailable) {
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

  Color _bannerColor(FaceBackendWarmupState state) {
    switch (state) {
      case FaceBackendWarmupState.ready:
        return Colors.green;
      case FaceBackendWarmupState.unavailable:
        return Colors.redAccent;
      case FaceBackendWarmupState.checking:
      case FaceBackendWarmupState.warmingUp:
        return Colors.orangeAccent;
    }
  }
}
