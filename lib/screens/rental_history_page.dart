// File: lib/screens/rental_history_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/screens/rental_management_page.dart';
import 'dart:async';

class RentalHistoryPage extends StatefulWidget {
  const RentalHistoryPage({super.key});

  @override
  State<RentalHistoryPage> createState() => _RentalHistoryPageState();
}

class _RentalHistoryPageState extends State<RentalHistoryPage> {
  List<Map<String, dynamic>> _rentedItems = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0 for Active, 1 for Completed
  Set<String> _expandedPaymentIds = {}; // Track which rental's payment details are expanded
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchRentalData();
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _fetchRentalData() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Fetch rentals where the user is renter (only show rentals with payments or completed status)
      final rentedData = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('renter_id', userId)
          .order('rented_at', ascending: false);

      List<Map<String, dynamic>> updatedRented = [];

      // Fetch owner profile and payment records for each rental
      for (var rental in rentedData) {
        final ownerId = rental['user_id']; // owner_id in rentals
        final ownerProfile = await SupabaseService.client
            .from('profiles')
            .select()
            .eq('id', ownerId)
            .maybeSingle(); // returns Map<String,dynamic>? or null

        rental['owner'] = ownerProfile;
        
        // Fetch payment records for this rental
        try {
          final payments = await SupabaseService.client
              .from('payments')
              .select('*')
              .eq('rental_id', rental['id'])
              .order('paid_at', ascending: false)
              .limit(1);
          
          if (payments.isNotEmpty) {
            final latestPayment = payments[0];
            rental['latest_payment'] = latestPayment;
            rental['payment_method_latest'] = latestPayment['method'];
            rental['payment_amount'] = latestPayment['amount'];
            rental['payment_date'] = latestPayment['paid_at'];
            rental['transaction_id'] = latestPayment['transaction_id'] ?? rental['transaction_id'];
          }
        } catch (e) {
          debugPrint('Error loading payment for rental ${rental['id']}: $e');
        }
        
        // Only add rentals that have payments or are completed/active (not pending without payment)
        final hasPayment = rental['latest_payment'] != null || 
                          rental['amount'] != null || 
                          rental['amount_paid'] != null ||
                          rental['payment_status'] == 'submitted' ||
                          rental['payment_status'] == 'paid' ||
                          rental['payment_status'] == 'completed';
        
        final isCompleted = rental['status'] == 'completed' || rental['returned_at'] != null;
        final isActive = rental['status'] == 'active' && rental['rented_at'] != null;
        
        if (hasPayment || isCompleted || isActive) {
          updatedRented.add(Map<String, dynamic>.from(rental));
        }
      }

      setState(() {
        _rentedItems = updatedRented;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching rental data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load rental history.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _activeRentals {
    return _rentedItems.where((rental) {
      final status = rental['status'];
      final paymentStatus = rental['payment_status'];
      final returnedAt = rental['returned_at'];
      
      // Exclude completed/cancelled
      if (status == 'completed' || status == 'cancelled') {
        return false;
      }
      
      // Exclude if payment is completed AND item is returned (these are in history)
      if (paymentStatus == 'completed' && returnedAt != null) {
        return false;
      }
      
      // Include active, awaiting_payment, pending_confirmation
      return status == 'active' || 
             status == 'awaiting_payment' ||
             status == 'pending_confirmation';
    }).toList();
  }

  List<Map<String, dynamic>> get _completedRentals {
    return _rentedItems.where((rental) {
      final status = rental['status'];
      final paymentStatus = rental['payment_status'];
      final returnedAt = rental['returned_at'];
      
      // Include if status is completed or cancelled
      if (status == 'completed' || status == 'cancelled') {
        return true;
      }
      
      // Also include if payment is completed AND item is returned (even if status is active)
      if (paymentStatus == 'completed' && returnedAt != null) {
        return true;
      }
      
      return false;
    }).toList();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Not available';
    final normalized = dateStr.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
    final date = DateTime.tryParse(normalized);
    if (date == null) return 'Not available';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // Parse a timestamp string as LOCAL time, ignoring any trailing timezone suffix like 'Z' or '+00:00'.
  DateTime? _parseLocalIgnoringTimezone(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final normalized = raw.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
    return DateTime.tryParse(normalized);
  }

  Widget _buildInfoChip(String label, String value, IconData icon, {bool isPenalty = false}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPenalty ? const Color(0xFFFEF2F2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPenalty ? const Color(0xFFDC2626).withOpacity(0.3) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isPenalty = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String label, double amount, {bool isPaid = false, bool isPenalty = false, bool isTotal = false}) {
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
              color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
            ),
          ),
          Row(
            children: [
              Text(
                '₹${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: isTotal ? 18 : 14,
                  fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                  color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
                ),
              ),
              if (isPaid && !isTotal)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Paid',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfo(Map<String, dynamic>? user) {
    if (user == null) return const Text('N/A');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Name: ${user['name'] ?? 'N/A'}'),
        Text('Email: ${user['email'] ?? 'N/A'}'),
        Text('Phone: ${user['phone'] ?? 'N/A'}'),
        if (user['state'] != null && user['district'] != null)
          Text(
              'Location: ${user['locality'] ?? ''}, ${user['district']}, ${user['state']}'),
        if (user['pincode'] != null) Text('Pincode: ${user['pincode']}'),
      ],
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental, {bool isCompleted = false}) {
    final product = rental['products'];
    final contactUser = rental['owner']; // fetched from profiles
    final status = rental['status'] ?? 'Unknown';
    final rentalId = rental['id'];
    final isPaymentExpanded = _expandedPaymentIds.contains(rentalId);

    // Use rental_days when present; otherwise calculate from amount_due first (most accurate for pending rentals)
    final pricePerDay = (product?['price'] ?? 0).toDouble();
    int rentalDays = rental['rental_days'] ?? 0;
    
    // If rental_days is not available, try to calculate from amount_due first (most accurate for pending rentals)
    if (rentalDays == 0 && rental['amount_due'] != null && pricePerDay > 0) {
      try {
        final amountDue = (rental['amount_due'] as num).toDouble();
        // Calculate exact days: amount_due / pricePerDay should give us the exact number of days
        // Use round() to handle any floating point precision issues, but prefer exact division
        final calculatedDays = amountDue / pricePerDay;
        // If the division is very close to a whole number, use that; otherwise round
        if ((calculatedDays - calculatedDays.round()).abs() < 0.01) {
          rentalDays = calculatedDays.round();
        } else {
          rentalDays = calculatedDays.round(); // Round to nearest day
        }
      } catch (_) {}
    }
    
    // Fallback to time difference if amount_due calculation didn't work
    if (rentalDays == 0 && rental['expected_return_date'] != null && rental['rented_at'] != null) {
      try {
        final rentedAt = DateTime.parse(rental['rented_at']);
        final expected = DateTime.parse(rental['expected_return_date']);
        final diffDays = expected.difference(rentedAt).inDays;
        rentalDays = diffDays > 0 ? diffDays : 1; // At least 1 day
      } catch (_) {}
    }
    if (rentalDays <= 0) rentalDays = 1;

    DateTime? rentedAt = DateTime.tryParse(rental['rented_at'] ?? '');
    if (status == 'pending_confirmation') {
      rentedAt = null; // Start after owner approval only
    }
    // Use expected_return_date from database if available, otherwise calculate from rented_at
    DateTime? dueDate;
    if (rental['expected_return_date'] != null) {
      try {
        final expectedStr = rental['expected_return_date'].toString();
        final normalized = expectedStr.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
        dueDate = DateTime.tryParse(normalized);
      } catch (_) {}
    }
    // Fallback to calculated date if expected_return_date not available
    if (dueDate == null && rentedAt != null) {
      dueDate = rentedAt.add(Duration(days: rentalDays));
    }
    
    final returnedAt = rental['returned_at'] != null ? DateTime.tryParse(rental['returned_at']) : null;
    final paidAt = rental['paid_at'] != null ? DateTime.tryParse(rental['paid_at']) : null;

    final now = DateTime.now();
    int overdueDays = 0; // display as days
    int daysUntilDue = 0; // day precision for warnings
    int minutesUntilDue = 0; // minutes precision for "due soon" alert (30 min threshold)
    
    // Calculate penalty using same logic as rental_management_page
    double penalty = 0.0;
    bool lockPenalty = false;
    final String paymentStatus = (rental['payment_status'] ?? '').toString();
    final double? lockedLateCharge = (rental['late_charge'] as num?)?.toDouble();
    
    // Check if penalty payment has been approved
    final bool hasLatestPayment = rental['latest_payment'] != null;
    final String? latestPaymentStatus = rental['latest_payment']?['status']?.toString();
    final double? latestPaymentAmount = rental['latest_payment']?['amount'] != null 
        ? (rental['latest_payment']['amount'] as num).toDouble() 
        : null;
    
    // Penalty payment is approved if:
    // 1. late_charge exists (penalty was recorded)
    // 2. AND either:
    //    - payment record status is 'paid' or 'approved', OR
    //    - rental payment_status is 'paid' and late_charge exists (fallback)
    final bool isPenaltyPaymentApproved = lockedLateCharge != null && lockedLateCharge > 0.0 && (
      (hasLatestPayment &&
       (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
       (latestPaymentAmount != null && latestPaymentAmount! > 0)) ||
      (paymentStatus == 'paid' && lockedLateCharge > 0.0)
    );
    
    // NO PENALTY for returned or completed rentals (use late_charge if already paid)
    if (status == 'completed' || returnedAt != null) {
      // If item is returned, use late_charge if it exists (penalty already finalized)
      if (lockedLateCharge != null && lockedLateCharge > 0) {
        penalty = lockedLateCharge;
        // Calculate overdue days from the locked penalty amount to ensure consistency
        // Penalty = pricePerDay * overdueDays * 1.0
        // Therefore: overdueDays = penalty / pricePerDay
        if (pricePerDay > 0) {
          overdueDays = (penalty / pricePerDay).ceil();
        } else {
          // Fallback to time difference if price is not available
          if (dueDate != null && returnedAt != null && returnedAt.isAfter(dueDate)) {
            final overdueDaysCount = returnedAt.difference(dueDate).inDays;
            overdueDays = overdueDaysCount > 0 ? overdueDaysCount : 1;
          }
        }
      } else {
        penalty = 0;
        overdueDays = 0;
      }
    } else {
      // Only calculate penalty for active rentals that haven't been returned
      // ***** POLISHED: lock penalty when payment proof is submitted or rental has late_charge (payment_status = 'submitted' means pending approval, stop penalty growth)
      // Lock if penalty payment submitted by renter (pending approval) or penalty already finalized.
      // Note: Don't lock penalty if it's just the initial rent payment ('paid' status) - only lock when penalty payment is submitted
      if (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment' || (lockedLateCharge != null && lockedLateCharge > 0)) {
        lockPenalty = true;
      }
      try {
        DateTime? expectedDate = _parseLocalIgnoringTimezone(rental['expected_return_date']);
        expectedDate ??= _parseLocalIgnoringTimezone(rental['rented_at'])?.add(Duration(days: rentalDays));
        if (expectedDate != null) {
          DateTime endTime;
          if (lockPenalty && rental['returned_at'] == null) {
            // Use penalty cutoff: payment submission/return requested/locked date
            // Once renter submits penalty payment (status='submitted'), lock penalty at that time
            // It's owner's responsibility to review quickly
            if (rental['return_requested_at'] != null) {
              endTime = _parseLocalIgnoringTimezone(rental['return_requested_at'])!;
            } else if (rental['latest_payment'] != null && 
                       (rental['latest_payment']?['status'] == 'submitted' || 
                        rental['latest_payment']?['status'] == 'awaiting_payment')) {
              // Lock penalty when payment is submitted - owner's fault if they don't review
              endTime = rental['latest_payment']?['paid_at'] != null 
                ? _parseLocalIgnoringTimezone(rental['latest_payment']['paid_at'])!
                : DateTime.now();
            } else {
              endTime = DateTime.now();
            }
          } else {
            // For active overdue rentals, always use current time to calculate penalty
            // Penalty updates daily until payment is submitted
            endTime = DateTime.now();
          }
          if (endTime.isAfter(expectedDate)) {
            final overdueDaysCount = endTime.difference(expectedDate).inDays;
            // Calculate penalty per day: 100% of daily rate per day overdue
            // This ensures owner doesn't lose money - renter pays full rate for overtime use
            // Example: ₹100/day = ₹100/day overdue (full rate)
            // Calculate penalty based on actual days overdue - full daily rate (100%)
            penalty = pricePerDay * overdueDaysCount * 1.0; // 100% penalty per day (full rate)
            // Ensure minimum 1 day is calculated if overdue
            if (penalty > 0 && overdueDaysCount < 1) {
              penalty = pricePerDay * 1 * 1.0;
              overdueDays = 1;
            } else {
              overdueDays = overdueDaysCount;
            }
          }
        }
      } catch (_) {}
      // After payment is submitted or locked, use rental['late_charge'] as fixed penalty everywhere
      if (lockPenalty && lockedLateCharge != null && lockedLateCharge > 0) {
        penalty = lockedLateCharge;
        // Calculate overdue days from the locked penalty amount to ensure consistency
        // Penalty = pricePerDay * overdueDays * 1.0
        // Therefore: overdueDays = penalty / pricePerDay
        if (pricePerDay > 0) {
          overdueDays = (penalty / pricePerDay).ceil();
        }
      }
      
      // Calculate days and minutes until due for warnings
      if (dueDate != null && returnedAt == null && now.isBefore(dueDate)) {
        final timeUntilDue = dueDate.difference(now);
        daysUntilDue = timeUntilDue.inDays;
        minutesUntilDue = timeUntilDue.inMinutes;
      }
    }

    // Determine card color based on status and urgency
    Color cardColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    
    if (isCompleted) {
      if (status == 'completed') {
        cardColor = Colors.green.shade50;
        borderColor = Colors.green.shade200;
      } else if (status == 'cancelled') {
        cardColor = Colors.red.shade50;
        borderColor = Colors.red.shade200;
      }
    } else {
      if (overdueDays > 0) {
        cardColor = Colors.red.shade50;
        borderColor = Colors.red.shade300;
      } else if (minutesUntilDue <= 30 && minutesUntilDue > 0) {
        cardColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade300;
      } else if (daysUntilDue <= 1 && daysUntilDue > 0) {
        cardColor = Colors.yellow.shade50;
        borderColor = Colors.yellow.shade300;
      } else if (daysUntilDue <= 3 && daysUntilDue > 1) {
        cardColor = Colors.yellow.shade50;
        borderColor = Colors.yellow.shade300;
      }
    }

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product?['name'] ?? 'Unknown Product',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _buildStatusBadge(isCompleted ? 'completed' : status, overdueDays, daysUntilDue, minutesUntilDue, isPenaltyPaymentApproved),
                ],
              ),
            const SizedBox(height: 8),
            if (product?['images'] != null &&
                (product['images'] as List).isNotEmpty)
              GestureDetector(
                onTap: () {
                  final images = (product['images'] as List?)?.cast<String>() ?? [];
                  _showFullScreenImage(context, images);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    product['images'][0],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (rentedAt != null)
              Text('Rented on: ${_formatDate(rentedAt.toIso8601String())}')
            else if (status == 'pending_confirmation')
              const Text('Rented on: — (starts on owner approval)'),
            const SizedBox(height: 4),
            if (dueDate != null)
              Text('Due date: ${_formatDate(dueDate.toIso8601String())}')
            else if (status == 'pending_confirmation')
              const Text('Due date: —'),
            const SizedBox(height: 8),
            // Rental duration and pricing info
            // Don't show as "Overdue" if penalty is paid - show as normal details or "Penalty Paid"
            Builder(
              builder: (context) {
                final bool showAsOverdue = overdueDays > 0 && !isPenaltyPaymentApproved;
                final bool showPenaltyPaid = overdueDays > 0 && isPenaltyPaymentApproved;
                return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: showPenaltyPaid ? Colors.green.shade50 : (showAsOverdue ? Colors.red.shade50 : Colors.blue.shade50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: showPenaltyPaid ? Colors.green.shade200 : (showAsOverdue ? Colors.red.shade200 : Colors.blue.shade200),
                  width: (showAsOverdue || showPenaltyPaid) ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        showPenaltyPaid ? Icons.check_circle : (showAsOverdue ? Icons.warning : Icons.access_time),
                        size: 18,
                        color: showPenaltyPaid ? Colors.green : (showAsOverdue ? Colors.red : const Color(0xFF3B82F6)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        showPenaltyPaid ? 'Rental Details (Penalty Paid)' : (showAsOverdue ? 'Rental Details (Overdue)' : 'Rental Details'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: showPenaltyPaid ? Colors.green : (showAsOverdue ? Colors.red : const Color(0xFF3B82F6)),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow('Duration', '${rentalDays} ${rentalDays == 1 ? 'day' : 'days'}'),
                  _buildDetailRow('Price per Day', '₹${pricePerDay.toStringAsFixed(2)}'),
                  _buildDetailRow('Base Rent', '₹${(rentalDays * pricePerDay).toStringAsFixed(2)}'),
                  if (overdueDays > 0) ...[
                    const SizedBox(height: 4),
                    _buildDetailRow('Overtime Days', '$overdueDays ${overdueDays == 1 ? 'day' : 'days'}', isPenalty: !showPenaltyPaid),
                    _buildDetailRow('Penalty', '₹${penalty.toStringAsFixed(2)}', isPenalty: !showPenaltyPaid),
                  ],
                  const Divider(height: 16),
                  _buildDetailRow(
                    'Total Amount',
                    '₹${((rentalDays * pricePerDay) + penalty).toStringAsFixed(2)}',
                    isPenalty: showAsOverdue,
                  ),
                ],
              ),
            );
              },
            ),
              if (isCompleted && rental['returned_at'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Returned on: ${_formatDate(rental['returned_at'])}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            const SizedBox(height: 8),
            
            // Rented from section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person, size: 18, color: Color(0xFF6B7280)),
                      SizedBox(width: 8),
                      Text(
                        'Rented from',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Name: ${contactUser?['name'] ?? 'N/A'}'),
                  Text('Phone: ${contactUser?['phone'] ?? 'N/A'}'),
                  if (contactUser?['email'] != null)
                    Text('Email: ${contactUser['email']}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // Payment info toggle for completed rentals
            if (isCompleted && (rental['payment_status'] == 'completed' || rental['amount'] != null)) ...[
              InkWell(
                onTap: () {
                  setState(() {
                    if (_expandedPaymentIds.contains(rentalId)) {
                      _expandedPaymentIds.remove(rentalId);
                    } else {
                      _expandedPaymentIds.add(rentalId);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.payment, size: 18, color: Color(0xFF3B82F6)),
                          SizedBox(width: 8),
                          Text(
                            'Payment Details',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3B82F6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        isPaymentExpanded ? Icons.expand_less : Icons.expand_more,
                        color: const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                ),
              ),
              if (isPaymentExpanded) ...[
                const SizedBox(height: 8),
                Column(
                  children: [
                    // Amount Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Amount Paid',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 4),
                            ],
                          ),
                          Text(
                            '₹${(rental['amount'] ?? rental['amount_paid'] ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Payment Details Grid
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        // Payment Mode
                        if (rental['payment_method_latest'] != null || rental['payment_method'] != null)
                          _buildInfoChip(
                            'Payment Mode',
                            (rental['payment_method_latest'] ?? rental['payment_method']).toString().toUpperCase(),
                            Icons.account_balance_wallet,
                          ),
                        // Paid Date
                        if (paidAt != null)
                          _buildInfoChip(
                            'Paid on',
                            _formatDate(paidAt.toString()),
                            Icons.calendar_today,
                          ),
                        // Returned Date
                        if (returnedAt != null)
                          _buildInfoChip(
                            'Returned on',
                            _formatDate(returnedAt.toString()),
                            Icons.check_circle,
                          ),
                        // Base Rent Status
                        _buildInfoChip(
                          'Base Rent',
                          'Paid',
                          Icons.check_circle,
                        ),
                        // Late Fee Status
                        if (rental['late_charge'] != null && (rental['late_charge'] as num).toDouble() > 0)
                          _buildInfoChip(
                            'Late Fee',
                            'Paid',
                            Icons.check_circle,
                          )
                        else if (rental['late_charge'] != null && (rental['late_charge'] as num).toDouble() == 0)
                          _buildInfoChip(
                            'Late Fee',
                            'No Fee',
                            Icons.check_circle,
                          ),
                      ],
                    ),
                    
                    // Payment Breakdown with Status
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.receipt_long, size: 18, color: Color(0xFF6B7280)),
                              SizedBox(width: 8),
                              Text(
                                'Payment Breakdown',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPaymentRow('Base Rent (${rentalDays} ${rentalDays == 1 ? 'day' : 'days'})', (rentalDays * pricePerDay).toDouble(), isPaid: true),
                          // Show penalty/overdue details if exists
                          if (overdueDays > 0 && penalty > 0) ...[
                            _buildDetailRow('Overtime Days', '$overdueDays ${overdueDays == 1 ? 'day' : 'days'}', isPenalty: true),
                          ],
                          if (rental['late_charge'] != null && (rental['late_charge'] as num).toDouble() > 0)
                            _buildPaymentRow('Late Fee (Penalty)', (rental['late_charge'] as num).toDouble(), isPaid: true, isPenalty: true)
                          else if (penalty > 0)
                            _buildPaymentRow('Late Fee (Penalty)', penalty, isPaid: true, isPenalty: true)
                          else
                            _buildPaymentRow('Late Fee (Penalty)', 0.0, isPaid: true, isPenalty: true),
                          const Divider(height: 16),
                          Builder(
                            builder: (context) {
                              // Total should include both base rent and penalty
                              final double totalPaid = (rental['amount'] ?? rental['amount_paid'] ?? 0).toDouble();
                              final double calculatedTotal = (rentalDays * pricePerDay) + (penalty > 0 ? penalty : ((rental['late_charge'] as num?)?.toDouble() ?? 0.0));
                              return _buildPaymentRow('Total Paid', totalPaid > 0 ? totalPaid : calculatedTotal, isTotal: true);
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // Transaction ID (show renter-entered value only)
                    if ((rental['latest_payment']?['transaction_id'] ?? rental['transaction_id']) != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.receipt, size: 16, color: Color(0xFF6B7280)),
                                const SizedBox(width: 6),
                                const Text(
                                  'Transaction ID',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              (rental['latest_payment']?['transaction_id'] ?? rental['transaction_id']).toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF111111),
                                fontFamily: 'monospace',
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
              
              // Urgency warnings for active rentals with color-coded notifications
              if (!isCompleted && rentedAt != null) ...[
                if (overdueDays > 0) ...[
                  // Check if penalty is paid and approved - show different message
                  if (isPenaltyPaymentApproved) ...[
                    // Penalty Paid - GREEN (Approved)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.shade300,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF10B981),
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Penalty Paid - Rental Period Over',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Penalty Amount Paid:',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '₹${penalty.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Penalty payment has been approved. Please return the product to complete the rental.',
                            style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Overdue - RED/ORANGE (High Priority or Under Review)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: lockPenalty ? Colors.orange.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: lockPenalty ? Colors.orange.shade300 : Colors.red.shade300,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                lockPenalty ? Icons.pending_actions : Icons.warning_amber_rounded,
                                color: lockPenalty ? Colors.orange.shade700 : Colors.red.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  lockPenalty
                                      ? 'OVERDUE: $overdueDays ${overdueDays == 1 ? 'day' : 'days'} late (Penalty Payment Under Review)'
                                      : 'OVERDUE: $overdueDays ${overdueDays == 1 ? 'day' : 'days'} late',
                                  style: TextStyle(
                                    color: lockPenalty ? Colors.orange.shade700 : Colors.red.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: lockPenalty ? Colors.orange.shade200 : Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  lockPenalty ? 'Penalty Amount (Locked):' : 'Accumulating Penalty:',
                                  style: TextStyle(
                                    color: lockPenalty ? Colors.orange : Colors.red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '₹${penalty.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: lockPenalty ? Colors.orange.shade700 : Colors.red.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lockPenalty
                                ? 'Penalty payment is under review. Amount locked at ₹${penalty.toStringAsFixed(2)}. Waiting for owner approval.'
                                : 'Penalty increases every minute until you return the item. Return immediately!',
                            style: TextStyle(
                              color: lockPenalty ? Colors.orange.shade600 : Colors.red.shade600,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else if (minutesUntilDue <= 30 && minutesUntilDue > 0) ...[
                  // 30 minutes or less - ORANGE (Critical Warning)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade300, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.notifications_active, color: Colors.orange.shade700, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                minutesUntilDue <= 5
                                    ? 'DUE IN ${minutesUntilDue} MINUTES!'
                                    : 'Due in ${minutesUntilDue} minutes',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer_off, color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Return now to avoid penalty charges!',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (daysUntilDue == 1) ...[
                  // 1 hour or less - YELLOW (Warning)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.yellow.shade300, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, color: Colors.orange.shade700, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Due in 1 day',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Plan to return soon to avoid penalties',
                                style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (daysUntilDue <= 3 && daysUntilDue > 1) ...[
                  // 3 days or less - LIGHT YELLOW (Reminder)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Due in $daysUntilDue ${daysUntilDue == 1 ? 'day' : 'days'}. Plan your return.',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            const SizedBox(height: 8),
              ],
              
              // View in Rental Management button for active rentals
              if (!isCompleted && status == 'active')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RentalManagementPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Manage in Rental Management'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, int overdueDays, int daysUntilDue, int minutesUntilDue, bool isPenaltyPaymentApproved) {
    Color color;
    String text;
    IconData icon;
    
    switch (status) {
      case 'completed':
        color = Colors.green;
        text = 'Completed';
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        color = Colors.red;
        text = 'Cancelled';
        icon = Icons.cancel;
        break;
      case 'active':
        // Check if penalty is paid - show different status
        if (overdueDays > 0 && isPenaltyPaymentApproved) {
          color = Colors.green;
          text = 'Penalty Paid';
          icon = Icons.check_circle;
        } else if (overdueDays > 0) {
          color = Colors.red;
          text = 'Overdue';
          icon = Icons.warning;
        } else if (minutesUntilDue <= 30 && minutesUntilDue > 0) {
          color = Colors.orange;
          text = 'Due Soon';
          icon = Icons.schedule;
        } else {
          color = Colors.blue;
          text = 'Active';
          icon = Icons.inventory;
        }
        break;
      case 'awaiting_payment':
        color = Colors.amber;
        text = 'Awaiting Payment';
        icon = Icons.payment;
        break;
      case 'pending_confirmation':
        color = Colors.orange;
        text = 'Pending';
        icon = Icons.hourglass_empty;
        break;
      default:
        color = Colors.grey;
        text = status;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental History'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111111),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tab Buttons
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          title: 'Active Rentals',
                          icon: Icons.inventory,
                          iconColor: const Color(0xFF007BFF),
                          isSelected: _selectedTabIndex == 0,
                          count: _activeRentals.length,
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 0;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          title: 'Completed Rentals',
                          icon: Icons.history,
                          iconColor: const Color(0xFF10B981),
                          isSelected: _selectedTabIndex == 1,
                          count: _completedRentals.length,
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 1;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Content based on selected tab
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchRentalData,
                    child: _rentedItems.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No rentals found.',
                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: _selectedTabIndex == 0
                                ? _buildActiveContent()
                                : _buildCompletedContent(),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? iconColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? iconColor : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? iconColor : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? iconColor : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveContent() {
    if (_activeRentals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No active rentals.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ..._activeRentals.map((rental) => _buildRentalCard(rental, isCompleted: false)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCompletedContent() {
    if (_completedRentals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No completed rentals.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ..._completedRentals.map((rental) => _buildRentalCard(rental, isCompleted: true)),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full screen image viewer with PageView for multiple images
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: PageView.builder(
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return Center(
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.error, color: Colors.white, size: 48),
                    ),
                  );
                },
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  shape: const CircleBorder(),
                ),
              ),
            ),
            // Image indicator if multiple images
            if (images.length > 1)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Swipe to view all ${images.length} images',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
