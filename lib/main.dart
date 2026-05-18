import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io'; 
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_screen.dart'; 
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/admin_medicine_screen.dart';

// --- গ্লোবাল ভেরিয়েবল ---
const Color logoRed = Color(0xFFD00000);
const Color logoYellow = Color(0xFFFFC107);
const String baseUrl = "https://khalil-medicare-app-backend.onrender.com/api"; 
bool isBoxMode = true; 
List<Map<String, dynamic>> cartItems = [];
ValueNotifier<int> cartUpdateNotifier = ValueNotifier<int>(0);

// গ্লোবাল ফাংশন কার্টে যোগ করার জন্য
void globalAddToCart(dynamic med, BuildContext context) {
  int stock = int.tryParse(med['stock_quantity'].toString()) ?? 0;
  if (stock < 1) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("sorry it has no stock"), backgroundColor: Colors.red));
    return;
  }
  
  double boxP = double.tryParse(med['price'].toString()) ?? 0;
  int stripsPerBox = int.tryParse(med['strips_per_box'].toString()) ?? 1;
  double disc = isBoxMode ? (double.tryParse(med['box_discount'].toString()) ?? 0) : (double.tryParse(med['strip_discount'].toString()) ?? 0);
  
  double unitP = isBoxMode ? boxP : (boxP / (stripsPerBox > 0 ? stripsPerBox : 1));
  double finalP = unitP - (unitP * disc / 100);

  int idx = cartItems.indexWhere((it) => it['name'] == med['name'] && it['unit'] == (isBoxMode ? "Box" : "Strip"));
  if (idx != -1) { 
    cartItems[idx]['quantity']++; 
  } else { 
    cartItems.add({
      'name': med['name'],
      'unit': isBoxMode ? "Box" : "Strip",
      'final_price': finalP,
      'original_price': unitP,
      'quantity': 1,
      'discount': disc
    }); 
  }
  cartUpdateNotifier.value++;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${med['name']} কার্টে যোগ করা হয়েছে"), duration: const Duration(seconds: 1)));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');
  
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(primaryColor: logoRed, useMaterial3: true),
    home: token == null ? AuthScreen() : const MainNavigationScreen(),
    routes: {
      '/home': (context) => const MainNavigationScreen(),
      '/login': (context) => AuthScreen(),
    },
  ));
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  bool isAdmin = false; 

  @override
  void initState() {
    super.initState();
    _checkAdminStatus(); 
  }

  Future<void> _checkAdminStatus() async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token == null) return;
    
    final res = await http.get(Uri.parse("$baseUrl/profile/"), headers: {'Authorization': 'Token $token'});
    
    if (res.statusCode == 200) {
      final userData = json.decode(res.body);
      print("Current User: ${userData['username']}"); // এটি ল্যাপটপের কনসোলে চেক করুন
      
      setState(() { 
  isAdmin = (userData['username'].toString().toLowerCase() == 'kha_lil_medi_care' || 
             userData['is_superuser'] == true); 
});
    }
  } catch (e) { print("Error checking admin: $e"); }
}

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      const MedicineListScreen(),       
      const CompanyDedicatedScreen(),  
      const MyOrdersScreen(),           
      const CartScreen(), 
    ];
    if (isAdmin) pages.add(const AdminDashboard());

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: logoRed,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          const BottomNavigationBarItem(icon: Icon(Icons.business_center), label: "Company"),
          const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "Orders"),
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<int>(
              valueListenable: cartUpdateNotifier,
              builder: (context, value, child) => Badge(
                label: Text(cartItems.length.toString()),
                isLabelVisible: cartItems.isNotEmpty,
                child: const Icon(Icons.shopping_bag),
              ),
            ), 
            label: "Cart"
          ),
          if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: "Admin"),
        ],
      ),
    );
  }
}

class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({super.key});
  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  String searchQuery = ""; 
  List medicines = []; 
  List filtered = []; 
  bool isLoading = true;
  final PageController _sliderController = PageController();
  int _activePage = 0;
  Timer? _timer;

  @override
  void initState() { 
    super.initState(); 
    fetchInitialData();
    _timer = Timer.periodic(const Duration(seconds: 4), (t) {
      if(_sliderController.hasClients && medicines.isNotEmpty){
        _activePage = (_activePage < 5) ? _activePage + 1 : 0;
        _sliderController.animateToPage(_activePage, duration: const Duration(milliseconds: 800), curve: Curves.easeInOutQuart);
      }
    });
  }

  @override void dispose() { _timer?.cancel(); _sliderController.dispose(); super.dispose(); }

  Future fetchInitialData() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$baseUrl/medicines/"));
      if (res.statusCode == 200) {
        setState(() { medicines = json.decode(res.body); filtered = medicines; isLoading = false; });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _makeCall() async {
    const phone = "tel:+01700920629"; 
    if (await canLaunchUrl(Uri.parse(phone))) await launchUrl(Uri.parse(phone));
  }

  @override
  Widget build(BuildContext context) {
    final sliderItems = medicines.where((m) => (double.tryParse(m['box_discount'].toString()) ?? 0) > 0).take(6).toList();
    
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white, 
        elevation: 0, 
        toolbarHeight: 50, // হাইট কমানো হয়েছে
        centerTitle: false,
        title: const Text("Khalil Medicare", style: TextStyle(fontWeight: FontWeight.w900, color: logoRed, fontSize: 20)),
        actions: [
          // কল আইকন যুক্ত করা হয়েছে
          IconButton(
            onPressed: _makeCall, 
            icon: const Icon(Icons.call, color: Colors.green, size: 24)
          ),
          // প্রোফাইল আইকন
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ProfileScreen())), 
            icon: const Icon(Icons.account_circle_rounded, color: logoRed, size: 32)
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Column(
        children: [
          // সার্চবার - একদম উপরে
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), 
            color: Colors.white,
            child: Row(
              children: [
                Expanded(child: Container(
                  height: 42, 
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                  child: TextField(
                    onChanged: (v) => setState(() { searchQuery = v; filtered = medicines.where((m) => m['name'].toLowerCase().contains(v.toLowerCase())).toList(); }),
                    decoration: const InputDecoration(hintText: "Search what ever you want...", prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                  ),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => isBoxMode = !isBoxMode),
                  child: Container(
                    height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: isBoxMode ? logoRed : logoYellow, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(isBoxMode ? "BOX" : "STRIP", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  ),
                )
              ],
            ),
          ),

          // --- স্লাইডার (উচ্চতা ১১৫) ---
          if (searchQuery.isEmpty && sliderItems.isNotEmpty)
            SizedBox(
              height: 115, 
              child: PageView.builder(
                controller: _sliderController,
                itemCount: sliderItems.length,
                itemBuilder: (context, i) => _buildSplitSlider(sliderItems[i]),
              ),
            ),

          // --- মেডিসিন গ্রিড ---
          Expanded(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator(color: logoRed)) 
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, 
                    childAspectRatio: 0.75, 
                    crossAxisSpacing: 10, 
                    mainAxisSpacing: 10
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _buildProCard(filtered[i]),
                ),
          )
        ],
      ),
    );
  }

  // --- স্লাইডার ডিজাইন (বাম পাশে ইমেজ, ডান পাশে টেক্সট) ---
 Widget _buildSplitSlider(dynamic med) {
  double boxP = double.tryParse(med['price']?.toString() ?? '0') ?? 0;
  double disc = isBoxMode
      ? (double.tryParse(med['box_discount']?.toString() ?? '0') ?? 0)
      : (double.tryParse(med['strip_discount']?.toString() ?? '0') ?? 0);

  double unitP = isBoxMode
      ? boxP
      : (boxP /
          (int.tryParse(med['strips_per_box']?.toString() ?? '1') ?? 1));

  double finalP = unitP - (unitP * disc / 100);

  return GestureDetector(
    onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MedicineDetailScreen(medicine: med), 
    ),
  );
},
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          colors: [logoRed, Color(0xFF900000)],
        ),
      ),
      child: Row(
        children: [
          // বাম পাশে ইমেজ
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.network(med['image'] ?? ''),
                ),
              ),
            ),
          ),

          // ডান পাশে টেক্সট
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (disc > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${disc.toStringAsFixed(0)}% OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    med['name'] ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  FittedBox(
                    child: Row(
                      children: [
                        Text(
                          "৳${finalP.toStringAsFixed(1)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        if (disc > 0)
                          Text(
                            "৳${unitP.toStringAsFixed(0)}",
                            style: const TextStyle(
                              color: Color.fromARGB(221, 242, 241, 245),
                              decoration: TextDecoration.lineThrough,
                              fontSize: 18,
                              fontWeight: FontWeight.w900
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
  // --- গ্রিড প্রোডাক্ট কার্ড (কাটা দাম স্পষ্ট) ---
  Widget _buildProCard(dynamic med) {
    int stock = int.tryParse(med['stock_quantity'].toString()) ?? 0;
    double boxP = double.tryParse(med['price'].toString()) ?? 0;
    double disc = isBoxMode ? (double.tryParse(med['box_discount'].toString()) ?? 0) : (double.tryParse(med['strip_discount'].toString()) ?? 0);
    double unitP = isBoxMode ? boxP : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
    double finalP = unitP - (unitP * disc / 100);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: const Color.fromARGB(255, 37, 2, 77).withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(child: Image.network(med['image'] ?? '', fit: BoxFit.contain)),
                ),
                if (disc > 0)
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: logoRed, borderRadius: BorderRadius.circular(6)), child: Text("${disc.toStringAsFixed(0)}% OFF", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text("৳${finalP.toStringAsFixed(1)}", style: const TextStyle(color: logoRed, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(width: 4),
                    if (disc > 0)
                      Text(
                        "৳${unitP.toStringAsFixed(0)}", 
                        style: const TextStyle(color: Color.fromARGB(255, 88, 9, 235), decoration: TextDecoration.lineThrough, decorationColor: Color.fromARGB(255, 238, 14, 89), decorationThickness: 1.5, fontSize: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity, height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: stock > 0 ? logoRed : const Color.fromARGB(255, 224, 224, 224),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero
                    ),
                    onPressed: stock > 0 ? () => globalAddToCart(med, context) : null,
                    child: Text(stock > 0 ? "ADD" : "OUT", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- আপডেটেড মেডিসিন ডিটেইল স্ক্রিন ---
class MedicineDetailScreen extends StatefulWidget {
  final dynamic medicine;
  const MedicineDetailScreen({super.key, required this.medicine});
  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  @override
  Widget build(BuildContext context) {
    // এখানে ?? ব্যবহার করে নাল চেক করা হয়েছে
    var med = widget.medicine ?? {}; 
    String name = med['name']?.toString() ?? "ওষুধের নাম পাওয়া যায়নি";
    String image = med['image']?.toString() ?? "";
    String category = med['category_name']?.toString() ?? "General";
    String description = med['description']?.toString() ?? "এই ওষুধটি সম্পর্কে বিস্তারিত তথ্য নেই।";

    double boxP = double.tryParse(med['price']?.toString() ?? '0') ?? 0;
    double disc = isBoxMode 
        ? (double.tryParse(med['box_discount']?.toString() ?? '0') ?? 0) 
        : (double.tryParse(med['strip_discount']?.toString() ?? '0') ?? 0);
    int stripsPerBox = int.tryParse(med['strips_per_box']?.toString() ?? '1') ?? 1;
    
    double unitP = isBoxMode ? boxP : (boxP / (stripsPerBox > 0 ? stripsPerBox : 1));
    double finalP = unitP - (unitP * disc / 100);
    int stock = int.tryParse(med['stock_quantity']?.toString() ?? '0') ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(name), backgroundColor: logoRed, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 250, width: double.infinity, color: Colors.white,
              child: image.isNotEmpty 
                ? Image.network(image, fit: BoxFit.contain, errorBuilder: (c,e,s) => Icon(Icons.image_not_supported, size: 100, color: Colors.grey))
                : Icon(Icons.image_not_supported, size: 100, color: Colors.grey),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("Category: $category", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Text("৳${finalP.toStringAsFixed(1)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: logoRed)),
                    const SizedBox(width: 10),
                    if(disc > 0) Text("৳${unitP.toStringAsFixed(0)}", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 18)),
                  ]),
                  const SizedBox(height: 20),
                  const Text("Description:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(description, style: const TextStyle(fontSize: 15, color: Colors.black87)),
                  const SizedBox(height: 30),
                  Text(stock > 0 ? "stock has: $stock" : "stock out", style: TextStyle(color: stock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: stock > 0 ? logoRed : Colors.grey, minimumSize: const Size(double.infinity, 55)),
          onPressed: stock > 0 ? () => globalAddToCart(med, context) : null,
          child: const Text("ADD TO CART", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final addrController = TextEditingController();
  String selectedPayment = "Cash on Delivery";
  bool isPlacingOrder = false;

  // সর্বমোট দাম বের করার ফাংশন
  double getSubtotal() {
    double total = 0;
    for (var item in cartItems) {
      total += (item['final_price'] * item['quantity']);
    }
    return total;
  }

  // --- অর্ডার প্লেস করার মেইন ফাংশন ---
 Future<void> handlePlaceOrder() async {
  double total = getSubtotal();

  if (total < 1000) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("কমপক্ষে ১০০০ টাকার অর্ডার করতে হবে। আরও ${(1000 - total).toStringAsFixed(0)} টাকার পণ্য যোগ করুন।"))
    );
    return;
  }

  if (addrController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ঠিকানা লিখুন")));
    return;
  }

  setState(() => isPlacingOrder = true);

  try {
    SharedPreferences p = await SharedPreferences.getInstance();
    String? token = p.getString('token');

    // ব্যাকএন্ডের জন্য ডেটা ফরম্যাট তৈরি
    Map<String, dynamic> orderData = {
      "medicine_names": cartItems.map((m) => "${m['name']} (${m['unit']} x ${m['quantity']})").join(", "),
      "items": cartItems.map((e) {

  // ===== UNIT SAFE FIX =====
  String unitName = "Piece";

  if (e['unit'] != null &&
      e['unit'].toString().trim().isNotEmpty) {
    unitName = e['unit'].toString();
  } else if (e['unit_type'] != null &&
      e['unit_type'].toString().trim().isNotEmpty) {
    unitName = e['unit_type'].toString();
  } else if (e['selected_unit'] != null &&
      e['selected_unit'].toString().trim().isNotEmpty) {
    unitName = e['selected_unit'].toString();
  }

  return {
    "name": e['name'].toString(),
    "quantity": e['quantity'],
    "unit": unitName,
    "unit_type": unitName,
    "price": e['final_price'].toString(),
  };
}).toList(),
      "total_price": total.toStringAsFixed(2), // Double কে String এ কনভার্ট করে পাঠানো নিরাপদ
      "address": addrController.text.trim(),
      "payment_method": selectedPayment,
    };

    final res = await http.post(
      Uri.parse("$baseUrl/place-order/"),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(orderData),
    );

    // ডিবাগিং এর জন্য এগুলো প্রিন্ট করুন
    print("Response Status: ${res.statusCode}");
    print("Response Body: ${res.body}"); // এখানে সার্ভার বলবে কেন 400 এসেছে

    if (res.statusCode == 201 || res.statusCode == 200) {
      setState(() {
        cartItems.clear();
        cartUpdateNotifier.value++;
      });
      _showSuccessDialog();
    } else {
      // সার্ভার থেকে আসা সঠিক এরর মেসেজ দেখানো
      var errorData = json.decode(res.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${errorData.toString()}"), backgroundColor: Colors.red),
      );
    }
  } catch (e) {
    print("Error placing order: $e");
  } finally {
    if (mounted) setState(() => isPlacingOrder = false);
  }
}

  // --- সাকসেস ডায়ালগ ডিজাইন ---
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 60),
              ),
              const SizedBox(height: 20),
              const Text("thanks a lot!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 10),
              const Text("Your order submitted successfull", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ok"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("Shopping Cart"), backgroundColor: logoRed, foregroundColor: Colors.white, elevation: 0),
      body: ValueListenableBuilder<int>(
        valueListenable: cartUpdateNotifier,
        builder: (context, value, child) {
          if (cartItems.isEmpty) return const Center(child: Text("Empty your cart!"));
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: cartItems.length,
                  itemBuilder: (context, i) => _buildCartCard(i),
                ),
              ),
              _buildCheckoutSection(),
            ],
          );
        },
      ),
    );
  }

  // --- কার্ট আইটেম ডিজাইন ---
  Widget _buildCartCard(int i) {
    var item = cartItems[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: Row(
        children: [
          Container(height: 60, width: 60, decoration: BoxDecoration(color: logoRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.medication, color: logoRed)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("৳${item['final_price']} / ${item['unit']}", style: const TextStyle(color: logoRed, fontWeight: FontWeight.bold)),
            ]),
          ),
          Row(children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() { if (item['quantity'] > 1) item['quantity']--; else cartItems.removeAt(i); cartUpdateNotifier.value++; })),
            Text("${item['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.add_circle, color: logoRed), onPressed: () => setState(() { item['quantity']++; cartUpdateNotifier.value++; })),
          ]),
        ],
      ),
    );
  }

  // --- চেকআউট সেকশন ডিজাইন ---
  Widget _buildCheckoutSection() {
    double total = getSubtotal();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: addrController, decoration: const InputDecoration(hintText: "ডেলিভারি ঠিকানা", prefixIcon: Icon(Icons.location_on, color: logoRed))),
          const SizedBox(height: 15),
          // পেমেন্ট অপশনস
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ["Cash on Delivery", "bKash", "Nagad"].map((p) => ChoiceChip(
              label: Text(p),
              selected: selectedPayment == p,
              onSelected: (v) => setState(() => selectedPayment = p),
              selectedColor: logoRed,
              labelStyle: TextStyle(color: selectedPayment == p ? Colors.white : Colors.black),
            )).toList(),
          ),
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Total Bill:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("৳${total.toStringAsFixed(1)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: logoRed)),
          ]),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: total >= 1000 ? logoRed : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: isPlacingOrder ? null : handlePlaceOrder,
              child: isPlacingOrder ? const CircularProgressIndicator(color: Colors.white) : const Text("PLACE ORDER", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map? user;
  bool isLoading = true;
  bool isEditing = false;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addrController = TextEditingController();

  @override
  void initState() {
    super.initState();
    getProfileData();
  }

  Future getProfileData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final res = await http.get(
        Uri.parse("$baseUrl/profile/"),
        headers: {'Authorization': 'Token $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          user = json.decode(res.body);
          nameController.text = user?['username']?.toString() ?? "";
          emailController.text = user?['email']?.toString() ?? "";
          phoneController.text = user?['phone']?.toString() ?? "";
          addrController.text = user?['address']?.toString() ?? "";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future updateProfile() async {
    setState(() => isLoading = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      
      final res = await http.put(
        Uri.parse("$baseUrl/profile/"),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "username": nameController.text,
          "email": emailController.text,
          "phone": phoneController.text,
          "address": addrController.text,
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated!")));
        setState(() => isEditing = false);
        getProfileData();
      }
    } catch (e) {
      print("Update Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String username = nameController.text.isEmpty ? "User" : nameController.text;
    
    // ইমেজ ইউআরএল চেক করা
    String? profileImageUrl = user?['image']; 

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: logoRed,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: logoRed))
          : SingleChildScrollView(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 100,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: logoRed,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                        ),
                      ),
                      Positioned(
                        top: 30,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: CircleAvatar(
                            radius: 55,
                            backgroundColor: logoYellow,
                            // এখানে ইমেজ চেক করা হচ্ছে
                            backgroundImage: (profileImageUrl != null && profileImageUrl.isNotEmpty)
                                ? NetworkImage(profileImageUrl)
                                : null,
                            child: (profileImageUrl == null || profileImageUrl.isEmpty)
                                ? Text(
                                    username.isNotEmpty ? username[0].toUpperCase() : "U",
                                    style: const TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: logoRed),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 65),
                  
                  Text(
                    username.toUpperCase(),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Text("Verified Customer", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13)),
                  
                  const SizedBox(height: 25),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _buildInfoTile(Icons.person_outline, "Full Name", nameController, isEditing),
                        _buildInfoTile(Icons.email_outlined, "Email Address", emailController, isEditing),
                        _buildInfoTile(Icons.phone_android_outlined, "Phone Number", phoneController, isEditing),
                        _buildInfoTile(Icons.location_on_outlined, "Default Address", addrController, isEditing),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isEditing ? Colors.green : Colors.white,
                              foregroundColor: isEditing ? Colors.white : logoRed,
                              side: BorderSide(color: isEditing ? Colors.green : logoRed, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: () {
                              if (isEditing) updateProfile();
                              else setState(() => isEditing = true);
                            },
                            icon: Icon(isEditing ? Icons.check_circle : Icons.edit_note),
                            label: Text(isEditing ? "SAVE CHANGES" : "EDIT PROFILE", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 15),
                        if(!isEditing) SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: logoRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: () async {
                              SharedPreferences p = await SharedPreferences.getInstance();
                              await p.remove('token');
                              if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text("LOGOUT ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, TextEditingController controller, bool editing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: logoRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: logoRed, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                editing 
                ? TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  )
                : Text(controller.text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompanyDedicatedScreen extends StatefulWidget {
  const CompanyDedicatedScreen({super.key});
  @override
  State<CompanyDedicatedScreen> createState() => _CompanyDedicatedScreenState();
}

class _CompanyDedicatedScreenState extends State<CompanyDedicatedScreen> {
  List categories = [];
  List filteredCategories = [];
  bool isLoading = true;
  String searchCat = "";

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  Future<void> fetchCategories() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/categories/"));
      if (res.statusCode == 200) {
        setState(() {
          categories = json.decode(res.body);
          filteredCategories = categories;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      print("Category Error: $e");
    }
  }

  void _filterCategories(String query) {
    setState(() {
      searchCat = query;
      filteredCategories = categories
          .where((c) => c['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("All Companies", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- সার্চ বার ---
          // --- সার্চ বার (সংশোধিত) ---
          Padding(
            padding: const EdgeInsets.all(15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                onChanged: _filterCategories,
                decoration: InputDecoration(
                  hintText: "Search company or category...",
                  prefixIcon: const Icon(Icons.search, color: logoRed),
                  border: InputBorder.none, // এখানে বর্ডার হিল করে দেওয়া হয়েছে কারণ কন্টেইনারে বর্ডার আছে
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                ),
              ),
            ),
          ),

          // --- ক্যাটাগরি গ্রিড ---
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: logoRed))
                : filteredCategories.isEmpty
                    ? const Center(child: Text("No Category Found!"))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                        ),
                        itemCount: filteredCategories.length,
                        itemBuilder: (context, i) => _buildCategoryCard(filteredCategories[i]),
                      ),
          ),
        ],
      ),
    );
  }

  // --- প্রফেশনাল ক্যাটাগরি কার্ড ---
  Widget _buildCategoryCard(dynamic cat) {
    return GestureDetector(
      onTap: () {
        // এখানে ক্লিক করলে ঐ ক্যাটাগরির প্রোডাক্ট দেখাবে
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => CategoryProductsScreen(
              categoryId: cat['id'],
              categoryName: cat['name'],
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: logoRed.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business_rounded, color: logoRed, size: 35),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                cat['name']?.toString() ?? "Unknown",
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- ক্যাটাগরি অনুযায়ী প্রোডাক্ট দেখানোর স্ক্রিন ---
class CategoryProductsScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  const CategoryProductsScreen({super.key, required this.categoryId, required this.categoryName});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  List products = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetch();
  }

  fetch() async {
    final res = await http.get(Uri.parse("$baseUrl/medicines/?category=${widget.categoryId}"));
    if (res.statusCode == 200) {
      setState(() {
        products = json.decode(res.body);
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName), backgroundColor: logoRed, foregroundColor: Colors.white),
      body: loading 
        ? const Center(child: CircularProgressIndicator()) 
        : products.isEmpty 
          ? const Center(child: Text("No medicines found in this company"))
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, i) => ListTile(
                leading: Image.network(products[i]['image'] ?? '', width: 50, errorBuilder: (c,e,s)=>const Icon(Icons.medication)),
                title: Text(products[i]['name']),
                subtitle: Text("৳${products[i]['price']}"),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => MedicineDetailScreen(medicine: products[i]))),
              ),
            ),
    );
  }
}

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});
  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      SharedPreferences p = await SharedPreferences.getInstance();
      String? token = p.getString('token');

      final res = await http.get(
        Uri.parse("$baseUrl/my-orders/"),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      // এটি ল্যাপটপের কনসোলে দেখবেন যখন অর্ডার পেজটি খুলবেন
      print("GET ORDERS STATUS: ${res.statusCode}");
      print("GET ORDERS DATA: ${res.body}");

      if (res.statusCode == 200) {
        final dynamic decoded = json.decode(res.body);
        setState(() {
          if (decoded is List) {
            orders = decoded;
          } else if (decoded is Map && decoded.containsKey('orders')) {
            orders = decoded['orders'];
          } else if (decoded is Map && decoded.containsKey('results')) {
            orders = decoded['results'];
          } else {
            orders = [];
          }
          // নতুন অর্ডার গুলো সবার উপরে দেখানোর জন্য
          orders = orders.reversed.toList();
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Error fetching orders: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Order history", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: logoRed,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [IconButton(onPressed: fetchOrders, icon: const Icon(Icons.refresh))],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: logoRed))
          : orders.isEmpty
              ? _buildEmptyUI()
              : RefreshIndicator(
                  onRefresh: fetchOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: orders.length,
                    itemBuilder: (context, i) => _buildOrderCard(orders[i]),
                  ),
                ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    // আপনার ব্যাকএন্ড অনুযায়ী medicine_names ফিল্ড ব্যবহার করা হয়েছে
    String medicines = order['medicine_names']?.toString() ?? "ওষুধের নাম পাওয়া যায়নি";
    String price = order['total_price']?.toString() ?? "0.0";
    String status = order['status']?.toString() ?? "Pending";
    String id = order['id']?.toString() ?? "0";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OrderDetailScreen(order: order))),
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          backgroundColor: logoRed.withOpacity(0.1),
          child: const Icon(Icons.receipt_long, color: logoRed),
        ),
        title: Text("অর্ডার আইডি: #$id", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(medicines, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Text("৳$price", style: const TextStyle(color: logoRed, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: status.toLowerCase() == 'delivered' ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: status.toLowerCase() == 'delivered' ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("You have no order history", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}

// --- নতুন এবং উন্নত অর্ডার ডিটেইল স্ক্রিন ---
class OrderDetailScreen extends StatelessWidget {
  final dynamic order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    // ডাটা সেটআপ
    String orderId = order['id']?.toString() ?? "00";
    String status = order['status']?.toString() ?? "Pending";
    String totalPrice = order['total_price']?.toString() ?? "0";
    String address = order['address']?.toString() ?? "ঠিকানা পাওয়া যায়নি";
    String itemsText = order['medicine_names']?.toString() ?? "";
    List<String> itemsList = itemsText.split(', ');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Digital Invoice", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ১. টপ সেকশন (ব্র্যান্ডিং)
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 60),
                  const SizedBox(height: 10),
                  Text("ORDER #$orderId", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Status: $status", style: TextStyle(color: status.toLowerCase() == 'delivered' ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            const Divider(thickness: 1, indent: 20, endIndent: 20),

            // ২. কাস্টমার ডিটেইলস কার্ড
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Delivery Address:", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(address, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),

            // ৩. প্রফেশনাল বিলিং টেবিল
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // টেবিল হেডার
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Color(0xFFE9ECEF), borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
                    child: const Row(
                      children: [
                        Expanded(flex: 4, child: Text("Item", style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text("Qty", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  // আইটেম লিস্ট
                  ...itemsList.map((item) {
                    // Napa (Box x 2) -> আলাদা করা
                    String name = item.split(' (')[0];
                    String qty = item.contains('(') ? item.split('(')[1].split(')')[0] : "1";
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(flex: 4, child: Text(name, style: const TextStyle(fontSize: 13))),
                          Expanded(flex: 2, child: Text(qty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.blueGrey))),
                          const Expanded(flex: 2, child: Text("-", textAlign: TextAlign.right)),
                        ],
                      ),
                    );
                  }).toList(),
                  
                  const Divider(height: 1),

                  // সাবটোটাল সেকশন
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Total Payable Amount", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text("৳$totalPrice", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: logoRed)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // ৪. ফুটার মেসেজ
            const Icon(Icons.qr_code_2, size: 80, color: Colors.black54),
            const SizedBox(height: 10),
            const Text("Thank you for choosing Khalil Medicare", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            const SizedBox(height: 40),
          ],
        ),
      ),
      // ৫. হেল্পলাইন বাটন
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: logoRed, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(double.infinity, 50)),
          onPressed: () => launchUrl(Uri.parse("tel:+01700920629")),
          child: const Text("Need Help? Contact Us", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // এই ডাটাগুলো চাইলে API থেকে আনা যায়, আপাতত স্ট্যাটিক রাখা হয়েছে
  int totalOrders = 0;
  double totalRevenue = 0.0;
  int pendingOrders = 0;

  @override
  void initState() {
    super.initState();
    // এখানে চাইলে আপনি অ্যাডমিন সামারি লোড করার ফাংশন কল করতে পারেন
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text("Admin Command Center", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ১. অ্যাডমিন হেডার (Welcome Banner)
            _buildAdminHeader(),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ২. কুইক স্ট্যাটাস গ্রিড (Stats Cards)
                  const Text("Business Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      _buildStatCard("Total Sales", "৳$totalRevenue", Icons.payments, Colors.green),
                      const SizedBox(width: 15),
                      _buildStatCard("Pending", "$pendingOrders", Icons.pending_actions, Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ৩. মেইন ম্যানেজমেন্ট মেনু (Management Cards)
                  const Text("Management Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  
                  _buildLargeMenuCard(
                    title: "Order Management",
                    subtitle: "Check new orders and update status",
                    icon: Icons.shopping_cart_checkout,
                    color: Colors.blue[800]!,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminOrdersScreen())),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  _buildLargeMenuCard(
                    title: "Medicine Inventory",
                    subtitle: "Add new medicine or update stock",
                    icon: Icons.inventory_2,
                    color: Colors.teal[700]!,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminMedicineScreen())),
                  ),
                  
                  const SizedBox(height: 15),
                  
                  _buildLargeMenuCard(
                    title: "User Control",
                    subtitle: "Manage customers and their profiles",
                    icon: Icons.people_alt,
                    color: Colors.purple[700]!,
                    onTap: () {
                      // ইউজারের জন্য আলাদা স্ক্রিন এখানে দিতে পারেন
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- অ্যাডমিন হেডার ডিজাইন ---
  Widget _buildAdminHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 25),
      decoration: BoxDecoration(
        color: Colors.indigo[900],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Hello, Khalil Admin", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text("Manage your Medicare system efficiently.", style: TextStyle(color: Colors.indigo[100], fontSize: 14)),
        ],
      ),
    );
  }

  // --- ছোট স্ট্যাটাস কার্ড ডিজাইন ---
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 15),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // --- বড় মেনু কার্ড ডিজাইন ---
  Widget _buildLargeMenuCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: color, size: 35),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}