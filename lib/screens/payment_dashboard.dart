import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/models/payment_model.dart';
import 'package:rental_app/screens/payment_modal.dart';
import 'package:rental_app/screens/qr_upload_modal.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentDashboard extends StatefulWidget {
  final String rentalId;
  final String productId;
  final String ownerId;
  final String? qrCodeUrl;
  final String? upiId;

  const PaymentDashboard({
    super.key,
    required this.rentalId,
    required this.productId,
    required this.ownerId,
    this.qrCodeUrl,
    this.upiId,
  });

  @override
  State<PaymentDashboard> createState() => _PaymentDashboardState();
}

class _PaymentDashboardState extends State<PaymentDashboard> {
  bool _isLoading = true;
  Map<String, dynamic>? _rentalData;
  Map<String, dynamic>? _productData;
  Map<String, dynamic>? _ownerData;
  PaymentBreakdown? _paymentBreakdown;
  String? _qrCodeUrl;
  String? _upiId;

  // Parse a timestamp string as LOCAL time, ignoring any trailing timezone suffix like 'Z' or '+00:00'.
  DateTime? _parseLocalIgnoringTimezone(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final normalized = raw.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
    return DateTime.tryParse(normalized);
  }

  double _computePenaltyDueNow() {
    if (_rentalData == null || _productData == null) return 0.0;
    
    final rentalStatus = (_rentalData!['status'] ?? '').toString();
    final paymentStatus = (_rentalData!['payment_status'] ?? '').toString();
    final returnedAt = _rentalData!['returned_at'];
    
    // No penalty for completed/returned rentals
    if (rentalStatus == 'completed' || returnedAt != null) {
      return 0.0;
    }
    
    final recordedLate = (_rentalData!['late_charge'] as num?)?.toDouble() ?? 0.0;
    final bool isRentalActive = rentalStatus == 'active' || rentalStatus == 'overdue';
    
    // If penalty payment is pending approval, use the locked penalty amount
    if (recordedLate > 0 && (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment')) {
      return recordedLate; // Return locked penalty amount
    }

    final pricePerDay = (_productData!['price'] ?? 0).toDouble();
    int rentalDays = _rentalData!['rental_days'] ?? 0;
    if (rentalDays <= 0) rentalDays = 1;

    // First, calculate if rental is overdue and what the penalty should be
    double computedPenalty = 0.0;
    try {
      DateTime? expectedDate = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
      expectedDate ??= _parseLocalIgnoringTimezone(_rentalData!['rented_at'])?.add(Duration(days: rentalDays));
      if (expectedDate != null) {
        DateTime endTime;
        if (_rentalData!['returned_at'] != null) {
          endTime = _parseLocalIgnoringTimezone(_rentalData!['returned_at'])!;
        } else if (_rentalData!['return_requested_at'] != null) {
          endTime = _parseLocalIgnoringTimezone(_rentalData!['return_requested_at'])!;
        } else {
          endTime = DateTime.now();
        }
        if (endTime.isAfter(expectedDate)) {
          final overdueDuration = endTime.difference(expectedDate);
          final overdueDays = overdueDuration.inDays;
          // If overdue by any amount (even less than a full day), count as 1 day minimum
          if (overdueDays < 1) {
            // Overdue by less than a full day - still charge for 1 day
            computedPenalty = pricePerDay * 1.0; // 100% penalty for 1 day (full rate)
          } else {
            computedPenalty = pricePerDay * overdueDays * 1.0; // 100% penalty per day (full rate)
          }
        }
      }
    } catch (_) {}
    
    // If no penalty is computed (not overdue), return 0
    if (computedPenalty <= 0.0 && recordedLate <= 0.0) {
      return 0.0;
    }
    
    // Check if penalty is already paid and approved
    // For active rentals, we need to distinguish between initial rent payment and penalty payment
    final latestPayment = _rentalData!['latest_payment'];
    final bool hasLatestPayment = latestPayment != null;
    final String? latestPaymentStatus = latestPayment?['status']?.toString();
    final double? latestPaymentAmount = latestPayment?['amount'] != null 
        ? (latestPayment['amount'] as num).toDouble() 
        : null;
    
    // Penalty is approved if:
    // 1. late_charge exists (penalty was recorded)
    // 2. AND (latest payment exists with status 'paid'/'approved' OR payment_status is 'paid' for active rental)
    // 3. For active rentals, check if payment amount matches penalty (to distinguish from initial rent)
    final bool penaltyApproved = (recordedLate > 0.0 || computedPenalty > 0.0) && (
      (hasLatestPayment &&
       (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
       (latestPaymentAmount != null && latestPaymentAmount! > 0) &&
       (recordedLate > 0.0 ? latestPaymentAmount! >= recordedLate * 0.9 : latestPaymentAmount! >= computedPenalty * 0.9)) ||
      (isRentalActive && paymentStatus == 'paid' && recordedLate > 0.0 && 
       latestPaymentAmount != null && latestPaymentAmount! >= recordedLate * 0.9) // Payment amount matches penalty
    );
    
    // If penalty is already paid and approved, no penalty due
    if (penaltyApproved) {
      return 0.0;
    }
    
    // Return the penalty amount (use recorded late_charge if exists, otherwise computed penalty)
    return recordedLate > 0.0 ? recordedLate : computedPenalty;
  }

  @override
  void initState() {
    super.initState();
    _loadPaymentData();
  }

  Future<void> _loadPaymentData() async {
    try {
      // Load rental data
      final rental = await SupabaseService.client
          .from('rentals')
          .select('*, products(qr_code_url, upi_id, name, price, description, images), payments(* )')
          .eq('id', widget.rentalId)
          .single();

      if (rental != null) {
        setState(() {
          _rentalData = rental;
          _productData = rental['products'];
        });

        // Try to load owner data from profiles table
        try {
          final owner = await SupabaseService.client
              .from('profiles')
              .select()
              .eq('id', widget.ownerId)
              .maybeSingle();

          setState(() {
            _ownerData = owner;
            // Priority: use passed in payment info, then product data, then widget params
            _qrCodeUrl = widget.qrCodeUrl ?? _productData?['qr_code_url'];
            _upiId = widget.upiId ?? _productData?['upi_id'];
          });
        } catch (e) {
          // If profiles table doesn't exist or query fails, continue without owner data
          print('Could not load owner profile: $e');
          setState(() {
            // Use passed in payment info if available, otherwise use queried data
            _qrCodeUrl = widget.qrCodeUrl ?? _productData?['qr_code_url'];
            _upiId = widget.upiId ?? _productData?['upi_id'];
          });
        }

        // If there is a linked payment_id prefer that; else fall back to latest by rental_id
        try {
          Map<String, dynamic>? payment;
          if (rental['payment_id'] != null) {
            payment = await SupabaseService.client
                .from('payments')
                .select()
                .eq('id', rental['payment_id'])
                .maybeSingle();
          }
          if (payment == null) {
            final list = await SupabaseService.client
                .from('payments')
                .select()
                .eq('rental_id', widget.rentalId)
                .order('paid_at', ascending: false)
                .limit(1);
            if (list is List && list.isNotEmpty) {
              payment = Map<String, dynamic>.from(list.first);
            }
          }

          if (payment != null) {
            setState(() {
              _rentalData!['latest_payment'] = payment;
            });
          }
        } catch (_) {}

        // Calculate payment breakdown
        _calculatePaymentBreakdown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading payment data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _calculatePaymentBreakdown() {
    if (_rentalData == null || _productData == null) return;

    final pricePerDay = (_productData!['price'] ?? 0).toDouble();
    // Derive days: prefer rental_days, else calculate from amount_due, else difference between expected_return_date and rented_at, else 1
    int rentalDays = _rentalData!['rental_days'] ?? 0;
    if (rentalDays == 0) {
      // Try to calculate from amount_due if available (for pending rentals)
      if (_rentalData!['amount_due'] != null && pricePerDay > 0) {
        final amountDue = (_rentalData!['amount_due'] as num).toDouble();
        rentalDays = (amountDue / pricePerDay).ceil();
      } else {
        // Fallback to time difference calculation
        try {
          final rentedAt = _parseLocalIgnoringTimezone(_rentalData!['rented_at']);
          final expected = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
          if (rentedAt != null && expected != null) {
            final diffDays = expected.difference(rentedAt).inDays;
            rentalDays = diffDays > 0 ? diffDays : 1; // At least 1 day
          }
        } catch (_) {}
      }
    }
    if (rentalDays <= 0) rentalDays = 1;
    final baseRent = pricePerDay * rentalDays;

    // Calculate penalty if overdue (per-day calculation, parsing as local and ignoring tz suffix)
    double penalty = 0;
    int overdueDays = 0;
    
    final rentalStatus = (_rentalData!['status'] ?? '').toString();
    final paymentStatus = (_rentalData!['payment_status'] ?? '').toString();
    final returnedAt = _rentalData!['returned_at'];
    final recordedLate = (_rentalData!['late_charge'] as num?)?.toDouble() ?? 0.0;
    
    // No penalty for completed/returned rentals
    if (rentalStatus == 'completed' || returnedAt != null) {
      penalty = 0;
    }
    // If penalty is already paid and approved, include it in breakdown (for total calculation) but mark as paid
    else if (recordedLate > 0 && paymentStatus == 'paid') {
      penalty = recordedLate; // Include paid penalty in total calculation
      try {
        DateTime? expectedDate = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
        expectedDate ??= _parseLocalIgnoringTimezone(_rentalData!['rented_at'])?.add(Duration(days: rentalDays));
        if (expectedDate != null) {
          // Calculate overdue days for display
          DateTime endTime = _parseLocalIgnoringTimezone(_rentalData!['return_requested_at']) ?? 
                            _parseLocalIgnoringTimezone(_rentalData!['latest_payment']?['paid_at']) ??
                            DateTime.now();
          if (endTime.isAfter(expectedDate)) {
            final overdueDaysCount = endTime.difference(expectedDate).inDays;
            overdueDays = overdueDaysCount > 0 ? overdueDaysCount : 1;
          }
        }
      } catch (_) {}
    }
    // If penalty payment is pending approval, use locked penalty amount
    else if (recordedLate > 0 && (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment')) {
      penalty = recordedLate; // Use locked penalty amount
      try {
        DateTime? expectedDate = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
        expectedDate ??= _parseLocalIgnoringTimezone(_rentalData!['rented_at'])?.add(Duration(days: rentalDays));
        if (expectedDate != null) {
          DateTime endTime = _parseLocalIgnoringTimezone(_rentalData!['return_requested_at']) ?? DateTime.now();
          if (endTime.isAfter(expectedDate)) {
            final overdueDaysCount = endTime.difference(expectedDate).inDays;
            overdueDays = overdueDaysCount > 0 ? overdueDaysCount : 1;
          }
        }
      } catch (_) {}
    }
    // Calculate live penalty for active overdue rentals
    else {
      try {
        DateTime? expectedDate = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
        expectedDate ??= _parseLocalIgnoringTimezone(_rentalData!['rented_at'])?.add(Duration(days: rentalDays));
        if (expectedDate != null) {
          DateTime endTime;
          if (_rentalData!['returned_at'] != null) {
            endTime = _parseLocalIgnoringTimezone(_rentalData!['returned_at'])!;
          } else if (_rentalData!['return_requested_at'] != null) {
            endTime = _parseLocalIgnoringTimezone(_rentalData!['return_requested_at'])!;
          } else {
            endTime = DateTime.now();
          }
          if (endTime.isAfter(expectedDate)) {
            final overdueDuration = endTime.difference(expectedDate);
            final overdueDaysCount = overdueDuration.inDays;
            // If overdue by any amount (even less than a full day), count as 1 day minimum
            if (overdueDaysCount < 1) {
              // Overdue by less than a full day - still charge for 1 day
              penalty = pricePerDay * 1.0; // 100% penalty for 1 day (full rate)
              overdueDays = 1;
            } else {
              penalty = pricePerDay * overdueDaysCount * 1.0; // 100% per-day penalty (full rate)
              overdueDays = overdueDaysCount;
            }
          }
        }
      } catch (_) {}
    }
    
    debugPrint('[PaymentDashboard] rental ${_rentalData!['id']}: days=$rentalDays base=$baseRent penalty=$penalty overdueDays=$overdueDays');

    setState(() {
      _paymentBreakdown = PaymentBreakdown(
        baseRent: baseRent,
        penalty: penalty,
        total: baseRent + penalty,
        rentalDays: rentalDays,
        overdueDays: overdueDays,
        pricePerDay: pricePerDay,
      );
    });
  }

  Future<void> _launchUPI(String upiId, double amount) async {
    final uri = Uri.parse('upi://pay?pa=$upiId&pn=Owner&am=$amount&cu=INR');
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: Copy UPI ID to clipboard
        await _copyToClipboard(upiId);
      }
    } catch (e) {
      await _copyToClipboard(upiId);
    }
  }

  Future<void> _copyToClipboard(String text) async {
    // Note: You'll need to add flutter/services import for Clipboard
    // Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('UPI ID copied: $text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111111),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPaymentCard(),
            const SizedBox(height: 12),
            _buildDueNowBanner(),
            const SizedBox(height: 24),
            _buildPaymentMethods(),
            const SizedBox(height: 24),
            _buildPaymentHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard() {
    final latest = _rentalData?['latest_payment'];
    final method = latest?['method'] ?? _rentalData?['payment_method'];
    final txn = latest?['transaction_id'] ?? _rentalData?['transaction_id'];
    final receipt = latest?['receipt_url'] ?? _rentalData?['payment_screenshot'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF007BFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF007BFF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productData?['name'] ?? 'Product',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111),
                      ),
                    ),
                    Text(
                      'Owner: ${_ownerData?['name'] ?? 'Unknown'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_paymentBreakdown != null) ...[
            _buildAmountRow('Base Rent (${_paymentBreakdown!.rentalDays} ${_paymentBreakdown!.rentalDays == 1 ? 'day' : 'days'})', _paymentBreakdown!.baseRent),
            if (_paymentBreakdown!.penalty > 0) ...[
              const SizedBox(height: 8),
              _buildAmountRow('Late Penalty (${_paymentBreakdown!.overdueDays} ${_paymentBreakdown!.overdueDays == 1 ? 'day' : 'days'})', _paymentBreakdown!.penalty, isPenalty: true),
            ],
            const Divider(height: 32),
            _buildAmountRow('Total Amount', _paymentBreakdown!.total, isTotal: true),
          ],
          const SizedBox(height: 16),
          _buildLatestPaymentDetails(),
          if (method != null || txn != null || receipt != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Submitted Payment Proof',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111111)),
                  ),
                  const SizedBox(height: 8),
                  if (method != null) _kv('Method', method.toString().toUpperCase()),
                  if (txn != null) _kv('Transaction ID', txn.toString()),
                  if (receipt != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        receipt.toString(),
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.error, color: Color(0xFFDC2626))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, double amount, {bool isPenalty = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
            color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
          ),
        ),
      ],
    );
  }

  Widget _buildLatestPaymentDetails() {
    final latest = _rentalData?['latest_payment'];
    if (latest == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 8),
          _kv('Method', (latest['method'] ?? '').toString().toUpperCase()),
          _kv('Transaction ID', latest['transaction_id'] ?? '-'),
          _kv('Amount Paid', '₹${(latest['amount'] ?? 0).toString()}'),
          _kv('Status', latest['status'] ?? '-'),
          if (latest['receipt_url'] != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                final url = latest['receipt_url'] as String;
                // ignore: deprecated_member_use
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    latest['receipt_url'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Color(0xFFDC2626)),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF111111), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Methods',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        if (_qrCodeUrl != null) _buildQRPaymentCard(),
        if (_upiId != null) _buildUPIPaymentCard(),
        if (_qrCodeUrl == null && _upiId == null) _buildNoPaymentMethods(),
      ],
    );
  }

  Widget _buildQRPaymentCard() {
    final penaltyDue = _computePenaltyDueNow();
    final bool hasPenaltyDue = penaltyDue > 0 && _rentalData?['returned_at'] == null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF007BFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.qr_code_2,
                  color: Color(0xFF007BFF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'QR Code Payment',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _qrCodeUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.error, color: Color(0xFFDC2626)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showPaymentModal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007BFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                hasPenaltyDue ? 'Pay Penalty ₹' + penaltyDue.toStringAsFixed(2) : 'Pay Now via UPI',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUPIPaymentCard() {
    final penaltyDue = _computePenaltyDueNow();
    final bool hasPenaltyDue = penaltyDue > 0 && _rentalData?['returned_at'] == null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'UPI Payment',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'UPI ID',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _upiId!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _launchUPI(_upiId!, hasPenaltyDue ? penaltyDue : (_paymentBreakdown?.total ?? 0)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                hasPenaltyDue ? 'Pay Penalty via UPI' : 'Pay via UPI App',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPaymentMethods() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.payment_outlined,
              color: Color(0xFF6B7280),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Payment Methods Available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The owner hasn\'t set up payment methods yet.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentHistory() {
    Color amber = const Color(0xFFF59E0B);
    Color green = const Color(0xFF10B981);
    Color blue = const Color(0xFF3B82F6);
    Color red = const Color(0xFFDC2626);

    final paymentStatus = (_rentalData?['payment_status'] ?? '').toString();
    final latestPayment = _rentalData?['latest_payment'];
    final hasRealProof = latestPayment != null && (
      (latestPayment['receipt_url'] != null && latestPayment['receipt_url'].toString().trim().isNotEmpty) ||
      (latestPayment['payment_screenshot'] != null && latestPayment['payment_screenshot'].toString().trim().isNotEmpty) ||
      (latestPayment['transaction_id'] != null && latestPayment['transaction_id'].toString().trim().isNotEmpty)
    );
    final bool showApprovalPending = hasRealProof &&
      (latestPayment['status'] == 'submitted' || latestPayment['status'] == 'pending_confirmation');

    // Determine if this is a penalty payment using context:
    // Check rental status - if it's 'active', initial rent was already approved
    final rentalStatus = (_rentalData?['status'] ?? '').toString();
    final bool isRentalActive = rentalStatus == 'active' && _rentalData?['returned_at'] == null;
    final penaltyDue = _computePenaltyDueNow();
    final bool hasPenaltyDue = penaltyDue > 0 && _rentalData?['returned_at'] == null;
    final recordedLate = (_rentalData?['late_charge'] as num?)?.toDouble() ?? 0.0;
    
    // Penalty payment detection:
    // - Rental must be active (initial rent was approved, rental is ongoing)
    // - There must be a penalty (recordedLate > 0 OR computed penalty > 0)
    // - Payment is pending approval
    // Note: When penalty payment is submitted, payment_status becomes 'submitted' which overwrites 'paid',
    // so we can't rely on payment_status. Instead, check if rental is active and has penalty.
    final bool hasPenalty = recordedLate > 0.0 || (penaltyDue > 0 && _rentalData?['returned_at'] == null);
    final bool isPenaltyPayment = isRentalActive && showApprovalPending && hasPenalty;

    Widget paymentStatusWidget;
    if (showApprovalPending) {
      paymentStatusWidget = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB), // soft amber
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.hourglass_top, color: Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPenaltyPayment ? 'Penalty Payment Pending Approval' : 'Approval Pending',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPenaltyPayment
                        ? 'Your penalty payment proof is being reviewed by the owner. Once approved, you can request return.'
                        : 'We are reviewing your payment proof. You will be notified once approved.',
                    style: const TextStyle(color: Color(0xFF92400E)),
                    softWrap: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // Get latest payment status first
      final String? latestPaymentStatus = latestPayment?['status']?.toString();
      final double? latestPaymentAmount = latestPayment?['amount'] != null 
          ? (latestPayment['amount'] as num).toDouble() 
          : null;
      
      // Check if payment is paid/completed
      if (paymentStatus == 'paid' || paymentStatus == 'completed' || 
          latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') {
        // Check if penalty was just paid (initial rent was already paid before)
        // Also check payment record status for more accurate detection
        // Penalty is paid if: rental is active AND late_charge exists AND payment is approved
        // Also check if payment amount matches penalty to distinguish from initial rent payment
        final bool isPenaltyPaid = isRentalActive && recordedLate > 0 && (
          (paymentStatus == 'paid' && latestPaymentAmount != null && latestPaymentAmount! >= recordedLate * 0.9) ||
          ((latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
           latestPaymentAmount != null && latestPaymentAmount! >= recordedLate * 0.9)
        );
      
      paymentStatusWidget = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5), // soft green
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPenaltyPaid ? 'Penalty Payment Approved' : 'All dues cleared.',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                  ),
                  if (isPenaltyPaid) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Your penalty payment was approved. You can now request return.',
                      style: const TextStyle(color: Color(0xFF065F46), fontSize: 12),
                      softWrap: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      } else {
        // Payment not paid yet
        paymentStatusWidget = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF), // soft blue
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No payment yet. Please pay to continue.',
                style: TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600),
                softWrap: true,
              ),
            ),
          ],
        ),
      );
      }
    }

    final hasApprovalPending = paymentStatus == 'submitted' || paymentStatus == 'pending';
    final hasPaymentApproved = paymentStatus == 'paid' || paymentStatus == 'completed' || paymentStatus == 'approved';

    // Recalculate penalty here to ensure it's up to date (match management screen parsing rules)
    double currentPenalty = 0.0;
    if (_rentalData != null && _productData != null) {
      final pricePerDay = (_productData!['price'] ?? 0).toDouble();
      int rentalDays = _rentalData!['rental_days'] ?? 0;
      if (rentalDays == 0) rentalDays = 1;
      
      try {
        DateTime? expectedDate = _parseLocalIgnoringTimezone(_rentalData!['expected_return_date']);
        expectedDate ??= _parseLocalIgnoringTimezone(_rentalData!['rented_at'])?.add(Duration(days: rentalDays));
        if (expectedDate != null) {
          DateTime endTime;
          if (_rentalData!['returned_at'] != null) {
            endTime = _parseLocalIgnoringTimezone(_rentalData!['returned_at'])!;
          } else if (_rentalData!['return_requested_at'] != null) {
            endTime = _parseLocalIgnoringTimezone(_rentalData!['return_requested_at'])!;
          } else {
            endTime = DateTime.now();
          }
          if (endTime.isAfter(expectedDate)) {
            final overdueDays = endTime.difference(expectedDate).inDays;
            final pricePerDay = (_productData!['price'] ?? 0).toDouble();
            currentPenalty = pricePerDay * overdueDays * 1.0; // 100% penalty per day (full rate)
          }
        }
      } catch (_) {}
    }
    
    debugPrint('[PaymentDashboard] Status check: recordedLate=$recordedLate, currentPenalty=$currentPenalty, penaltyDue=$penaltyDue, hasPenaltyDue=$hasPenaltyDue, returned_at=${_rentalData?['returned_at']}');

    Widget item(IconData icon, String title, String subtitle, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111111))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Status',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: paymentStatusWidget, // ONLY THIS!
        ),
      ],
    );
  }

  Widget _buildDueNowBanner() {
    final penaltyDue = _computePenaltyDueNow();
    final paymentStatus = (_rentalData?['payment_status'] ?? '').toString();
    final recordedLate = (_rentalData?['late_charge'] as num?)?.toDouble() ?? 0.0;
    final latestPayment = _rentalData?['latest_payment'];
    final latestPaymentStatus = latestPayment?['status']?.toString();
    
    // Check if penalty payment is already submitted and pending approval
    // If payment status is 'submitted' or 'awaiting_payment' and there's a late_charge, penalty payment is pending
    final bool penaltyPaymentPending = (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment' || 
                                        latestPaymentStatus == 'submitted' || latestPaymentStatus == 'pending_confirmation') &&
                                       recordedLate > 0;
    
    // Only show "Penalty Due Now" if penalty exists AND payment is NOT already submitted
    final bool hasPenaltyDue = penaltyDue > 0 && _rentalData?['returned_at'] == null && !penaltyPaymentPending;
    final double alreadyPaid = (_rentalData?['latest_payment']?['amount'] ?? _rentalData?['amount'] ?? 0).toDouble();
    final double total = _paymentBreakdown?.total ?? 0.0;
    final bool allPaid = !hasPenaltyDue && (alreadyPaid >= total || (_rentalData?['payment_status'] == 'paid' || _rentalData?['status'] == 'completed'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasPenaltyDue ? const Color(0xFFFEF2F2) : (penaltyPaymentPending ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasPenaltyDue ? const Color(0xFFFECACA) : (penaltyPaymentPending ? const Color(0xFFFDE68A) : const Color(0xFFD1FAE5))),
      ),
      child: Row(
        children: [
          Icon(
            hasPenaltyDue ? Icons.warning_amber_rounded : (penaltyPaymentPending ? Icons.hourglass_top : Icons.verified), 
            color: hasPenaltyDue ? const Color(0xFFDC2626) : (penaltyPaymentPending ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPenaltyDue 
                      ? 'Penalty Due Now' 
                      : (penaltyPaymentPending 
                          ? 'Penalty Payment Pending' 
                          : (allPaid ? 'All Dues Cleared' : 'Payment Summary')),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPenaltyDue
                      ? 'You need to pay ₹' + penaltyDue.toStringAsFixed(2) + ' to continue.'
                      : (penaltyPaymentPending
                          ? 'Your penalty payment proof is being reviewed. Once approved, you can request return.'
                          : ('Paid ₹' + alreadyPaid.toStringAsFixed(2) + (total > 0 ? ' of ₹' + total.toStringAsFixed(2) : ''))),
                  style: TextStyle(
                    fontSize: 13, 
                    color: hasPenaltyDue 
                        ? const Color(0xFFDC2626) 
                        : (penaltyPaymentPending ? const Color(0xFF92400E) : const Color(0xFF047857)), 
                    fontWeight: FontWeight.w500
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    final paymentStatus = _rentalData?['payment_status'];
    if (paymentStatus == 'submitted') {
      return const Color(0xFFF59E0B); // amber
    }
    if (paymentStatus == 'paid') {
      return const Color(0xFF10B981); // green
    }

    final status = _rentalData?['status'];
    switch (status) {
      case 'completed':
        return const Color(0xFF10B981);
      case 'awaiting_payment':
        return const Color(0xFFF59E0B);
      case 'pending':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _getStatusText() {
    final paymentStatus = _rentalData?['payment_status'];
    if (paymentStatus == 'submitted') {
      return 'Awaiting Owner Verification';
    }
    if (paymentStatus == 'paid') {
      return 'Payment Approved';
    }

    final status = _rentalData?['status'];
    switch (status) {
      case 'completed':
        return 'Payment Completed';
      case 'awaiting_payment':
        return 'Awaiting Payment';
      case 'pending':
        return 'Payment Pending';
      default:
        return 'Payment Pending';
    }
  }

  String _getStatusDescription() {
    final paymentStatus = _rentalData?['payment_status'];
    if (paymentStatus == 'submitted') {
      return 'Your receipt was submitted. The owner will verify and confirm.';
    }
    if (paymentStatus == 'paid') {
      return 'Your payment was approved. Your rental is active.';
    }

    final status = _rentalData?['status'];
    switch (status) {
      case 'completed':
        return 'Your payment has been successfully processed.';
      case 'awaiting_payment':
        return 'Please complete the payment to confirm your rental.';
      case 'pending':
        return 'Payment is being processed.';
      default:
        return 'Payment status is being updated.';
    }
  }

  void _showPaymentModal() {
    if (_paymentBreakdown == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final penaltyDue = _computePenaltyDueNow();
        final bool hasPenaltyDue = penaltyDue > 0 && _rentalData?['returned_at'] == null;
        final PaymentBreakdown toPay = hasPenaltyDue
            ? PaymentBreakdown(
                baseRent: 0,
                penalty: penaltyDue,
                total: penaltyDue,
                rentalDays: _paymentBreakdown!.rentalDays,
                overdueDays: _paymentBreakdown!.overdueDays,
                pricePerDay: _paymentBreakdown!.pricePerDay,
              )
            : _paymentBreakdown!;

        return PaymentModal(
          rentalId: widget.rentalId,
          paymentBreakdown: toPay,
          qrCodeUrl: _qrCodeUrl,
          upiId: _upiId,
          onPaymentComplete: () {
            _loadPaymentData(); // Refresh data
          },
        );
      },
    );
  }
}
