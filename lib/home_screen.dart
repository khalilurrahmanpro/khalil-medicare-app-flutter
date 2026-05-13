import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainNavigationScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Khalil Medicare"),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // টোকেন মুছে দিবে
              Navigator.pushReplacementNamed(context, '/auth');
            },
          )
        ],
      ),
      body: Center(
        child: Text("Welcome! Your backend is connected.", style: TextStyle(fontSize: 18)),
      ),
    );
  }
}