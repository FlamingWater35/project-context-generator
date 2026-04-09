import 'package:flutter/material.dart';

void showSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
}) {
  final Color backgroundColor = isError
      ? Colors.red.shade800
      : Colors.green.shade700;
  final IconData icon = isError
      ? Icons.error_outline
      : Icons.check_circle_outline;
  final Color contentColor = Colors.white;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          Icon(icon, color: contentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: contentColor, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
}
