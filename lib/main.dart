import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io'; // ফাইল হ্যান্ডেল করার জন্য
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_screen.dart'; // আপনার অথ স্ক্রিন ফাইল
import '../services/invoice_service.dart'; // আপনার ইনভয়েস সার্ভিস
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/admin_medicine_screen.dart';

// --- গ্লোবাল ভেরিয়েবল ---
const Color logoRed = Color(0xFFD00000);
const Color logoYellow = Color(0xFFFFC107);
const String baseUrl = "https://khalil-medicare-app-backend.onrender.com/api"; 
bool isBoxMode = true; 
List<Map<String, dynamic>> cartItems = [];
ValueNotifier<int> cartUpdateNotifier = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');
  
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(primaryColor: logoRed),
    
    // যদি auth_screen.dart এ ক্লাসের নাম AuthScreen হয়, তবে নিচেরটা দিন:
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
  final List<Widget> _pages = [
    const MedicineListScreen(),       
    const CompanyDedicatedScreen(),  
    const MyOrdersScreen(),           
    const CartScreen(), 
    const AdminDashboard(),             
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          const BottomNavigationBarItem(icon: Icon(Icons.business_center), label: "Company"),
          const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "Orders"),
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<int>(
              valueListenable: cartUpdateNotifier,
              builder: (context, value, child) {
                return Badge(
                  label: Text(cartItems.length.toString()),
                  isLabelVisible: cartItems.isNotEmpty,
                  child: const Icon(Icons.shopping_bag),
                );
              },
            ), 
            label: "Cart"
          ),
          const BottomNavigationBarItem(
           icon: Icon(Icons.admin_panel_settings),
           label: "Admin",
         ),
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
  List categories = []; 
  List filtered = []; 
  bool isLoading = true;
  final PageController _sliderController = PageController();
  int _activePage = 0;
  Timer? _timer;

  @override
  void initState() { 
    super.initState(); 
    fetchInitialData();
    // স্লাইডার অটো-প্লে টাইমার
    _timer = Timer.periodic(const Duration(seconds: 4), (t) {
      final sliderItems = getSliderItems();
      if(_sliderController.hasClients && sliderItems.isNotEmpty){
        _activePage = (_activePage < sliderItems.length - 1) ? _activePage + 1 : 0;
        _sliderController.animateToPage(_activePage, duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      }
    });
  }

  @override void dispose() { _timer?.cancel(); _sliderController.dispose(); super.dispose(); }

  Future fetchInitialData() async {
    await fetchCategories();
    await fetchMedicines();
  }

  // --- ক্যাটাগরি ফেচ করা ---
  Future fetchCategories() async {
    final res = await http.get(Uri.parse("$baseUrl/categories/"));
    if (res.statusCode == 200) setState(() => categories = json.decode(res.body));
  }

  // --- মেডিসিন ফেচ এবং ব্র্যান্ড সর্টিং (Brand > Surgical > Non-brand) ---
  Future fetchMedicines({int? catId}) async {
    if (!mounted) return;
    setState(() => isLoading = true);
    String url = (catId == null) ? "$baseUrl/medicines/" : "$baseUrl/medicines/?category=$catId";
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      List allMeds = json.decode(res.body);
      
      // সর্টিং লজিক
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

      setState(() { medicines = allMeds; filtered = medicines; isLoading = false; });
    }
  }

  // --- স্লাইডার আইটেম ফিল্টার ---
  List getSliderItems() {
    if (medicines.isEmpty) return [];
    // প্রতিটি ক্যাটাগরি থেকে সেরা ডিসকাউন্টের ওষুধ নেওয়া
    return medicines.where((m) => 
      (double.tryParse(m['box_discount'].toString()) ?? 0) > 0 || 
      (double.tryParse(m['strip_discount'].toString()) ?? 0) > 0
    ).take(6).toList();
  }

  // --- কল করার ফাংশন ---
  void _makeCall() async {
    const phone = "tel:+8801700000000"; // আপনার নাম্বার দিন
    if (await canLaunchUrl(Uri.parse(phone))) await launchUrl(Uri.parse(phone));
  }

  // --- ক্যামেরা দিয়ে প্রেসক্রিপশন আপলোড ---
  Future<void> _uploadPrescription() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploading Prescription...")));
      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? token = prefs.getString('token');
        var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/upload-prescription/"));
        request.headers['Authorization'] = 'Token $token';
        request.files.add(await http.MultipartFile.fromPath('prescription', image.path));
        var response = await request.send();
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prescription Uploaded!"), backgroundColor: Colors.green));
        }
      } catch (e) { print(e); }
    }
  }

  // --- কার্টে যোগ করার ফাংশন ---
  void addToCart(dynamic med) {
    int stock = int.tryParse(med['stock_quantity'].toString()) ?? 0;
    if (stock < 1) return;

    double boxP = double.tryParse(med['price'].toString()) ?? 0;
    double disc = isBoxMode ? (double.tryParse(med['box_discount'].toString()) ?? 0) : (double.tryParse(med['strip_discount'].toString()) ?? 0);
    double unitP = isBoxMode ? boxP : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
    double finalP = unitP - (unitP * disc / 100);

    setState(() {
      int idx = cartItems.indexWhere((it) => it['name'] == med['name'] && it['unit'] == (isBoxMode ? "Box" : "Strip"));
      if (idx != -1) { cartItems[idx]['quantity']++; } 
      else { cartItems.add({'name': med['name'],'unit': isBoxMode ? "Box" : "Strip",'final_price': finalP,'original_price': unitP,'quantity': 1,'discount': disc}); }
      cartUpdateNotifier.value++;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${med['name']} added to cart"), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final sliderItems = getSliderItems();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white, 
        elevation: 0, 
        title: const Text("Khalil Medicare", style: TextStyle(fontWeight: FontWeight.bold, color: logoRed)),
        actions: [
          IconButton(onPressed: _makeCall, icon: const Icon(Icons.call, color: Colors.green, size: 26)),
          IconButton(onPressed: _uploadPrescription, icon: const Icon(Icons.camera_alt, color: Colors.indigo, size: 26)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ProfileScreen())), icon: const Icon(Icons.person_pin, color: logoRed, size: 30))
        ],
      ),
      body: Column(
        children: [
          // সার্চ বার
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(
                  onChanged: (v) => setState(() { searchQuery = v; filtered = medicines.where((m) => m['name'].toLowerCase().contains(v.toLowerCase())).toList(); }),
                  decoration: InputDecoration(hintText: "Search medicine...", prefixIcon: const Icon(Icons.search, color: logoRed), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => isBoxMode = !isBoxMode),
                  child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isBoxMode ? logoRed : logoYellow, borderRadius: BorderRadius.circular(15)), child: Text(isBoxMode ? "BOX" : "STRIP", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                )
              ],
            ),
          ),
          // স্লাইডার
          if (searchQuery.isEmpty && sliderItems.isNotEmpty)
            SizedBox(
              height: 180, 
              child: PageView.builder(
                controller: _sliderController, 
                itemCount: sliderItems.length, 
                itemBuilder: (context, i) => _buildMedicineSlide(sliderItems[i]),
              ),
            ),
          // মেডিসিন গ্রিড
          Expanded(
            child: isLoading ? const Center(child: CircularProgressIndicator(color: logoRed)) : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.55, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: filtered.length,
              itemBuilder: (context, i) => _buildMedicineCard(filtered[i]),
            ),
          )
        ],
      ),
    );
  }

  // --- স্লাইডার ডিজাইন (ডিজাইন ইনট্যাক্ট) ---
  Widget _buildMedicineSlide(dynamic med) {
    double boxP = double.tryParse(med['price'].toString()) ?? 0;
    double disc = isBoxMode ? (double.tryParse(med['box_discount'].toString()) ?? 0) : (double.tryParse(med['strip_discount'].toString()) ?? 0);
    double unitP = isBoxMode ? boxP : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
    double finalP = unitP - (unitP * disc / 100);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => MedicineDetailScreen(medicine: med))),
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [logoRed, Color(0xFF800000)]), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)]),
        child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(10), child: Image.network(med['image'] ?? '', fit: BoxFit.contain))),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1),
            if(disc > 0) Container(margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: logoYellow, borderRadius: BorderRadius.circular(5)), child: Text("${disc.toStringAsFixed(0)}% OFF", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
            Row(children: [
              Text("৳${finalP.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 5),
              if(disc > 0) Text("৳${unitP.toStringAsFixed(0)}", style: const TextStyle(color: Color.fromARGB(179, 249, 248, 250), decoration: TextDecoration.lineThrough, fontSize: 18)),
            ]),
            const Text("Tap to view", style: TextStyle(color: Colors.yellow, fontSize: 10))
          ])),
        ]),
      ),
    );
  }

  // --- মেডিসিন কার্ড ডিজাইন (প্রো-লেভেল গ্রেডিয়েন্ট বাটনসহ) ---
  Widget _buildMedicineCard(dynamic med) {
    int stock = int.tryParse(med['stock_quantity'].toString()) ?? 0;
    bool isOutOfStock = stock < 1;
    double boxP = double.tryParse(med['price'].toString()) ?? 0;
    double disc = isBoxMode ? (double.tryParse(med['box_discount'].toString()) ?? 0) : (double.tryParse(med['strip_discount'].toString()) ?? 0);
    double unitP = isBoxMode ? boxP : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
    double finalP = unitP - (unitP * disc / 100);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Stack(alignment: Alignment.center, children: [
          Container(width: double.infinity, decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), gradient: LinearGradient(colors: [Colors.red.shade50, Colors.orange.shade50])), child: Padding(padding: const EdgeInsets.all(15), child: Image.network(med['image'] ?? '', fit: BoxFit.contain))),
          if (isOutOfStock) Container(width: double.infinity, height: double.infinity, color: Colors.black.withOpacity(0.2), child: Center(child: Container(padding: const EdgeInsets.all(5), color: Colors.red, child: const Text("OUT OF STOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
          if (disc > 0 && !isOutOfStock) Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.red.shade700, Colors.orange.shade600]), borderRadius: BorderRadius.circular(30)), child: Text("${disc.toStringAsFixed(0)}% OFF", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)))),
          Positioned(top: 10, right: 10, child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: isBoxMode ? Colors.red : Colors.orange, borderRadius: BorderRadius.circular(10)), child: Text(isBoxMode ? "BOX" : "STRIP", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
        ])),
        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            Text("৳${finalP.toStringAsFixed(1)}", style: TextStyle(color: isOutOfStock ? Colors.grey : Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 5),
            if (disc > 0) Text("৳${unitP.toStringAsFixed(0)}", style: const TextStyle(color: Color.fromARGB(255, 53, 4, 230), decoration: TextDecoration.lineThrough, fontSize: 18)),
          ]),
          const SizedBox(height: 10),
          // প্রো-লেভেল গ্রেডিয়েন্ট বাটন
          SizedBox(width: double.infinity, height: 40, child: ElevatedButton(
            style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: isOutOfStock ? null : () => addToCart(med),
            child: Ink(
              decoration: BoxDecoration(gradient: isOutOfStock ? null : LinearGradient(colors: [Colors.red.shade700, Colors.orange.shade600]), color: isOutOfStock ? Colors.grey : null, borderRadius: BorderRadius.circular(12)),
              child: Container(alignment: Alignment.center, child: Text(isOutOfStock ? "OUT OF STOCK" : "ADD TO CART", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
            ),
          )),
        ])),
      ]),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final addr = TextEditingController();
  String payMethod = "Cash on Delivery";
  bool isPlacingOrder = false;

  // লোগো কালার থিম (Design Intact)
  final Color logoRed = const Color(0xFFD00000);
  final Color logoYellow = const Color(0xFFFFC107);

  double getTotal() {
    double t = 0;
    for (var i in cartItems) {
      t += (i['final_price'] * i['quantity']);
    }
    return t;
  }

  Future<void> placeOrder() async {
    // ১. মিনিমাম অর্ডার চেক (আপনার কোড অনুযায়ী ৮০০ বা ১০০০)
    if (getTotal() < 800) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("কমপক্ষে ৮০০ টাকার অর্ডার প্রয়োজন"), backgroundColor: Colors.orange));
      return;
    }
    
    // ২. ঠিকানা চেক
    if (addr.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("অনুগ্রহ করে আপনার ঠিকানা লিখুন"), backgroundColor: Colors.red));
      return;
    }

    setState(() => isPlacingOrder = true);

    try {
      SharedPreferences p = await SharedPreferences.getInstance();
      String? t = p.getString('token');
      
      // অর্ডারের সব ওষুধের নাম ও ডিটেইলস
      String details = cartItems
          .map((m) => "${m['name']} (${m['unit']} x ${m['quantity']})")
          .join(", ");

      // ব্যাকএন্ডে পাঠানোর জন্য আইটেম লিস্ট তৈরি
      // টিপস: আপনার ব্যাকএন্ড যদি ID চায় তবে 'name' এর বদলে 'id' পাঠাতে হতে পারে
      List itemsList = cartItems.map((e) => {
        "name": e['name'], 
        "quantity": e['quantity'],
        "unit": e['unit'],
        "price": e['final_price']
      }).toList();

      final res = await http.post(
        Uri.parse("$baseUrl/place-order/"),
        headers: {
          'Authorization': 'Token $t',
          'Content-Type': 'application/json'
        },
        body: json.encode({
          "medicine_names": details,
          "total_price": getTotal().toStringAsFixed(2),
          "address": addr.text,
          "payment_method": payMethod,
          "transaction_id": "", 
          "items": itemsList, // সার্ভার এই লিস্ট থেকে স্টক কমাবে
        }),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        // ইনভয়েস জেনারেট করার লজিক (আপনার অরিজিনাল কোড)
        List<Map<String, dynamic>> invoiceData = cartItems
            .map((e) => {
                  "name": e['name'],
                  "qty": e['quantity'],
                  "price": e['original_price'],
                  "discount": e['discount'],
                })
            .toList();

        // প্রোফাইল ডাটা ফেচ করা (ইনভয়েসের জন্য)
        final profileRes = await http.get(
          Uri.parse("$baseUrl/profile/"),
          headers: {'Authorization': 'Token $t'},
        );

        String customerName = "Customer";
        String customerPhone = "N/A";
        if (profileRes.statusCode == 200) {
          final profileData = json.decode(profileRes.body);
          customerName = profileData['username']?.toString() ?? "Customer";
          customerPhone = profileData['phone']?.toString() ?? "N/A";
        }

        // PDF ইনভয়েস তৈরি
        await InvoiceService.generateInvoice(
          customerName: customerName,
          phone: customerPhone,
          items: invoiceData,
        );

        // কার্ট ক্লিয়ার করা
        setState(() {
          cartItems.clear();
          cartUpdateNotifier.value++;
        });
        
        _showSuccessDialog(); // সফল মেসেজ দেখানো
      } else {
        // যদি ফেইল হয়, তবে সার্ভার থেকে আসা এরর মেসেজটি দেখাবে
        final errorData = json.decode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['error'] ?? errorData['message'] ?? "স্টক আপডেট বা অর্ডার ফেইল হয়েছে"), 
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("সংযোগ বিচ্ছিন্ন বা সমস্যা: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isPlacingOrder = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text("অর্ডার সফল!",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const Text("আপনার ইনভয়েস (PDF) তৈরি হয়েছে।",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: logoRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(context),
                child: const Text("ঠিক আছে",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Shopping Cart",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: logoRed,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: cartUpdateNotifier,
        builder: (context, value, child) {
          if (cartItems.isEmpty) {
            return const Center(
                child: Text("আপনার ঝুড়ি বর্তমানে খালি",
                    style: TextStyle(color: Colors.grey)));
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: cartItems.length,
                  itemBuilder: (context, i) => _buildCartItem(i),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(25),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(35),
                      topRight: Radius.circular(35)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 15,
                        offset: Offset(0, -5))
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: addr,
                      decoration: InputDecoration(
                        labelText: "আপনার ঠিকানা দিন",
                        prefixIcon: Icon(Icons.location_on, color: logoRed),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: payMethod,
                      decoration: InputDecoration(
                        labelText: "পেমেন্ট মেথড",
                        prefixIcon: Icon(Icons.payment, color: logoRed),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      items: ["Cash on Delivery", "bKash"]
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => payMethod = v!),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("সর্বমোট বিল:",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("৳${getTotal().toStringAsFixed(1)}",
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: logoRed)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              getTotal() >= 1000 ? logoRed : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: isPlacingOrder ? null : placeOrder,
                        child: isPlacingOrder
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("অর্ডার সম্পন্ন করুন",
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (getTotal() < 1000)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                            "আর ৳${(1000 - getTotal()).toStringAsFixed(0)} টাকার মেডিসিন প্রয়োজন",
                            style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildCartItem(int i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)
          ]),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: logoRed.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.medication_rounded, color: logoRed, size: 30),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cartItems[i]['name'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1),
                Text(
                    "৳${cartItems[i]['final_price']} x ${cartItems[i]['quantity']}",
                    style: TextStyle(color: logoRed, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                        if (cartItems[i]['quantity'] > 1)
                          cartItems[i]['quantity']--;
                        else
                          cartItems.removeAt(i);
                        cartUpdateNotifier.value++;
                      })),
              Text("${cartItems[i]['quantity']}",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                  icon: Icon(Icons.add_circle, color: logoRed),
                  onPressed: () => setState(() {
                        cartItems[i]['quantity']++;
                        cartUpdateNotifier.value++;
                      })),
            ],
          ),
        ],
      ),
    );
  }
}
//---------------------------------------------------------------------
// ১. প্রোফাইল স্ক্রিন (ইমেজ এবং এডিট বাটন ১০০% ফিক্সড)
//---------------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map? user;
  bool isLoading = true;

  @override void initState() { super.initState(); getProfileData(); }

  Future getProfileData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final res = await http.get(
        Uri.parse("$baseUrl/profile/"), 
        headers: {'Authorization': 'Token $token'}
      );
      if (res.statusCode == 200) {
        setState(() { user = json.decode(res.body); isLoading = false; });
      }
    } catch (e) { setState(() => isLoading = false); }
  }

  // ইমেজের ইউআরএল ঠিক করার জন্য শক্তিশালী ফাংশন
  String getProfileImageUrl(String? path) {
    if (path == null || path.isEmpty || path == "null") return "";
    if (path.startsWith('http')) return path; // যদি পূর্ণ লিঙ্ক থাকে
    
    // স্লাশ চেক করে লিঙ্ক তৈরি
    String cleanPath = path.startsWith('/') ? path : '/$path';
    return "https://khalil-medicare-app-backend.onrender.com$cleanPath";
  }

  @override
  Widget build(BuildContext context) {
    String finalUrl = getProfileImageUrl(user?['image']);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("My Account"), backgroundColor: logoRed, foregroundColor: Colors.white, elevation: 0),
      body: isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        clipBehavior: Clip.none, 
        child: Column(children: [
          // লাল হেডার এবং ছবি
          Stack(
            clipBehavior: Clip.none, 
            alignment: Alignment.bottomCenter, 
            children: [
              Container(height: 120, width: double.infinity, color: logoRed), // আপনার লাল হেডার
              
              Positioned(
                bottom: -50, 
                child: Stack(
                  clipBehavior: Clip.none, 
                  children: [
                    // প্রোফাইল পিকচার
                    Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: CircleAvatar(
                        radius: 60, 
                        backgroundColor: Colors.grey[200], 
                        backgroundImage: finalUrl.isNotEmpty ? NetworkImage(finalUrl) : null,
                        child: finalUrl.isEmpty ? const Icon(Icons.person, size: 60, color: Colors.grey) : null,
                      ),
                    ),
                    // হলুদ এডিট বাটন
                    Positioned(
                      bottom: 0, right: 5, 
                      child: Material( // ক্লিকের জন্য ম্যাটেরিয়াল টাচ যোগ করা হয়েছে
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (context) => EditProfileScreen(user: user!))
                            ).then((value) => getProfileData());
                          },
                          child: const CircleAvatar(backgroundColor: logoYellow, radius: 20, child: Icon(Icons.edit, color: Colors.black, size: 18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 65),
          Text(user?['username']?.toString().toUpperCase() ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          
          // আপনার সেই ইনফো টাইলস
          _infoTile(Icons.email, "Email Address", user?['email']),
          _infoTile(Icons.phone_android, "Mobile Number", user?['phone']),
          _infoTile(Icons.location_on, "Shipping Address", user?['address']),
          
          const SizedBox(height: 30),
          TextButton(
            onPressed: () async {
              SharedPreferences p = await SharedPreferences.getInstance();
              await p.remove('token');
              Navigator.pushReplacementNamed(context, '/login');
            }, 
            child: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ]),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String? value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        CircleAvatar(backgroundColor: logoRed.withOpacity(0.1), child: Icon(icon, color: logoRed, size: 22)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(value ?? "Not Set", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
        ]))
      ]),
    );
  }
}

//---------------------------------------------------------------------
// ২. এডিট প্রোফাইল স্ক্রিন
//---------------------------------------------------------------------
class EditProfileScreen extends StatefulWidget {
  final Map user; 
  const EditProfileScreen({super.key, required this.user});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController email;
  late TextEditingController phone;
  late TextEditingController address;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    email = TextEditingController(text: widget.user['email']?.toString() ?? "");
    phone = TextEditingController(text: widget.user['phone']?.toString() ?? "");
    address = TextEditingController(text: widget.user['address']?.toString() ?? "");
  }

  Future<void> update() async {
    setState(() => isSaving = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final response = await http.put(
        Uri.parse("$baseUrl/profile/update/"),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: json.encode({"email": email.text, "phone": phone.text, "address": address.text}),
      );
      if (response.statusCode == 200) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated!")));
      }
    } catch (e) { print(e); } finally { setState(() => isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Information"), backgroundColor: logoRed, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(children: [
          TextField(controller: email, decoration: const InputDecoration(labelText: "Email Address")),
          TextField(controller: phone, decoration: const InputDecoration(labelText: "Phone Number")),
          TextField(controller: address, decoration: const InputDecoration(labelText: "Full Address")),
          const SizedBox(height: 35),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: logoRed, foregroundColor: Colors.white),
              onPressed: isSaving ? null : update,
              child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SAVE CHANGES"),
            ),
          )
        ]),
      ),
    );
  }
}

class CompanyProductsScreen extends StatefulWidget {
  final int companyId;
  final String companyName;
  const CompanyProductsScreen({super.key, required this.companyId, required this.companyName});

  @override
  State<CompanyProductsScreen> createState() => _CompanyProductsScreenState();
}

class _CompanyProductsScreenState extends State<CompanyProductsScreen> {
   List medicines = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchCompanyProducts();
  }

  Future<void> fetchCompanyProducts() async {
    setState(() => isLoading = true);
    // নির্দিষ্ট ক্যাটাগরি/কোম্পানির আইডি দিয়ে প্রোডাক্ট ফিল্টার করা হচ্ছে
    final res = await http.get(Uri.parse("$baseUrl/medicines/?category=${widget.companyId}"));
    if (res.statusCode == 200) {
      setState(() {
        medicines = json.decode(res.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.companyName), // কোম্পানির নাম দেখাবে
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : medicines.isEmpty
              ? const Center(child: Text("No medicine found for this company", style: TextStyle(fontSize: 16, color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, 
                    childAspectRatio: 0.56, 
                    crossAxisSpacing: 12, 
                    mainAxisSpacing: 12,
                  ),
                  itemCount: medicines.length,
                  itemBuilder: (context, i) {
                    final med = medicines[i];
                    double boxP = double.tryParse(med['price'].toString()) ?? 0;
                    double disc = isBoxMode 
                        ? (double.tryParse(med['box_discount'].toString()) ?? 0) 
                        : (double.tryParse(med['strip_discount'].toString()) ?? 0);
                    double unitP = isBoxMode 
                        ? boxP 
                        : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
                    double finalP = unitP - (unitP * disc / 100);

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(15), 
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: Column(children: [
                        Expanded(child: Stack(children: [
                          Padding(padding: const EdgeInsets.all(10), child: Center(child: Image.network(med['image'] ?? '', fit: BoxFit.contain))),
                          if(disc > 0) Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(5)), child: Text("${disc.toStringAsFixed(0)}% OFF", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                        ])),
                        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(med['name'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                          Row(children: [
                            Text("৳${finalP.toStringAsFixed(1)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                            const Spacer(),
                            if(disc > 0) Text("৳${unitP.toStringAsFixed(0)}", style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10)),
                          ]),
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity, height: 35, child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFE4E1), foregroundColor: Colors.black), 
                            onPressed: () {
                              setState(() { 
                                int idx = cartItems.indexWhere((it) => it['name'] == med['name'] && it['unit'] == (isBoxMode ? "Box" : "Strip"));
                                if(idx != -1) { cartItems[idx]['quantity']++; } else { cartItems.add({'name': med['name'],'unit': isBoxMode ? "Box": "Strip",'final_price': finalP,'original_price': unitP,'quantity': 1,}); }
                                cartUpdateNotifier.value++; 
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${med['name']} added to cart!"), duration: const Duration(seconds: 1)));
                            }, 
                            child: const Text("ADD TO CART", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                          )),
                        ]))
                      ]),
                    );
                  },
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
  List comps = []; 
  bool load = true;

  @override 
  void initState() { super.initState(); fetch(); }

  fetch() async { 
    final res = await http.get(Uri.parse("$baseUrl/categories/")); 
    if (res.statusCode == 200) {
      setState(() { comps = json.decode(res.body); load = false; }); 
    }
  }

  @override 
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text("Companies"),
      backgroundColor: Colors.white,
      elevation: 0,
      foregroundColor: Colors.black,
    ), 
    body: load 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView.builder(
            itemCount: comps.length, 
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.business, color: Colors.indigo),
              title: Text(comps[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onTap: () {
                // কোম্পানিতে ক্লিক করলে নতুন পেজে নিয়ে যাবে
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CompanyProductsScreen(
                      companyId: comps[i]['id'],
                      companyName: comps[i]['name'],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});
  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List orders = [];
  bool load = true;

  @override
  void initState() {
    super.initState();
    fetch();
  }

  fetch() async {
  SharedPreferences p = await SharedPreferences.getInstance();
  String? t = p.getString('token');
  
  print("আমার টোকেন: $t"); 

  final res = await http.get(
    Uri.parse("$baseUrl/my-orders/"), 
    headers: {'Authorization': 'Token $t'}
  );
  
  print("সার্ভার রেসপন্স কোড: ${res.statusCode}"); 
  print("সার্ভার থেকে আসা ডাটা: ${res.body}");     

  if (res.statusCode == 200) {
    setState(() {
      orders = json.decode(res.body);
      load = false;
    });
  } else {
    setState(() => load = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("আমার অর্ডার সমূহ", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFD00000),
        foregroundColor: Colors.white,
      ),
      body: load
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(child: Text("কোনো অর্ডার পাওয়া যায়নি"))
              : RefreshIndicator(
                  onRefresh: () => fetch(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final order = orders[i];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFD00000).withOpacity(0.1),
                            child: const Icon(Icons.shopping_basket, color: Color(0xFFD00000)),
                          ),
                          title: Text(
                            "Order #${order['id'] ?? 'N/A'}", 
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Status: ${order['status']}"),
                              Text("Bill: ৳${order['total_price']}"),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => OrderDetailScreen(order: order)),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class OrderDetailScreen extends StatelessWidget {
  final dynamic order;
  const OrderDetailScreen({super.key, required this.order});

  // লোগো কালার থিম
  final Color logoRed = const Color(0xFFD00000);
  final Color logoYellow = const Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("Order Details #${order['id'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: logoRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ১. অর্ডার স্ট্যাটাস ও ইনফো কার্ড
            _buildInfoCard(
              "Order information",
              Icons.info_outline,
              [
                _detailRow("Order id", "#${order['id']}"),
                _detailRow("Order status", order['status'], isStatus: true),
                _detailRow("Date & Time", order['created_at'].toString().split('T')[0]),
                _detailRow("Payment method", order['payment_method']),
              ],
            ),

            const SizedBox(height: 15),

            // ২. ঔষধের তালিকা কার্ড
            _buildInfoCard(
              "কেনা ঔষধের তালিকা",
              Icons.medication_rounded,
              [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    order['medicine_names'] ?? "কোনো তালিকা পাওয়া যায়নি",
                    style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            // ৩. ডেলিভারি ঠিকানা কার্ড
            _buildInfoCard(
              "Please add Your address",
              Icons.location_on_outlined,
              [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    order['address'] ?? "No address here",
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // ৪. সর্বমোট বিল সেকশন
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: logoRed.withOpacity(0.2)),
                boxShadow: [BoxShadow(color: logoRed.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Totall bill:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    "৳${order['total_price']}",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: logoRed),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 35),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[800],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                ),
                icon: const Icon(Icons.print_rounded),
                label: const Text("Print memo (PDF)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
         onPressed: () async {
  
  List<Map<String, dynamic>> itemsForPdf = [
    {
      "name": "Order Summary: ${order['medicine_names']}",
      "unit": "Order",
      "qty": 1,
      "price": double.tryParse(order['total_price'].toString()) ?? 0,
      "discount": 0, // অর্ডার হিস্টোরিতে আলাদা ডিসকাউন্ট না থাকলে ০
    }
  ];

  await InvoiceService.generateInvoice(
    customerName: "ID: #${order['id']}", 
    phone: "Payment: ${order['payment_method']}", 
    items: itemsForPdf, 
  );
},
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  // --- কার্ড ডিজাইন বিল্ডার ---
  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: logoRed, size: 22),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            ],
          ),
          const Divider(height: 25),
          ...children,
        ],
      ),
    );
  }

  // --- তথ্য রো (Row) বিল্ডার ---
  Widget _detailRow(String label, String? value, {bool isStatus = false}) {
    Color valColor = Colors.black87;
    if (isStatus) {
      if (value?.toLowerCase() == "pending") valColor = Colors.orange;
      if (value?.toLowerCase() == "delivered") valColor = Colors.green;
      if (value?.toLowerCase() == "cancelled") valColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Flexible(
            child: Text(
              value ?? "N/A",
              style: TextStyle(fontWeight: FontWeight.bold, color: valColor, fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

 class MedicineDetailScreen extends StatefulWidget {
  final dynamic medicine;
  const MedicineDetailScreen({super.key, required this.medicine});

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {

  @override
  Widget build(BuildContext context) {
    final med = widget.medicine;
    // আপনার অরিজিনাল ভেরিয়েবল নাম ব্যবহার করা হয়েছে
    int stock = int.tryParse(med['stock_quantity'].toString()) ?? 0;
    bool isOutOfStock = stock < 1;

    double boxP = double.tryParse(med['price'].toString()) ?? 0;
    double disc = isBoxMode 
        ? (double.tryParse(med['box_discount'].toString()) ?? 0) 
        : (double.tryParse(med['strip_discount'].toString()) ?? 0);
    double unitP = isBoxMode ? boxP : (boxP / (int.tryParse(med['strips_per_box'].toString()) ?? 1));
    double finalP = unitP - (unitP * disc / 100);

    return Scaffold(
      appBar: AppBar(
        title: Text(med['name']), 
        backgroundColor: const Color(0xFFD00000), 
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ইমেজ সেকশন - ডিজাইন ইনট্যাক্ট
            Container(
              height: 280, 
              width: double.infinity, 
              color: Colors.white, 
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ইমেজ অপাসিটি ১.০ (সবসময় পরিষ্কার)
                  Image.network(med['image'] ?? '', fit: BoxFit.contain),
                  
                  // স্টক শূন্য হলে ছবির উপরে আউট অফ স্টক লেখা
                  if (isOutOfStock)
                    Container(
                      width: double.infinity, height: double.infinity,
                      color: Colors.black.withOpacity(0.2),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
                          child: const Text("OUT OF STOCK", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med['name'], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text("৳${finalP.toStringAsFixed(1)}", style: TextStyle(fontSize: 30, color: isOutOfStock ? Colors.grey : const Color(0xFFD00000), fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      if(disc > 0) 
                        Text("৳${unitP.toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  
                  if (isOutOfStock)
                    const Text("দুঃখিত, বর্তমানে পণ্যটি স্টকে নেই।", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500))
                  else if (disc > 0)
                    Container(
                      padding: const EdgeInsets.all(10), 
                      decoration: BoxDecoration(color: Colors.yellow[700], borderRadius: BorderRadius.circular(8)), 
                      child: Text("Special Discount: ${disc.toStringAsFixed(0)}% OFF", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
                    ),
                  
                  const SizedBox(height: 25),
                  const Text("Description:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 8),
                  Text(med['description'] ?? "No description available.", style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.5)),
                  
                  const SizedBox(height: 40),
                  
                  // আপনার সেই প্রো-লেভেল গ্রেডিয়েন্ট বাটন
                  SizedBox(
                    width: double.infinity, height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: isOutOfStock ? 0 : 5),
                      onPressed: isOutOfStock ? null : () {
                        setState(() { 
                          int idx = cartItems.indexWhere((it) => it['name'] == med['name'] && it['unit'] == (isBoxMode ? "Box" : "Strip"));
                          if(idx != -1) { cartItems[idx]['quantity']++; } 
                          else { cartItems.add({'name': med['name'],'unit': isBoxMode ? "Box" : "Strip",'final_price': finalP,'original_price': unitP,'quantity': 1,'discount': disc}); }
                          cartUpdateNotifier.value++; 
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to Cart!"), backgroundColor: Colors.green));
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: isOutOfStock 
                              ? null 
                              : const LinearGradient(colors: [Color(0xFFD00000), Color(0xFFFF6F00)]), 
                          color: isOutOfStock ? Colors.grey.shade400 : null,
                          borderRadius: BorderRadius.circular(15)
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            isOutOfStock ? "OUT OF STOCK" : "ADD TO CART", 
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Panel", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // ১. স্টক ম্যানেজমেন্ট কার্ড
            _buildAdminCard(
              context,
              title: "Stock Management",
              subtitle: "ওষুধের স্টক আপডেট ও চেক করুন",
              icon: Icons.inventory_2_outlined,
              color: Colors.indigo,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminMedicineScreen())),
            ),
            const SizedBox(height: 15),
            // ২. অর্ডার ম্যানেজমেন্ট কার্ড
            _buildAdminCard(
              context,
              title: "Order Management",
              subtitle: "কাস্টমারদের অর্ডারগুলো প্রসেস করুন",
              icon: Icons.shopping_bag_outlined,
              color: Colors.red[700]!,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminOrdersScreen())),
            ),
          ],
        ),
      ),
    );
  }

  // অ্যাডমিন কার্ড বিল্ডার (সহজ ও সুন্দর)
  Widget _buildAdminCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          radius: 25,
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}