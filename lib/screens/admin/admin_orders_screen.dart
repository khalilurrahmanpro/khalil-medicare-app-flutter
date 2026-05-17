import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; // কল দেওয়ার সুবিধার জন্য

import '../../main.dart'; 
import '../../services/invoice_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAllOrders();
  }

  // --- ডাটা ফেচ করার ফাংশন ---
  Future<void> fetchAllOrders() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final response = await http.get(
        Uri.parse("$baseUrl/admin-orders/"),
        headers: {
          'Authorization': 'Token $token', 
          'Content-Type': 'application/json'
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        setState(() {
          orders = (data is List) ? data : (data['results'] ?? []);
          orders = orders.reversed.toList(); // নতুন অর্ডার উপরে দেখাবে
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        title: const Text("ORDER MANAGEMENT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(onPressed: fetchAllOrders, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : orders.isEmpty
              ? const Center(child: Text("No orders found!"))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) => _buildOrderCard(orders[index]),
                ),
    );
  }

  // --- অর্ডার কার্ড ডিজাইন ---
  Widget _buildOrderCard(dynamic order) {
    // আইটেম লিস্ট তৈরি
    List currentItems = [];
    if (order['items'] != null && (order['items'] as List).isNotEmpty) {
      currentItems = order['items'];
    } else if (order['medicine_names'] != null && order['medicine_names'] != "") {
      currentItems = (order['medicine_names'] as String).split(',').map((name) => {
        'medicine_name': name.trim(),
        'quantity': '?', // সঠিক ডাটা না থাকলে ? দেখাবে
        'unit_type': '',
      }).toList();
    }

    double grandTotal = double.tryParse(order['total_price'].toString()) ?? 0;
    String status = order['status']?.toString() ?? "Pending";

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: CircleAvatar(
          backgroundColor: status.toLowerCase() == 'delivered' ? Colors.green[50] : Colors.orange[50],
          child: Icon(
            status.toLowerCase() == 'delivered' ? Icons.check_circle : Icons.pending_actions,
            color: status.toLowerCase() == 'delivered' ? Colors.green : Colors.orange,
          ),
        ),
        title: Text("Order ID: #${order['id']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text("Total Bill: ৳${grandTotal.toStringAsFixed(1)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.keyboard_arrow_down),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text("CUSTOMER INFO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                _infoRow(Icons.person, "Name", order['username']),
                _infoRow(Icons.phone, "Phone", order['phone'], isPhone: true),
                _infoRow(Icons.location_on, "Address", order['address']),
                
                const SizedBox(height: 15),
                const Text("ORDERED ITEMS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                
                // আইটেম লিস্ট প্রদর্শন
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: currentItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text("• ${item['medicine_name'] ?? item['name']}", style: const TextStyle(fontSize: 13))),
                          Text("Qty: ${item['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
                
                const SizedBox(height: 20),
                // অ্যাকশন বাটনসমূহ
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87, 
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                        onPressed: () async {
                          try {
                            final pdf = await InvoiceService.generateInvoice(order: order, items: currentItems);
                            await Printing.layoutPdf(onLayout: (format) async => pdf, name: 'Invoice_${order['id']}');
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text("INVOICE"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo, 
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                        onPressed: () => _updateStatus(order['id']),
                        icon: const Icon(Icons.sync_alt, size: 18),
                        label: const Text("STATUS"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- ইনফরমেশন রো (কল করার সুবিধাসহ) ---
  Widget _infoRow(IconData icon, String label, String? value, {bool isPhone = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.indigo[300]),
          const SizedBox(width: 10),
          Expanded(
            child: Text("$label: ${value ?? 'N/A'}", style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ),
          if (isPhone && value != null)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse("tel:$value")),
              child: const Icon(Icons.call, color: Colors.green, size: 20),
            ),
        ],
      ),
    );
  }

  // --- স্ট্যাটাস আপডেট করার ফাংশন ---
  void _updateStatus(int id) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("Update Order Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          ListTile(
            leading: const Icon(Icons.pending, color: Colors.orange),
            title: const Text("Mark as Pending"),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.delivery_dining, color: Colors.blue),
            title: const Text("Mark as Shipped"),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text("Mark as Delivered"),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}