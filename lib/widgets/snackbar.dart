import 'package:flutter/material.dart';

void showSnackBar(BuildContext context, {required String message}) {
  final Color backgroundColor = Colors.indigoAccent;
  final Color contentColor = Colors.white;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: backgroundColor,
      content: Row(
        children: [
          Icon(Icons.error_outline, color: contentColor),
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
