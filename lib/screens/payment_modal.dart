import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:rental_app/models/payment_model.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentModal extends StatefulWidget {
  final String rentalId;
  final PaymentBreakdown paymentBreakdown;
  final String? qrCodeUrl;
  final String? upiId;
  final VoidCallback onPaymentComplete;

  const PaymentModal({
    super.key,
    required this.rentalId,
    required this.paymentBreakdown,
    this.qrCodeUrl,
    this.upiId,
    required this.onPaymentComplete,
  });

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  final _transactionIdController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isProcessing = false;
  String? _paymentScreenshot;
  PaymentMethod _selectedMethod = PaymentMethod.qr;

  @override
  void dispose() {
    _transactionIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _uploadPaymentScreenshot() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final fileName = 'payment_${widget.rentalId}_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'payment_screenshots/$fileName';

        // Upload to Supabase storage (use existing 'products' bucket)
        final bytes = await file.readAsBytes();
        await SupabaseService.client.storage.from('products').uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: 'image/png',
          ),
        );
        
        final screenshotUrl = SupabaseService.client.storage.from('products').getPublicUrl(filePath);
        
        setState(() {
          _paymentScreenshot = screenshotUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment screenshot uploaded successfully!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload screenshot: $e')),
      );
    }
  }

  Future<void> _launchUPI(String upiId, double amount) async {
    final uri = Uri.parse('upi://pay?pa=$upiId&pn=Owner&am=$amount&cu=INR');
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No UPI app found. Please install a UPI app.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to launch UPI app: $e')),
      );
    }
  }

  Future<void> _processPayment() async {
    if (_transactionIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter transaction ID')),
      );
      return;
    }

    if (_paymentScreenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload the payment screenshot')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Resolve identifiers from rental
      final rentalRow = await SupabaseService.client
          .from('rentals')
          .select('product_id, renter_id, user_id')
          .eq('id', widget.rentalId)
          .single();

      final String productId = rentalRow['product_id'];
      final String renterId = rentalRow['renter_id'];
      final String ownerId = rentalRow['user_id'];

      final String methodName = _selectedMethod.name; // 'qr' | 'upi' | 'cash' | 'card'

      // 1) Create a payment record for audit/owner visibility
      final paymentResult = await SupabaseService.client.from('payments').insert({
        'rental_id': widget.rentalId,
        'payer_id': renterId,
        'payee_id': ownerId,
        'amount': widget.paymentBreakdown.total,
        'method': methodName,
        'status': 'submitted', // awaiting owner verification
        'paid_at': DateTime.now().toIso8601String(),
        'receipt_url': _paymentScreenshot,
        'transaction_id': _transactionIdController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      }).select().single();

      final String paymentId = paymentResult['id'];

      // 2) Update rental with payment linkage and set payment_status to submitted
      // IMPORTANT: Check if this is a penalty payment (rental is already active) vs initial rent payment
      // For penalty payments, DON'T overwrite 'amount' field - it should keep base rent
      // Only update 'amount' for initial rent payments
      print('Updating rental ${widget.rentalId} with payment_id: $paymentId');
      
      // Fetch current rental to check status
      final currentRental = await SupabaseService.client
          .from('rentals')
          .select('status, amount_due')
          .eq('id', widget.rentalId)
          .maybeSingle();
      
      final bool isPenaltyPayment = currentRental?['status'] == 'active';
      
      final updateData = <String, dynamic>{
        'payment_status': 'submitted',
        'payment_id': paymentId,
        // Mirror renter-entered fields so UI can display even if payments table lacks columns
        'transaction_id': _transactionIdController.text.trim(),
        'payment_screenshot': _paymentScreenshot,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      };
      
      // Only update 'amount' for initial rent payments, not penalty payments
      // For penalty payments, 'amount' should preserve the base rent
      if (!isPenaltyPayment) {
        // Initial rent payment - set amount to total (base rent)
        updateData['amount'] = widget.paymentBreakdown.total.toString();
      } else {
        // Penalty payment - preserve base rent in 'amount' field
        // Use amount_due as base rent, or keep existing amount if it represents base rent
        if (currentRental != null && currentRental['amount_due'] != null) {
          updateData['amount'] = currentRental['amount_due'].toString();
        }
        // If no amount_due, leave amount field unchanged (should already have base rent)
        print('Penalty payment detected - preserving base rent in amount field');
      }
      
      final updateResult = await SupabaseService.client.from('rentals').update(updateData).eq('id', widget.rentalId).select();
      
      print('Rental update result: $updateResult');

      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentComplete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment processed successfully!')),
        );
      }
    } catch (e, stackTrace) {
      print('Payment processing error: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process payment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Text(
                  'Complete Payment',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAmountBreakdown(),
                  const SizedBox(height: 32),
                  _buildPaymentMethodSelection(),
                  const SizedBox(height: 32),
                  _buildPaymentActions(),
                  const SizedBox(height: 32),
                  _buildTransactionDetails(),
                  const SizedBox(height: 32),
                  _buildPaymentScreenshot(),
                  const SizedBox(height: 32),
                  _buildNotes(),
                  const SizedBox(height: 100), // Space for button
                ],
              ),
            ),
          ),

          // Bottom button
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: const Color(0xFFE5E7EB)),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing || _paymentScreenshot == null ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _paymentScreenshot == null ? 'Upload Screenshot to Confirm' : 'Confirm Payment',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountBreakdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 16),
          _buildAmountRow('Base Rent (${widget.paymentBreakdown.rentalDays} days)', widget.paymentBreakdown.baseRent),
          if (widget.paymentBreakdown.penalty > 0) ...[
            const SizedBox(height: 8),
            _buildAmountRow('Late Penalty (${widget.paymentBreakdown.overdueDays} days)', widget.paymentBreakdown.penalty, isPenalty: true),
          ],
          const Divider(height: 24),
          _buildAmountRow('Total Amount', widget.paymentBreakdown.total, isTotal: true),
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

  Widget _buildPaymentMethodSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Method',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.qrCodeUrl != null)
          _buildPaymentMethodOption(
            PaymentMethod.qr,
            'QR Code',
            'Scan the QR code to pay',
            Icons.qr_code_2,
            const Color(0xFF007BFF),
          ),
        if (widget.upiId != null)
          _buildPaymentMethodOption(
            PaymentMethod.upi,
            'UPI',
            'Pay directly via UPI',
            Icons.account_balance_wallet,
            const Color(0xFF10B981),
          ),
      ],
    );
  }

  Widget _buildPaymentMethodOption(
    PaymentMethod method,
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedMethod == method;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE5E7EB),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? color : const Color(0xFF111111),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedMethod == PaymentMethod.qr && widget.qrCodeUrl != null)
          _buildQRAction(),
        if (_selectedMethod == PaymentMethod.upi && widget.upiId != null)
          _buildUPIAction(),
      ],
    );
  }

  Widget _buildQRAction() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.qrCodeUrl!,
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
          const Text(
            'Scan this QR code with your UPI app to pay',
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

  Widget _buildUPIAction() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Color(0xFF10B981),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.upiId!,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Amount: ₹${widget.paymentBreakdown.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _launchUPI(widget.upiId!, widget.paymentBreakdown.total),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Open UPI App',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaction Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _transactionIdController,
          decoration: const InputDecoration(
            labelText: 'Transaction ID',
            hintText: 'Enter UPI transaction ID',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            prefixIcon: Icon(Icons.receipt_long),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter transaction ID';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPaymentScreenshot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Screenshot (Required)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _uploadPaymentScreenshot,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: _paymentScreenshot != null ? Colors.white : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _paymentScreenshot != null ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
                style: BorderStyle.solid,
                width: 2,
              ),
            ),
            child: _paymentScreenshot != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _paymentScreenshot!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.error, color: Color(0xFFDC2626)),
                        );
                      },
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 32, color: Color(0xFF6B7280)),
                      SizedBox(height: 8),
                      Text(
                        'Upload Payment Screenshot',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Additional Notes (Optional)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes',
            hintText: 'Any additional information about the payment...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            prefixIcon: Icon(Icons.note_alt_outlined),
          ),
        ),
      ],
    );
  }
}
