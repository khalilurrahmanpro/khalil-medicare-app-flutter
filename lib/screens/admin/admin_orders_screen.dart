import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/invoice_service.dart';

const String baseUrl =
    "https://khalil-medicare-app-backend.onrender.com/api";

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() =>
      _AdminOrdersScreenState();
}

class _AdminOrdersScreenState
    extends State<AdminOrdersScreen> {

  List orders = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {

    try {

      SharedPreferences prefs =
          await SharedPreferences.getInstance();

      String? token = prefs.getString('token');

      final response = await http.get(
        Uri.parse("$baseUrl/admin-orders/"),
        headers: {
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {

        setState(() {

          orders = json.decode(response.body);

          loading = false;

        });

      } else {

        setState(() {
          loading = false;
        });

      }

    } catch (e) {

      setState(() {
        loading = false;
      });

      debugPrint(e.toString());

    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFFF5F5F5),

      appBar: AppBar(
        title: const Text(
          "Admin Orders",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        backgroundColor: const Color(0xFFD00000),

        foregroundColor: Colors.white,
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : orders.isEmpty
              ? const Center(
                  child: Text(
                    "No Orders Found",
                  ),
                )
              : RefreshIndicator(

                  onRefresh: fetchOrders,

                  child: ListView.builder(

                    padding: const EdgeInsets.all(12),

                    itemCount: orders.length,

                    itemBuilder: (context, index) {

                      final order = orders[index];

                      return Container(

                        margin:
                            const EdgeInsets.only(bottom: 12),

                        padding: const EdgeInsets.all(15),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius:
                              BorderRadius.circular(18),

                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            Row(

                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,

                              children: [

                                Text(
                                  "Order #${order['id']}",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),

                                Container(

                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),

                                  decoration: BoxDecoration(
                                    color: Colors.orange
                                        .withOpacity(0.1),

                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),

                                  child: Text(
                                    order['status']
                                        .toString(),

                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Text(
                              order['medicine_names']
                                  .toString(),

                              maxLines: 2,

                              overflow:
                                  TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 10),

                            Text(
                              "Total Bill: ৳${order['total_price']}",

                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),

                            const SizedBox(height: 15),

                            Row(

                              children: [

                                Expanded(

                                  child: ElevatedButton.icon(

                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.indigo,
                                      foregroundColor:
                                          Colors.white,
                                    ),

                                    onPressed: () async {

                                      List<
                                          Map<String,
                                              dynamic>> items = [

                                        {
                                          "name":
                                              order['medicine_names'],

                                          "qty": 1,

                                          "price":
                                              double.tryParse(
                                                    order[
                                                            'total_price']
                                                        .toString(),
                                                  ) ??
                                                  0,
                                        }

                                      ];

                                      await InvoiceService
                                          .generateInvoice(

                                        customerName:
                                            "Customer ID: ${order['user']}",

                                        phone:
                                            "Payment: ${order['payment_method']}",

                                        items: items,
                                      );
                                    },

                                    icon: const Icon(
                                      Icons.print,
                                    ),

                                    label: const Text(
                                      "Print Invoice",
                                    ),
                                  ),
                                ),

                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}