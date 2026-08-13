import 'package:flutter/material.dart';

class BookViewingScreen extends StatelessWidget {
  const BookViewingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a Viewing')),
      body: const Center(child: Text('Viewing booking form coming soon.')),
    );
  }
}
