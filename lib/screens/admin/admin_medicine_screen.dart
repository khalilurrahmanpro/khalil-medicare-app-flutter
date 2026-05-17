import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const Color logoRed = Color(0xFFD00000);
const String baseUrl = "https://khalil-medicare-app-backend.onrender.com/api";

class AdminMedicineScreen extends StatefulWidget {
  const AdminMedicineScreen({super.key});

  @override
  State<AdminMedicineScreen> createState() => _AdminMedicineScreenState();
}

class _AdminMedicineScreenState extends State<AdminMedicineScreen> {
  List medicines = [];
  List filtered = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchMedicines();
  }

  Future<void> fetchMedicines() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$baseUrl/medicines/"));
      if (res.statusCode == 200) {
        List allMeds = json.decode(res.body);
        // আপনার সেই ব্র্যান্ড সর্টিং লজিক
        allMeds.sort((a, b) {
          int getPriority(String? catName) {
            String name = (catName ?? "").toLowerCase();
            if (name.contains("brand") && !name.contains("non")) return 1;
            if (name.contains("surgical")) return 2;
            if (name.contains("non brand")) return 3;
            return 4;
          }
          return getPriority(a['category_name']).compareTo(getPriority(b['category_name']));
        });
        setState(() {
          medicines = allMeds;
          filtered = medicines;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

Future<void> updateStock(dynamic medId, String newQty) async {
  if (newQty.isEmpty || medId == null) return;

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');

  // আপনার urls.py অনুযায়ী একদম সঠিক ইউআরএল:
  final String url = "$baseUrl/medicine/$medId/update-stock/"; 

  try {
    print("অনুরোধ পাঠানো হচ্ছে: $url"); 

    final response = await http.patch(
      Uri.parse(url),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        "stock_quantity": int.parse(newQty), 
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("stock update successfull!"), backgroundColor: Colors.green),
      );
      fetchMedicines(); // লিস্ট রিফ্রেশ করা
    } else {
      print("Error Response: ${response.body}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("ব্যর্থ: কোড ${response.statusCode}"), backgroundColor: Colors.red),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("এরর: $e"), backgroundColor: Colors.red),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Stock Management", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: logoRed,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: TextField(
              onChanged: (v) {
                setState(() {
                  filtered = medicines.where((m) => m['name'].toLowerCase().contains(v.toLowerCase())).toList();
                });
              },
              decoration: InputDecoration(
                hintText: "search medicine...",
                prefixIcon: const Icon(Icons.search, color: logoRed),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: logoRed))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final med = filtered[i];
                      TextEditingController stockCtrl = TextEditingController(text: med['stock_quantity'].toString());

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(med['image'] ?? '', width: 60, height: 60, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.medication, size: 40)),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(med['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text("Current: ${med['stock_quantity']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Container(
                                width: 120,
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: stockCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.system_update_alt_rounded, color: Colors.blue),
                                      onPressed: () => updateStock(med['id'], stockCtrl.text),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}