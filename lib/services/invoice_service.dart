import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class InvoiceService {
  static Future<void> generateInvoice({
    required String customerName,
    required String phone,
    required List<Map<String, dynamic>> items,
  }) async {
    final pdf = pw.Document();
    final date = DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now());

    double grandSubtotal = 0;
    double totalDiscountAmount = 0;

    // ================= PDF =================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ================= HEADER =================
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "KHALIL MEDICARE",
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red900,
                          ),
                        ),
                        pw.Text("Your Trusted Online Pharmacy"),
                        pw.Text("Phone: 01XXXXXXXXX"), // আপনার ফার্মেসির নাম্বার দিন
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          "INVOICE",
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text("Date: $date"),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),
                pw.Divider(),

                // ================= CUSTOMER INFO =================
                pw.Text(
                  "BILL TO:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(customerName.isEmpty ? "Walk-in Customer" : customerName),
                pw.Text("Phone: $phone"),

                pw.SizedBox(height: 20),

                // ================= TABLE =================
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.indigo900,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3), // Medicine Name
                    1: const pw.FlexColumnWidth(1.2), // Unit (Box/Strip)
                    2: const pw.FlexColumnWidth(1), // Qty
                    3: const pw.FlexColumnWidth(1.5), // Price
                    4: const pw.FlexColumnWidth(1), // Disc %
                    5: const pw.FlexColumnWidth(1.5), // Subtotal
                  },
                  headers: [
                    'Medicine',
                    'Unit',
                    'Qty',
                    'Price',
                    'Disc %',
                    'Total',
                  ],
                  data: items.map((item) {
                    // ক্যালকুলেশন
                    double price = double.tryParse(item['price'].toString()) ?? 0;
                    int qty = int.tryParse(item['qty'].toString()) ?? 1;
                    double discountPercent = double.tryParse(item['discount'].toString()) ?? 0;
                    String unit = item['unit'] ?? "Strip"; // Box or Strip

                    double itemTotalWithoutDisc = price * qty;
                    double itemDiscount = (itemTotalWithoutDisc * discountPercent) / 100;
                    double finalItemTotal = itemTotalWithoutDisc - itemDiscount;

                    // গ্র্যান্ড টোটালের জন্য যোগ করা
                    grandSubtotal += itemTotalWithoutDisc;
                    totalDiscountAmount += itemDiscount;

                    return [
                      item['name'] ?? "Medicine",
                      unit,
                      qty.toString(),
                      price.toStringAsFixed(2),
                      "${discountPercent.toStringAsFixed(0)}%",
                      finalItemTotal.toStringAsFixed(2),
                    ];
                  }).toList(),
                ),

                pw.SizedBox(height: 25),

                // ================= SUMMARY / TOTALS =================
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 200,
                      child: pw.Column(
                        children: [
                          _buildTotalRow("Subtotal:", grandSubtotal.toStringAsFixed(2)),
                          _buildTotalRow("Discount:", "- ${totalDiscountAmount.toStringAsFixed(2)}", color: PdfColors.green700),
                          pw.Divider(),
                          _buildTotalRow(
                            "GRAND TOTAL:", 
                            "TK ${(grandSubtotal - totalDiscountAmount).toStringAsFixed(2)}",
                            isBold: true,
                            fontSize: 16,
                            color: PdfColors.red900,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.Spacer(),
                pw.Divider(),

                pw.Center(
                  child: pw.Text(
                    "Thank you for shopping with Khalil Medicare!",
                    style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic,
                      fontSize: 10,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    "This is a computer-generated invoice.",
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  // টোটাল সেকশনের জন্য ছোট উইজেট
  static pw.Widget _buildTotalRow(String label, String value, {bool isBold = false, double fontSize = 12, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}