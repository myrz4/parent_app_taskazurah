import 'package:flutter/material.dart';

class MyChildrenScreen extends StatelessWidget {
  const MyChildrenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy data (sementara)
    final children = [
      {
        'name': 'Ali Bin Ahmad',
        'photoUrl': 'https://cdn-icons-png.flaticon.com/512/3667/3667444.png'
      },
      {
        'name': 'Siti Nur Alia',
        'photoUrl': 'https://cdn-icons-png.flaticon.com/512/3667/3667339.png'
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F4), // soft eco green bg
      appBar: AppBar(
        title: const Text('My Children', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF4CAF50), // eco green
        centerTitle: true,
        elevation: 2,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: children.length,
        itemBuilder: (context, index) {
          final child = children[index];
          return Card(
            elevation: 5,
            shadowColor: Colors.green.withOpacity(0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Opening ${child['name']}'s details..."),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.green.shade100,
                      child: ClipOval(
                        child: Image.network(
                          (child['photoUrl'] ?? '').toString(),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.child_care,
                            color: Colors.green.shade700,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        color: Colors.green, size: 18),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
