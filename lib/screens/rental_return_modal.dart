import 'package:flutter/material.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/models/payment_model.dart';

class RentalReturnModal extends StatefulWidget {
  final Map<String, dynamic> rental;
  final VoidCallback onReturnComplete;

  const RentalReturnModal({
    super.key,
    required this.rental,
    required this.onReturnComplete,
  });

  @override
  State<RentalReturnModal> createState() => _RentalReturnModalState();
}

class _RentalReturnModalState extends State<RentalReturnModal> {
  bool _isProcessing = false;
  PaymentBreakdown? _paymentBreakdown;

  @override
  void initState() {
    super.initState();
    _calculatePaymentBreakdown();
  }

  void _calculatePaymentBreakdown() {
    final product = widget.rental['products'];
    final pricePerHour = (product['price'] ?? 0).toDouble();

    // Determine booked hours: prefer rental_days field; else compute from rented_at -> expected_return_date
    int rentalHours = widget.rental['rental_days'] ?? 0;
    if (rentalHours == 0) {
      try {
        final rentedAt = widget.rental['rented_at'] != null ? DateTime.parse(widget.rental['rented_at']) : null;
        final expected = widget.rental['expected_return_date'] != null ? DateTime.parse(widget.rental['expected_return_date']) : null;
        if (rentedAt != null && expected != null) {
          final diffMinutes = expected.difference(rentedAt).inMinutes;
          rentalHours = (diffMinutes / 60).ceil();
        }
      } catch (_) {}
    }
    if (rentalHours <= 0) rentalHours = 1;
    final baseRent = pricePerHour * rentalHours;

    // Get locked late_charge if it exists (this is the penalty amount that was already paid/approved)
    final double? lockedLateCharge = (widget.rental['late_charge'] as num?)?.toDouble();
    final String paymentStatus = (widget.rental['payment_status'] ?? '').toString();
    
    // If return is requested, penalty should already be paid and locked in late_charge
    // Use the locked late_charge to ensure consistency with payment details
    double penalty = 0;
    int overdueHours = 0;
    
    if (lockedLateCharge != null && lockedLateCharge > 0) {
      // Use locked penalty amount (already paid/approved)
      penalty = lockedLateCharge;
      // Calculate overdue hours from locked penalty to ensure consistency
      // Penalty = (pricePerHour / 60) * overdueMinutes * 1.0
      // Therefore: overdueMinutes = penalty / (pricePerHour / 60) = penalty * 60 / pricePerHour
      if (pricePerHour > 0) {
        final overdueMinutesFromPenalty = (penalty * 60.0 / pricePerHour).round();
        overdueHours = (overdueMinutesFromPenalty / 60.0).ceil();
      }
    } else if (paymentStatus == 'return_requested') {
      // Return requested but no late_charge - should not happen, but calculate as 0
      penalty = 0;
      overdueHours = 0;
    } else {
      // Only calculate penalty if no locked late_charge exists and return is not requested
      // Calculate penalty if overdue (expected_return_date vs now) - per minute for accuracy
      if (widget.rental['expected_return_date'] != null) {
        final expectedDate = DateTime.parse(widget.rental['expected_return_date']);
        final now = DateTime.now();
        if (now.isAfter(expectedDate)) {
          final overdueMinutes = now.difference(expectedDate).inMinutes;
          overdueHours = (overdueMinutes / 60).ceil();
          // Calculate penalty per minute: 100% of hourly rate per minute overdue
          // This ensures owner doesn't lose money - renter pays full rate for overtime use
          final pricePerMinute = pricePerHour / 60.0;
          penalty = pricePerMinute * overdueMinutes * 1.0; // 100% penalty per minute (full rate)
        }
      }
    }

    setState(() {
      _paymentBreakdown = PaymentBreakdown(
        baseRent: baseRent,
        penalty: penalty,
        total: baseRent + penalty,
        rentalDays: rentalHours, // Using rentalDays field for hours
        overdueDays: overdueHours, // Using overdueDays field for overdue hours
        pricePerDay: pricePerHour, // Using pricePerDay field for price per hour
      );
    });
  }

  Future<void> _processReturn() async {
    if (_paymentBreakdown == null) return;

    setState(() => _isProcessing = true);

    try {
      // First, persist late charge to rental (owner will collect/track as needed)
      if (_paymentBreakdown!.penalty > 0) {
        await SupabaseService.client
            .from('rentals')
            .update({
              'late_charge': _paymentBreakdown!.penalty,
            })
            .eq('id', widget.rental['id']);
      }

      // Then mark rental as returned and free the product
      await SupabaseService().markRentalAsReturned(rentalId: widget.rental['id']);

      // Clear any pending return request/payment flags so UI updates immediately
      await SupabaseService.client
          .from('rentals')
          .update({
            'payment_status': 'completed',
          })
          .eq('id', widget.rental['id']);

      if (mounted) {
        Navigator.pop(context);
        // Add a small delay to ensure database updates are committed
        await Future.delayed(const Duration(milliseconds: 500));
        widget.onReturnComplete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _paymentBreakdown!.penalty > 0
                  ? 'Return processed successfully! Penalty of ₹${_paymentBreakdown!.penalty.toStringAsFixed(2)} has been applied.'
                  : 'Return processed successfully!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process return: $e')),
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
    if (_paymentBreakdown == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final product = widget.rental['products'];
    final isOverdue = _paymentBreakdown!.overdueDays > 0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
                  'Process Return',
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
                  // Product and Renter Info
                  _buildInfoCard(product),
                  const SizedBox(height: 24),
                  
                  // Payment Breakdown
                  _buildPaymentBreakdown(),
                  const SizedBox(height: 24),
                  
                  // Overdue Warning
                  if (isOverdue) _buildOverdueWarning(),
                  if (isOverdue) const SizedBox(height: 24),
                  
                  // Return Instructions
                  _buildReturnInstructions(),
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
                onPressed: _isProcessing ? null : _processReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOverdue ? const Color(0xFFDC2626) : const Color(0xFF10B981),
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
                        isOverdue 
                            ? 'Process Return with Penalty'
                            : 'Process Return',
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

  Widget _buildInfoCard(Map<String, dynamic> product) {
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
                      product['name'] ?? 'Product',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111),
                      ),
                    ),
                    Text(
                      'Renter: ${widget.rental['renter_name'] ?? widget.rental['renter_id'] ?? 'Unknown'}',
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
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Breakdown',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 16),
          // Base rent with status
          _buildStatusAmountRow(
            label: 'Base Rent (${_paymentBreakdown!.rentalDays} hours)',
            amount: _paymentBreakdown!.baseRent,
            status: _isBaseRentPaid() ? 'Paid' : 'Unpaid',
            statusColor: _isBaseRentPaid() ? const Color(0xFF10B981) : const Color(0xFFDC2626),
          ),
          const SizedBox(height: 8),
          // Penalty always shown (0 if none)
          _buildStatusAmountRow(
            label: 'Late Penalty (${_paymentBreakdown!.overdueDays} hours)',
            amount: _paymentBreakdown!.penalty,
            status: _penaltyStatusLabel(),
            statusColor: _penaltyStatusColor(),
            isPenalty: true,
          ),
          const Divider(height: 24),
          _buildAmountRow('Total Amount', _paymentBreakdown!.total, isTotal: true),
        ],
      ),
    );
  }

  bool _isBaseRentPaid() {
    final status = widget.rental['payment_status'];
    if (status == 'paid' || status == 'completed') return true;
    if (widget.rental['amount'] != null) return true; // amount recorded on rental
    return false;
  }

  String _penaltyStatusLabel() {
    if (_paymentBreakdown!.penalty <= 0) return 'No penalty';
    final paymentStatus = (widget.rental['payment_status'] ?? '').toString();
    // If return is requested, penalty must be paid (return can only be requested after all dues cleared)
    if (paymentStatus == 'return_requested') return 'Paid';
    final late = widget.rental['late_charge'];
    if (late is num && late.toDouble() == 0) return 'Paid';
    // Check if penalty payment has been approved via latest_payment
    final latestPayment = widget.rental['latest_payment'];
    if (latestPayment != null) {
      final latestStatus = (latestPayment['status'] ?? '').toString();
      if (latestStatus == 'paid' || latestStatus == 'approved') {
        final latestAmount = latestPayment['amount'] != null 
            ? (latestPayment['amount'] as num).toDouble() 
            : 0.0;
        if (latestAmount > 0 && latestAmount >= _paymentBreakdown!.penalty * 0.9) {
          return 'Paid'; // Payment amount matches or is close to penalty
        }
      }
    }
    return 'Unpaid';
  }

  Color _penaltyStatusColor() {
    if (_paymentBreakdown!.penalty <= 0) return const Color(0xFF6B7280);
    final paymentStatus = (widget.rental['payment_status'] ?? '').toString();
    // If return is requested, penalty must be paid (return can only be requested after all dues cleared)
    if (paymentStatus == 'return_requested') return const Color(0xFF10B981);
    final late = widget.rental['late_charge'];
    if (late is num && late.toDouble() == 0) return const Color(0xFF10B981);
    // Check if penalty payment has been approved via latest_payment
    final latestPayment = widget.rental['latest_payment'];
    if (latestPayment != null) {
      final latestStatus = (latestPayment['status'] ?? '').toString();
      if (latestStatus == 'paid' || latestStatus == 'approved') {
        final latestAmount = latestPayment['amount'] != null 
            ? (latestPayment['amount'] as num).toDouble() 
            : 0.0;
        if (latestAmount > 0 && latestAmount >= _paymentBreakdown!.penalty * 0.9) {
          return const Color(0xFF10B981); // Payment amount matches or is close to penalty
        }
      }
    }
    return const Color(0xFFDC2626);
  }

  Widget _buildStatusAmountRow({
    required String label,
    required double amount,
    required String status,
    required Color statusColor,
    bool isPenalty = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: (isPenalty && statusColor == const Color(0xFF10B981)) 
                      ? const Color(0xFF10B981) 
                      : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
            ],
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: (isPenalty && statusColor == const Color(0xFF10B981)) 
                ? const Color(0xFF10B981) 
                : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111)),
          ),
        ),
      ],
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

  Widget _buildOverdueWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: const Color(0xFFDC2626), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overdue Return',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _paymentBreakdown!.penalty > 0
                      ? 'This product is ${_paymentBreakdown!.overdueDays} hour(s) overdue. A penalty of ₹${_paymentBreakdown!.penalty.toStringAsFixed(2)} ${widget.rental['late_charge'] != null && (widget.rental['late_charge'] as num).toDouble() > 0 ? "has been applied." : "will be applied."}'
                      : 'No penalty is due for this return.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: const Color(0xFF007BFF), size: 20),
              const SizedBox(width: 12),
              const Text(
                'Return Instructions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF007BFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Verify the product is in good condition\n'
            '2. Check for any damages or missing parts\n'
            '3. Confirm the return with the renter\n'
            '4. Process the return to update product availability',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF1E40AF),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
