import 'package:flutter/material.dart';

// Shows a transient green success banner notifying users of successful clipboard or file updates
void showSuccessSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.green.shade700,
    icon: Icons.check_circle_outline,
  );
}

// Displays a transient red error banner conveying detailed exceptions or validation failures
void showErrorSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.red.shade800,
    icon: Icons.error_outline,
  );
}

// Presents a transient blue informational alert representing status shifts or layout updates
void showInfoSnackBar(BuildContext context, String message) {
  _showSnackBar(
    context,
    message: message,
    backgroundColor: Colors.blue.shade800,
    icon: Icons.info_outline,
  );
}

// Root scaffolding constructor framing global visual elements of the notification banners
void _showSnackBar(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  required IconData icon,
}) {
  const contentColor = Colors.white;

  try {
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
                style: const TextStyle(color: contentColor, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  } catch (e) {
    debugPrint('Unable to manifest overlay alert message dialog safely: $e');
  }
}
