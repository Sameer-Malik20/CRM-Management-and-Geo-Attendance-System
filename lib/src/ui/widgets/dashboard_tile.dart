import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';

Widget buildTile(
    String icon, String title, String subtitle, BuildContext context, User user,
    [Function(BuildContext, User)? onTap]) {
  return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(28.0),
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28.0),
          onTap: onTap != null
              ? () {
                  onTap(context, user);
                }
              : () => print("Not yet set"),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFF8F1E7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28.0),
              border: Border.all(
                color: dashBoardColor.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: dashBoardColor.withValues(alpha: 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                    Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            leaveCardcolor.withValues(alpha: 0.20),
                            splashScreenColorBottom.withValues(alpha: 0.16),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Image.asset(
                        icon,
                        height: 40,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: appbarcolor,
                            fontFamily: "Bitter",
                            fontWeight: FontWeight.w700,
                            fontSize: 20.0,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.56),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.0,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: const [
                        Text(
                          "Open",
                          style: TextStyle(
                            color: dashBoardColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: dashBoardColor,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ));
}
