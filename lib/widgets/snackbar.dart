import 'package:flutter/material.dart';

void showSuccessSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.green.shade700,
    icon: Icons.check_circle_outline,
  );
}

void showErrorSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.red.shade800,
    icon: Icons.error_outline,
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.blue.shade800,
    icon: Icons.info_outline,
  );
}

void _showSnackBar(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  required IconData icon,
}) {
  final contentColor = Colors.white;

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
