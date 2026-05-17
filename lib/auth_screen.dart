import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';


class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true; // লগইন এবং রেজিস্ট্রেশন সুইচ করার জন্য
  bool isLoading = false; // লোডিং এনিমেশন দেখানোর জন্য
  final _formKey = GlobalKey<FormState>();

  // কন্ট্রোলারগুলো
  final TextEditingController userController = TextEditingController();
  final TextEditingController emailController = TextEditingController(); 
  final TextEditingController passController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  // আপনার Render এর এপিআই লিঙ্ক
  final String apiUrl = "https://khalil-medicare-app-backend.onrender.com/api";
 
Future<void> _submitAuth() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => isLoading = true);
  String endpoint = isLogin ? "/login/" : "/register/";
  String url = apiUrl + endpoint;

  try {
    Map<String, dynamic> bodyData = isLogin
        ? {
            'username': userController.text.trim(),
            'password': passController.text.trim(),
          }
        : {
            'username': userController.text.trim(),
            'email': emailController.text.trim(),
            'password': passController.text.trim(),
            'phone': phoneController.text.trim(),
          };

    // --- এই অংশটুকু খেয়াল করুন ---
    final response = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json", // এটি অবশ্যই লাগবে
        "Accept": "application/json",
      },
      body: json.encode(bodyData), // ডাটাকে JSON স্ট্রিং বানিয়ে পাঠাতে হবে
    );
    // ----------------------------

    print("Status Code: ${response.statusCode}");
    print("Response: ${response.body}");

    final data = json.decode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      _showError(data['error'] ?? "Login failed!");
    }
  } catch (e) {
    print("Error: $e");
    _showError("Connection error!");
  } finally {
    if (mounted) setState(() => isLoading = false);
  }
}

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // লোগো বা আইকন
                  const Icon(Icons.local_hospital_rounded, size: 80, color: Colors.indigo),
                  const SizedBox(height: 10),
                  Text(
                    isLogin ? "Welcome Back" : "Join Us",
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 30),

                  // ইউজারনেম ফিল্ড
                  TextFormField(
                    controller: userController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person),
                      labelText: "Username",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? "Enter username" : null,
                  ),
                  const SizedBox(height: 15),

                  // ইমেইল এবং ফোন ফিল্ড (শুধু রেজিস্ট্রেশনের সময় দেখাবে)
                  if (!isLogin) ...[
                    TextFormField(
                      controller: emailController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email),
                        labelText: "Email Address",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter email" : null,
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.phone),
                        labelText: "Phone Number",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter phone number" : null,
                    ),
                    const SizedBox(height: 15),
                  ],

                  // পাসওয়ার্ড ফিল্ড
                  TextFormField(
                    controller: passController,
                    obscureText: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock),
                      labelText: "Password",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.length < 6 ? "Minimum 6 characters" : null,
                  ),
                  const SizedBox(height: 30),

                  // সাবমিট বাটন
                  isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submitAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            isLogin ? "LOGIN" : "REGISTER",
                            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),

                  const SizedBox(height: 15),

                  // লগইন/রেজিস্টার সুইচ বাটন
                  TextButton(
                    onPressed: () {
                      setState(() {
                        isLogin = !isLogin;
                        _formKey.currentState?.reset();
                      });
                    },
                    child: Text(
                      isLogin ? "Don't have an account? Register Now" : "Already have an account? Login here",
                      style: const TextStyle(color: Colors.indigo, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}