// File: lib/screens/qr_scan_page.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rental_app/services/supabase_service.dart';

class QRScanPage extends StatefulWidget {
  final String rentalId;

  const QRScanPage({super.key, required this.rentalId});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  bool paymentProcessed = false;
  double amountToPay = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateAmount();
  }

  Future<void> _calculateAmount() async {
    try {
      final rental = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('id', widget.rentalId)
          .single();

      if (rental != null) {
        final product = rental['products'];
        double basePrice = product['price']?.toDouble() ?? 0;

        // Calculate overdue penalty if any
        double penaltyAmount = 0;
        if (rental['expected_return_date'] != null) {
          final expectedDate = DateTime.parse(rental['expected_return_date']);
          final now = DateTime.now();
          if (now.isAfter(expectedDate)) {
            final lateDays = now.difference(expectedDate).inDays;
            penaltyAmount = SupabaseService()
                .calculatePenalty(pricePerDay: basePrice, lateDays: lateDays);
          }
        }

        setState(() {
          amountToPay = basePrice + penaltyAmount;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to calculate amount: $e')),
        );
      }
    }
  }

  Future<void> _processPayment() async {
    try {
      await SupabaseService().markRentalAsPaid(
        rentalId: widget.rentalId,
        amountPaid: amountToPay,
      );
      if (!mounted) return;
      setState(() => paymentProcessed = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Owner QR for Payment')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  flex: 4,
                  child: MobileScanner(
                    onDetect: (capture) async {
                      if (paymentProcessed) return;

                      final barcode = capture.barcodes.first;
                      if (barcode.rawValue == null) return;

                      await _processPayment();
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: paymentProcessed
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check_circle, color: Colors.green, size: 60),
                              SizedBox(height: 16),
                              Text(
                                'Payment Successful!',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Total Amount to Pay',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '₹$amountToPay',
                                style: const TextStyle(
                                    fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Scan the owner\'s QR code to complete the payment.',
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}






