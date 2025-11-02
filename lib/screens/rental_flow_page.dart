import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/screens/payment_dashboard.dart';
import 'package:rental_app/models/payment_model.dart';

class RentalFlowPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const RentalFlowPage({super.key, required this.product});

  @override
  State<RentalFlowPage> createState() => _RentalFlowPageState();
}

class _RentalFlowPageState extends State<RentalFlowPage> {
  int _selectedHours = 1;
  bool _isProcessing = false;
  final SupabaseService _supabase = SupabaseService();

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final pricePerHour = product['price'] is num
        ? (product['price'] as num).toDouble()
        : double.tryParse(product['price']?.toString() ?? '0') ?? 0.0;
    final totalAmount = pricePerHour * _selectedHours;
    final qrUrl = product['qr_code_url'];
    final upiId = product['upi_id'];
    final hasPaymentMethods = qrUrl != null || upiId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Rent Product'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111111),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProductCard(product),
            const SizedBox(height: 24),
            _buildRentalDurationSelector(pricePerHour),
            const SizedBox(height: 24),
            _buildPaymentMethodsCard(qrUrl, upiId, hasPaymentMethods),
            const SizedBox(height: 24),
            _buildAmountBreakdown(pricePerHour, totalAmount),
            const SizedBox(height: 32),
            _buildRentButton(hasPaymentMethods, totalAmount),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final parsedPrice = product['price'] is num
        ? (product['price'] as num).toDouble()
        : double.tryParse(product['price']?.toString() ?? '0') ?? 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF007BFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF007BFF),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Product',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product['description'] ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${parsedPrice.toStringAsFixed(2)} per hour',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007BFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRentalDurationSelector(double pricePerHour) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'Select Rental Duration',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedHours,
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  items: List.generate(24, (index) => index + 1)
                      .map((hour) => DropdownMenuItem(
                            value: hour,
                            child: Text('$hour ${hour == 1 ? 'Hour' : 'Hours'}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedHours = value ?? 1;
                    });
                  },
                ),
              ),
            ],
          ),
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
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Rate per hour:'),
                    Text('₹${pricePerHour.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Duration:'),
                    Text('$_selectedHours ${_selectedHours == 1 ? 'hour' : 'hours'}'),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '₹${(pricePerHour * _selectedHours).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Color(0xFF007BFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsCard(String? qrUrl, String? upiId, bool hasPaymentMethods) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'Payment Methods',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 16),
          if (hasPaymentMethods) ...[
            if (qrUrl != null) ...[
              _buildPaymentMethodItem('QR Code Available', Icons.qr_code_2, const Color(0xFF007BFF)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF007BFF), size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'You will see the owner\'s QR code after confirming rental to make payment',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (qrUrl != null && upiId != null) const SizedBox(height: 12),
            if (upiId != null) _buildPaymentMethodItem('UPI Payment Available', Icons.account_balance_wallet, const Color(0xFF10B981)),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No payment methods available. Owner needs to setup QR code or UPI ID.',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodItem(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Icon(Icons.check_circle, color: color, size: 16),
        ],
      ),
    );
  }

  Widget _buildAmountBreakdown(double pricePerHour, double totalAmount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'Payment Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 16),
          _buildAmountRow('Rate per hour', pricePerHour),
          _buildAmountRow('Rental duration', _selectedHours.toDouble(), isDuration: true),
          const Divider(height: 24),
          _buildAmountRow('Total Amount', totalAmount, isTotal: true),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF007BFF), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment is required upfront. Late returns will incur additional penalties.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, double value, {bool isDuration = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
              color: const Color(0xFF6B7280),
            ),
          ),
          Text(
            isDuration 
                ? '$_selectedHours ${_selectedHours == 1 ? 'hour' : 'hours'}'
                : '₹${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? const Color(0xFF007BFF) : const Color(0xFF111111),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRentButton(bool hasPaymentMethods, double totalAmount) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing || !hasPaymentMethods ? null : () => _processRental(totalAmount),
        style: ElevatedButton.styleFrom(
          backgroundColor: hasPaymentMethods ? const Color(0xFF007BFF) : const Color(0xFF9CA3AF),
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
                hasPaymentMethods ? 'Proceed to Payment' : 'Payment Not Available',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Future<void> _processRental(double totalAmount) async {
    setState(() => _isProcessing = true);

    try {
      final pricePerHour = widget.product['price'] is num
          ? (widget.product['price'] as num).toDouble()
          : double.tryParse(widget.product['price']?.toString() ?? '0') ?? 0.0;

      final authProvider = context.read<AuthProvider>();
      if (authProvider.user == null) {
        throw Exception('User not logged in');
      }

      // Step 1: Create rental
      final rental = await _supabase.rentProduct(
        productId: widget.product['id'],
        renterId: authProvider.user!.id,
      );

      // Step 2: Update rental with hours and amount
      await _supabase.updateRentalHours(
        rentalId: rental['id'],
        rentalHours: _selectedHours,
        pricePerHour: pricePerHour,
      );

      if (!mounted) return;

      // Step 3: Navigate to payment
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentDashboard(
            rentalId: rental['id'],
            productId: widget.product['id'],
            ownerId: widget.product['user_id'],
            qrCodeUrl: widget.product['qr_code_url'],
            upiId: widget.product['upi_id'],
          ),
        ),
      );

      // Step 4: Return to previous screen
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process rental: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
