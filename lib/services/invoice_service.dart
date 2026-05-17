import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class InvoiceService {
  static Future<Uint8List> generateInvoice({required dynamic order, required List items}) async {
    final pdf = pw.Document();
    double grandTotalAmount = 0; 

    // গ্র্যান্ড টোটাল ক্যালকুলেশন (Price * Qty)
    for (var item in items) {
      double price = double.tryParse(item['price'].toString()) ?? 0;
      int qty = int.tryParse(item['quantity'].toString()) ?? 0;
      grandTotalAmount += (price * qty);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- Header Section ---
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("KHALIL MEDICARE", 
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text("Pharmacy Management System", style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("INVOICE", 
                          style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                      pw.Text("Order ID: #${order['id']}"),
                      pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}"),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              pw.Text("BILL TO:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("Name: ${order['username'] ?? 'N/A'}"),
              pw.Text("Address: ${order['address'] ?? 'N/A'}"),
              pw.SizedBox(height: 20),

              // --- Table Section (আপনার রিকোয়েস্ট অনুযায়ী কলাম) ---
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                cellHeight: 25,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.0), // Name
                  1: const pw.FlexColumnWidth(1.5), // Box/Strip/Pata
                  2: const pw.FlexColumnWidth(0.8), // Qty
                  3: const pw.FlexColumnWidth(1.5), // Main Price
                  4: const pw.FlexColumnWidth(1.5), // Subtotal
                },
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
                headers: ['Name', 'Box/Strip', 'Qty', 'Main Price', 'Subtotal'],
                data: items.map((item) {
                  
                  // --- গুরুত্বপূর্ণ লজিক: ইউনিট হ্যান্ডলিং ---
                  // আপনার কার্ট আইটেমে ইউনিটের নাম যে Key-তে আছে সেটি এখানে দিন। 
                  // আমি এখানে item['unit_type'] ধরেছি। যদি আপনার 'unit' বা অন্য কিছু হয় তবে সেটা লিখে দিন।
                  // ===== Unit Detect Logic =====

String displayUnit = "";

// possible keys check
if (item['unit_type'] != null) {
  displayUnit = item['unit_type'].toString();
} else if (item['unit'] != null) {
  displayUnit = item['unit'].toString();
} else if (item['selected_unit'] != null) {
  displayUnit = item['selected_unit'].toString();
} else if (item['box'] == true) {
  displayUnit = "Box";
} else if (item['strip'] == true) {
  displayUnit = "Strip";
} else if (item['pata'] == true) {
  displayUnit = "Pata";
} else {
  displayUnit = "Piece";
}

// সুন্দর Format
displayUnit =
    displayUnit[0].toUpperCase() +
    displayUnit.substring(1).toLowerCase();

                  double price = double.tryParse(item['price'].toString()) ?? 0;
                  int qty = int.tryParse(item['quantity'].toString()) ?? 0;
                  double subtotal = price * qty;

                  return [
                    item['medicine_name'] ?? 'Unknown',
                    displayUnit, // এখানে সরাসরি ইউজারের সিলেক্ট করা ইউনিট (Box/Strip/Pata) বসবে
                    qty.toString(),
                    price.toStringAsFixed(2),
                    subtotal.toStringAsFixed(2),
                  ];
                }).toList(),
              ),

              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColors.grey300),

              // --- Grand Total Section ---
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 220,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("GRAND TOTAL:", 
                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text("TK ${grandTotalAmount.toStringAsFixed(2)}", 
                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text("Thank you for choosing Khalil Medicare!", 
                        style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text("Software Developed by Khalil Medicare Team", 
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}