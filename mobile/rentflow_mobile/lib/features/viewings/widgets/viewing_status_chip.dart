import 'package:flutter/material.dart';

class ViewingStatusChip extends StatelessWidget {
  const ViewingStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(status));
  }
}
