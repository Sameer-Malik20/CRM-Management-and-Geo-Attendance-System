import 'package:flutter/material.dart';

Widget inOutButton(
  String buttonText,
  Color color,
  Function() callback, {
  bool enabled = true,
  String? disabledMessage,
  required BuildContext context,
}) {
  final effectiveColor = enabled ? color : Colors.grey;
  return Container(
    height: 60,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16.0),
      border: Border.all(color: effectiveColor, width: 3),
      color: effectiveColor.withOpacity(0.04),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: () {
          if (enabled) {
            callback();
            return;
          }
          if (disabledMessage != null && disabledMessage.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(disabledMessage)),
            );
          }
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              buttonText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: effectiveColor,
                fontFamily: "Poppins-Bold",
                fontSize: 18,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
