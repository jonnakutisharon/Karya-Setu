import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/screens/payment_dashboard.dart';
import 'package:rental_app/screens/rental_return_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:rental_app/models/payment_model.dart';

class RentalManagementPage extends StatefulWidget {
  const RentalManagementPage({super.key});

  @override
  State<RentalManagementPage> createState() => _RentalManagementPageState();
}

class _RentalManagementPageState extends State<RentalManagementPage> {
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0 for Owner, 1 for Renter
  List<Map<String, dynamic>> _activeRentals = [];
  List<Map<String, dynamic>> _pendingRentals = [];
  List<Map<String, dynamic>> _completedRentals = [];
  List<Map<String, dynamic>> _completedRentalsAsRenter = []; // Completed rentals where user is renter
  Set<String> _expandedPaymentIds = {}; // Track which rental's payment details are expanded
  final SupabaseService _supabase = SupabaseService();
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRentals();
    _cleanupDatabase();
    // Update penalty every minute for overdue rentals
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {
          // Force recalculation of penalties for overdue rentals
        });
      }
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _cleanupDatabase() async {
    try {
      await SupabaseService().forceCleanupRentedProducts();
      print('Database cleanup completed');
    } catch (e) {
      print('Error during database cleanup: $e');
    }
  }

  Future<void> _loadRentals() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    try {
        // Load active rentals (as owner) - exclude completed rentals, cancelled rentals, and those with returned_at
      final activeRentals = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('user_id', userId)
            .inFilter('status', ['pending_confirmation', 'active', 'awaiting_payment', 'overdue'])
            .not('status', 'eq', 'cancelled') // Exclude cancelled rentals
            .isFilter('returned_at', null) // Exclude rentals that have been returned
          .order('rented_at', ascending: false);

      print('Active rentals count: ${activeRentals.length}');
      for (var rental in activeRentals) {
        print('Active rental: ${rental['id']} - status: ${rental['status']}, returned_at: ${rental['returned_at']}');
      }

      // Load pending rentals (as renter) - exclude completed rentals, cancelled rentals, and those with returned_at
      final pendingRentals = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('renter_id', userId)
          .inFilter('status', ['pending_confirmation', 'active', 'awaiting_payment', 'overdue'])
          .not('status', 'eq', 'cancelled') // Exclude cancelled rentals
          .isFilter('returned_at', null) // Exclude rentals that have been returned
          .order('rented_at', ascending: false);

      // Load completed rentals separately (as owner) - include both status='completed' and returned_at is not null
      final completedRentalsAsOwner = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('user_id', userId)
          .or('status.eq.completed,returned_at.not.is.null')
          .order('rented_at', ascending: false);

      // Load completed rentals separately (as renter) - include both status='completed' and returned_at is not null
      final completedRentalsAsRenter = await SupabaseService.client
          .from('rentals')
          .select('*, products(*)')
          .eq('renter_id', userId)
          .or('status.eq.completed,returned_at.not.is.null')
          .order('rented_at', ascending: false);

      // Load payment records for each group
      final activeWithPayments = await _loadPaymentRecords(activeRentals);
      final pendingWithPayments = await _loadPaymentRecords(pendingRentals);
      final completedWithPaymentsAsOwner = await _loadPaymentRecords(completedRentalsAsOwner);
      final completedWithPaymentsAsRenter = await _loadPaymentRecords(completedRentalsAsRenter);

      // Collect all unique renter/owner ids to fetch profile names once
      final Set<String> allUserIds = {
        ...activeWithPayments.map((r) => (r['renter_id'] ?? '').toString()),
        ...activeWithPayments.map((r) => (r['user_id'] ?? '').toString()),
        ...pendingWithPayments.map((r) => (r['renter_id'] ?? '').toString()),
        ...pendingWithPayments.map((r) => (r['user_id'] ?? '').toString()),
        ...completedWithPaymentsAsOwner.map((r) => (r['renter_id'] ?? '').toString()),
        ...completedWithPaymentsAsOwner.map((r) => (r['user_id'] ?? '').toString()),
        ...completedWithPaymentsAsRenter.map((r) => (r['renter_id'] ?? '').toString()),
        ...completedWithPaymentsAsRenter.map((r) => (r['user_id'] ?? '').toString()),
      }..removeWhere((e) => e.isEmpty);

      Map<String, String> idToName = {};
      if (allUserIds.isNotEmpty) {
        try {
          final profiles = await SupabaseService.client
              .from('profiles')
              .select('id, name')
              .inFilter('id', allUserIds.toList());
          for (final p in profiles) {
            final id = (p['id'] ?? '').toString();
            final name = (p['name'] ?? '').toString();
            if (id.isNotEmpty && name.isNotEmpty) {
              idToName[id] = name;
            }
          }
        } catch (_) {}
      }

      // Attach readable names to each rental record for UI clarity
      void attachNames(List<Map<String, dynamic>> list) {
        for (final r in list) {
          final renterId = (r['renter_id'] ?? '').toString();
          final ownerId = (r['user_id'] ?? '').toString();
          if (renterId.isNotEmpty && idToName.containsKey(renterId)) {
            r['renter_name'] = idToName[renterId];
          }
          if (ownerId.isNotEmpty && idToName.containsKey(ownerId)) {
            r['owner_name'] = idToName[ownerId];
          }
        }
      }

      attachNames(activeWithPayments);
      attachNames(pendingWithPayments);
      attachNames(completedWithPaymentsAsOwner);
      attachNames(completedWithPaymentsAsRenter);

      // Filter renter pending list to only show after payment submitted/approved
      // Renter should see ALL pending rentals to allow completion or cancellation
      final filteredPendingForRenter = pendingWithPayments;

      if (mounted) {
        setState(() {
          _activeRentals = activeWithPayments;
          _pendingRentals = filteredPendingForRenter;
          _completedRentals = completedWithPaymentsAsOwner;
          _completedRentalsAsRenter = completedWithPaymentsAsRenter;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rentals: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadPaymentRecords(List<Map<String, dynamic>> rentals) async {
    final updatedRentals = <Map<String, dynamic>>[];
    
    for (var rental in rentals) {
      try {
        // Prefer linked payment_id; otherwise get latest by rental_id regardless of status
        Map<String, dynamic>? latestPayment;
        if (rental['payment_id'] != null) {
          latestPayment = await SupabaseService.client
              .from('payments')
              .select('*')
              .eq('id', rental['payment_id'])
              .maybeSingle();
        }
        if (latestPayment == null) {
          // Get the most recent payment by created_at (not paid_at, as penalty payments might not have paid_at yet)
          final list = await SupabaseService.client
            .from('payments')
            .select('*')
            .eq('rental_id', rental['id'])
            .order('created_at', ascending: false)
              .limit(1);
          if (list is List && list.isNotEmpty) {
            latestPayment = Map<String, dynamic>.from(list.first);
          }
        }

        if (latestPayment != null) {
          rental['latest_payment'] = latestPayment;
          
          // Also copy payment data to rental for easy access
          rental['payment_amount'] = latestPayment['amount'];
          rental['payment_method_latest'] = latestPayment['method'];
          rental['payment_date'] = latestPayment['paid_at'];
          rental['transaction_id'] = latestPayment['transaction_id'] ?? rental['transaction_id'];
          rental['payment_screenshot'] = latestPayment['receipt_url'] ?? rental['payment_screenshot'];
          
          debugPrint('Loaded payment for rental ${rental['id']}: ${latestPayment['id']}, amount: ${latestPayment['amount']}, status: ${latestPayment['status']}, method: ${latestPayment['method']}');
          // Also populate fields from payment record if not in rental
          // Keep existing fallbacks minimal — prefer explicit fields
        } else {
          debugPrint('No payments found for rental ${rental['id']}');
        }
      } catch (e) {
        debugPrint('Error loading payment for rental ${rental['id']}: $e');
      }
      updatedRentals.add(rental);
    }
    
    return updatedRentals;
  }

  // Parse a timestamp string as LOCAL time, ignoring any trailing timezone suffix like 'Z' or '+00:00'.
  DateTime? _parseLocalIgnoringTimezone(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final normalized = raw.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
    return DateTime.tryParse(normalized);
  }

  PaymentBreakdown _calculatePaymentBreakdown(Map<String, dynamic> rental) {
    final product = rental['products'];
    final pricePerHour = (product['price'] ?? 0).toDouble();
    int rentalHours = rental['rental_days'] ?? 0; // Using rental_days field for hours when set
    if (rentalHours == 0) {
      try {
        final rentedAt = _parseLocalIgnoringTimezone(rental['rented_at']);
        final expected = _parseLocalIgnoringTimezone(rental['expected_return_date']);
        if (rentedAt != null && expected != null) {
          final diffMinutes = expected.difference(rentedAt).inMinutes;
          rentalHours = (diffMinutes / 60).ceil();
        }
      } catch (_) {}
    }
    if (rentalHours <= 0) rentalHours = 1;
    final baseRent = pricePerHour * rentalHours;

    // Calculate penalty if overdue
    double penalty = 0;
    int overdueHours = 0; // expose as hours, but compute by minutes for accuracy
    bool lockPenalty = false; // Declare at method level for debug print
    
    // Get late_charge early for use in both returned and active rental logic
    final double? lockedLateCharge = (rental['late_charge'] as num?)?.toDouble();
    
    // Handle returned or completed rentals - use late_charge if exists
    final String rentalStatus = (rental['status'] ?? '').toString();
    final returnedAt = rental['returned_at'];
    if (rentalStatus == 'completed' || returnedAt != null) {
      // Item is returned or completed - use late_charge if it exists (penalty already finalized)
      // IMPORTANT: Always use locked late_charge to calculate overdue hours to maintain consistency
      // from return request time to completion. Do NOT recalculate from returned_at date.
      if (lockedLateCharge != null && lockedLateCharge > 0) {
        penalty = lockedLateCharge;
        // Calculate overdue hours from the locked penalty amount to ensure consistency
        // This ensures overtime hours remain the same from return request to completion
        // Penalty = (pricePerHour / 60) * overdueMinutes * 1.0
        // Therefore: overdueMinutes = penalty / (pricePerHour / 60) = penalty * 60 / pricePerHour
        if (pricePerHour > 0) {
          final overdueMinutesFromPenalty = (penalty * 60.0 / pricePerHour).round();
          overdueHours = (overdueMinutesFromPenalty / 60.0).ceil();
        } else {
          // Only use time difference fallback if price is not available AND late_charge exists
          // But prefer to keep overdue hours at 0 if we can't calculate from penalty
          // This ensures consistency - if we have late_charge, we should have price too
          overdueHours = 0;
        }
      } else {
        // No late_charge means no penalty was applied
        penalty = 0;
        overdueHours = 0;
      }
    } else {
      // Only calculate penalty for active rentals that haven't been returned
    // ***** POLISHED: lock penalty when payment proof is submitted or rental has late_charge (payment_status = 'submitted' means pending approval, stop penalty growth)
    final String paymentStatus = (rental['payment_status'] ?? '').toString();
      // Lock if penalty payment submitted by renter (pending approval) or penalty already finalized.
      // Note: Don't lock penalty if it's just the initial rent payment ('paid' status) - only lock when penalty payment is submitted
      if (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment' || (lockedLateCharge != null && lockedLateCharge > 0)) {
      lockPenalty = true;
    }
    try {
      DateTime? expectedDate = _parseLocalIgnoringTimezone(rental['expected_return_date']);
      expectedDate ??= _parseLocalIgnoringTimezone(rental['rented_at'])?.add(Duration(hours: rentalHours));
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
          // Penalty updates every minute until payment is submitted
          endTime = DateTime.now();
        }
        if (endTime.isAfter(expectedDate)) {
          final overdueMinutes = endTime.difference(expectedDate).inMinutes;
          // Calculate penalty per minute: 100% of hourly rate per minute overdue
          // This ensures owner doesn't lose money - renter pays full rate for overtime use
          // Example: ₹30/hour = ₹0.50/min, penalty = ₹0.50/min overdue (full rate)
          final pricePerMinute = pricePerHour / 60.0;
          // Calculate penalty based on actual minutes overdue - full hourly rate (100%)
          penalty = pricePerMinute * overdueMinutes * 1.0; // 100% penalty per minute (full rate)
          // Ensure minimum 1 minute is calculated if overdue
          if (penalty > 0 && overdueMinutes < 1) {
            penalty = pricePerMinute * 1 * 1.0;
          }
          // Display overdue hours (rounded up for display, but penalty is based on exact minutes)
          overdueHours = (overdueMinutes / 60).ceil();
        }
      }
    } catch (_) {}
    // After payment is submitted or locked, use rental['late_charge'] as fixed penalty everywhere
    if (lockPenalty && lockedLateCharge != null && lockedLateCharge > 0) {
      penalty = lockedLateCharge;
        // Calculate overdue hours from the locked penalty amount to ensure consistency
        // Penalty = (pricePerHour / 60) * overdueMinutes * 1.0
        // Therefore: overdueMinutes = penalty / (pricePerHour / 60) = penalty * 60 / pricePerHour
        if (pricePerHour > 0) {
          final overdueMinutesFromPenalty = (penalty * 60.0 / pricePerHour).round();
          overdueHours = (overdueMinutesFromPenalty / 60.0).ceil();
        }
      }
    }
    debugPrint('[PenaltyCalc-polished] rental ${rental['id']}: hours=$rentalHours base=$baseRent penalty=$penalty overdueHours=$overdueHours lockPenalty=$lockPenalty');

    return PaymentBreakdown(
      baseRent: baseRent,
      penalty: penalty,
      total: baseRent + penalty,
      rentalDays: rentalHours, // Using rentalDays field for hours
      overdueDays: overdueHours, // Using overdueDays field for overdue hours
      pricePerDay: pricePerHour, // Using pricePerDay field for price per hour
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'Not available';
    final date = _parseLocalIgnoringTimezone(dateStr);
    if (date == null) return 'Not available';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Rental Management'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111111),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _cleanupDatabase();
              await _loadRentals();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Database cleaned up and refreshed')),
                );
              }
            },
            tooltip: 'Cleanup & Refresh',
          ),
        ],
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
                          title: 'As Owner',
                          icon: Icons.business,
                          iconColor: const Color(0xFF007BFF),
                          isSelected: _selectedTabIndex == 0,
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 0;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          title: 'As Renter',
                          icon: Icons.shopping_cart,
                          iconColor: const Color(0xFF10B981),
                          isSelected: _selectedTabIndex == 1,
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _selectedTabIndex == 0
                        ? _buildOwnerContent()
                        : _buildRenterContent(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSection(
          title: 'My Active Rentals',
          rentals: _activeRentals,
          isOwner: true,
        ),
        if (_completedRentals.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSection(
            title: 'Completed Rentals',
            rentals: _completedRentals,
            isOwner: true,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRenterContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSection(
          title: 'My Pending Rentals',
          rentals: _pendingRentals,
          isOwner: false,
        ),
        if (_completedRentalsAsRenter.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSection(
            title: 'Completed Rentals',
            rentals: _completedRentalsAsRenter,
            isOwner: false,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> rentals,
    required bool isOwner,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 16),
        if (rentals.isEmpty)
          Container(
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
                    Icons.inventory_2_outlined,
                    color: Color(0xFF6B7280),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isOwner 
                      ? (title.contains('Completed') ? 'No Completed Rentals' : 'No Active Rentals')
                      : 'No Pending Rentals',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isOwner 
                      ? (title.contains('Completed') 
                          ? 'You don\'t have any completed rentals at the moment.'
                          : 'You don\'t have any active rentals at the moment.')
                      : 'You don\'t have any pending rentals at the moment.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...rentals.map((rental) => _buildRentalCard(rental, isOwner)).toList(),
      ],
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental, bool isOwner) {
    final ownerView = isOwner; // Capture isOwner parameter in local variable for use in closures
    final product = rental['products'];
    final paymentBreakdown = _calculatePaymentBreakdown(rental);
    final status = rental['status'] as String;
    
    // Check if penalty payment has been approved
    final double? lockedLateCharge = (rental['late_charge'] as num?)?.toDouble();
    final bool hasLatestPayment = rental['latest_payment'] != null;
    final String? latestPaymentStatus = rental['latest_payment']?['status']?.toString();
    final double? latestPaymentAmount = rental['latest_payment']?['amount'] != null 
        ? (rental['latest_payment']['amount'] as num).toDouble() 
        : null;
    final String paymentStatus = (rental['payment_status'] ?? '').toString();
    
    // Check if rental is returned/completed
    final bool isReturned = rental['returned_at'] != null;
    
    // Penalty is approved if:
    // 1. late_charge exists
    // 2. AND either:
    //    - latest_payment is paid/approved, OR
    //    - payment_status is 'paid', OR
    //    - payment_status is 'return_requested' (penalty must be paid to request return), OR
    //    - rental is returned/completed (penalty was paid before return was completed)
    final bool isPenaltyPaymentApproved = lockedLateCharge != null && lockedLateCharge > 0.0 && (
      (hasLatestPayment &&
       (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
       (latestPaymentAmount != null && latestPaymentAmount! > 0)) ||
      (paymentStatus == 'paid' && lockedLateCharge > 0.0) ||
      (paymentStatus == 'return_requested' && lockedLateCharge > 0.0) ||
      (isReturned && lockedLateCharge > 0.0) // Returned rental with late_charge = penalty paid (consistent from return request)
    );
    
    // Compute overdue based on expected return vs now to avoid any mismatch
    // Check overdue status first (based on time), then we'll override the display if penalty is paid
    bool isOverdue = false;
    try {
      DateTime? expectedDate = _parseLocalIgnoringTimezone(rental['expected_return_date']);
      expectedDate ??= _parseLocalIgnoringTimezone(rental['rented_at'])?.add(Duration(hours: paymentBreakdown.rentalDays));
      if (expectedDate != null) {
        final endTimeTmp = _parseLocalIgnoringTimezone(rental['returned_at']) ?? DateTime.now();
        // Calculate overdue based on time (regardless of penalty payment status)
        isOverdue = endTimeTmp.isAfter(expectedDate) && 
                    paymentStatus != 'submitted' && 
                    paymentStatus != 'awaiting_payment';
      }
    } catch (_) {}
    final returnedAt = rental['returned_at'] != null ? DateTime.tryParse(rental['returned_at']) : null;
    final paidAt = rental['paid_at'] != null ? DateTime.tryParse(rental['paid_at']) : null;
    DateTime? rentedAt = rental['rented_at'] != null ? DateTime.tryParse(rental['rented_at']) : null;
    if (status == 'pending_confirmation') {
      rentedAt = null; // Start time should be based on owner approval
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isOverdue && isPenaltyPaymentApproved) 
            ? const Color(0xFF10B981)  // Green border if penalty paid
            : (isOverdue 
              ? const Color(0xFFDC2626)  // Red border if overdue
              : const Color(0xFFE5E7EB)),  // Gray border if not overdue
          width: (isOverdue || isPenaltyPaymentApproved) ? 2 : 1,
        ),
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
          // Header
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
                      ownerView 
                          ? 'Rented by: ${rental['renter_name'] ?? rental['renter_id'] ?? 'Unknown'}'
                          : 'Owner: ${rental['owner_name'] ?? rental['user_id'] ?? 'Unknown'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(status, isOverdue, rental, isPenaltyPaymentApproved, isOwner: ownerView),
            ],
          ),
          
          const SizedBox(height: 16),
        
        // Show rental dates
        if (rentedAt != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: Color(0xFF3B82F6)),
                      SizedBox(width: 8),
                      Text(
                        'Rental Period',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow('Rented on', _formatDate(rentedAt)),
                  // Show clear due time for clarity
                  _buildDetailRow(
                    'Due by',
                    _formatDate(
                      rental['expected_return_date'] ??
                        (rental['rented_at'] != null
                          ? DateTime.parse(rental['rented_at']).toUtc().add(Duration(hours: paymentBreakdown.rentalDays)).toIso8601String()
                          : null),
                    ),
                  ),
                  if (returnedAt != null)
                    _buildDetailRow('Returned on', _formatDate(returnedAt)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          // Rental Details
          _buildDetailRow('Rental Period', '${paymentBreakdown.rentalDays} hours'),
          _buildDetailRow('Price per Hour', '₹${paymentBreakdown.pricePerDay.toStringAsFixed(2)}'),
          _buildDetailRow('Base Rent', '₹${paymentBreakdown.baseRent.toStringAsFixed(2)}'),
          
          // Always show overtime and penalty summary; color-coded when non-zero
          _buildDetailRow(
            'Overtime Hours',
            '${paymentBreakdown.overdueDays} hours',
            isPenalty: paymentBreakdown.overdueDays > 0,
            isPaid: isPenaltyPaymentApproved,
          ),
          _buildDetailRow(
            'Penalty',
            '₹${paymentBreakdown.penalty.toStringAsFixed(2)}',
            isPenalty: paymentBreakdown.penalty > 0,
            isPaid: isPenaltyPaymentApproved,
          ),
          
          const Divider(height: 24),
          _buildDetailRow('Total Amount', '₹${paymentBreakdown.total.toStringAsFixed(2)}', isTotal: true),
          
          // Show penalty if it exists in the database
          if (rental['late_charge'] != null && (rental['late_charge'] as num).toDouble() > 0) ...[
            const SizedBox(height: 4),
            _buildDetailRow('Late Fee', '₹${(rental['late_charge'] as num).toDouble().toStringAsFixed(2)}', isPenalty: true, isPaid: isPenaltyPaymentApproved),
          ],
          
          // Show payment details toggle when payment exists or was submitted/approved (for both owners and renters)
          if (rental['latest_payment'] != null || rental['payment_status'] == 'completed' || rental['payment_status'] == 'paid' || rental['payment_status'] == 'submitted' || rental['amount'] != null) ...[
            const SizedBox(height: 16),
            _buildToggleablePaymentDetails(rental, ownerView),
          ],
          
          const SizedBox(height: 16),
          
          if (rentedAt == null && status == 'pending_confirmation') ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pending_actions, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Rental Period Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Status', 
                  ownerView 
                    ? 'Waiting for your approval to start'
                    : 'Waiting for owner approval to start',
                ),
                const SizedBox(height: 4),
                Text(
                  ownerView
                    ? 'Once you verify payment and approve, the rental period will begin immediately.'
                    : 'The rental period will begin once the owner approves your payment.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ],
          
          // Action Buttons
          _buildActionButtons(rental, ownerView, status, isOverdue),
        ],
      ),
    );
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

  Widget _buildDetailRow(String label, String value, {bool isPenalty = false, bool isTotal = false, bool isPaid = false}) {
    // Change color to green if penalty is paid
    final Color labelColor = (isPenalty && isPaid) ? const Color(0xFF10B981) : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280));
    final Color valueColor = (isPenalty && isPaid) ? const Color(0xFF10B981) : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111));
    
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
              color: labelColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(Map<String, dynamic> rental, bool ownerView) {
    final String paymentStatus = (rental['payment_status'] ?? '').toString();
    final String rentalStatus = (rental['status'] ?? '').toString();
    final hasPaymentApproved = paymentStatus == 'paid' || paymentStatus == 'completed' || paymentStatus == 'approved';
    final hasApprovalPending = paymentStatus == 'submitted' || paymentStatus == 'pending' || paymentStatus == 'awaiting_payment';
    final isRentalActive = rentalStatus == 'active' && rental['returned_at'] == null;
    final isPendingConfirmation = rentalStatus == 'pending_confirmation';
    final isReturned = rental['returned_at'] != null;
    final breakdown = _calculatePaymentBreakdown(rental);
    final recordedLate = (rental['late_charge'] as num?)?.toDouble() ?? 0.0;
    
    // Check if penalty payment has been approved
    // Penalty is paid if: late_charge exists AND latest_payment exists AND latest_payment status is 'paid' or 'approved'
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
    final bool isPenaltyPaymentApproved = recordedLate > 0.0 && (
      (hasLatestPayment &&
       (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
       (latestPaymentAmount != null && latestPaymentAmount! > 0)) ||
      (paymentStatus == 'paid' && recordedLate > 0.0)
    );
    
    // Debug logging for penalty approval status
    if (recordedLate > 0.0) {
      debugPrint('[Status Timeline] Rental ${rental['id']}: recordedLate=$recordedLate, hasLatestPayment=$hasLatestPayment, latestPaymentStatus=$latestPaymentStatus, latestPaymentAmount=$latestPaymentAmount, isPenaltyPaymentApproved=$isPenaltyPaymentApproved');
    }
    
    // Penalty is due only if there's a penalty and it hasn't been approved yet
    // Also hide penalty due if return is requested (penalty should already be paid)
    final penaltyDue = (recordedLate > 0 && rental['returned_at'] == null) ? recordedLate : breakdown.penalty;
    final hasPenaltyDue = penaltyDue > 0 && 
                          rental['returned_at'] == null && 
                          !isPenaltyPaymentApproved &&
                          paymentStatus != 'return_requested'; // Hide if return is requested

    Widget statusItem({required IconData icon, required String title, required String subtitle, required Color color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111111))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, size: 18, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Text(
                ownerView ? 'Rental Status (Owner View)' : 'Rental Status (Your View)',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280), fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Show "Returned" status first if product is returned (for both owner and renter)
          if (isReturned) ...[
            statusItem(
              icon: Icons.check_circle_outline,
              title: 'Product Returned',
              subtitle: ownerView 
                ? 'Renter has returned the product. Rental completed successfully.'
                : 'You have returned the product. Rental completed successfully.',
              color: const Color(0xFF10B981),
            ),
          ]
          // Owner-specific status messages (only if not returned)
          else if (ownerView) ...[
            if (isPendingConfirmation && hasApprovalPending)
              statusItem(
                icon: Icons.pending_actions,
                title: 'Awaiting Your Approval',
                subtitle: 'Renter has submitted payment proof. Please verify and approve to start the rental.',
                color: const Color(0xFFF59E0B),
              ),
            if (isPendingConfirmation && rental['latest_payment'] == null && paymentStatus != 'submitted')
              statusItem(
                icon: Icons.schedule,
                title: 'Payment Pending',
                subtitle: 'Waiting for renter to submit payment proof.',
                color: const Color(0xFF6B7280),
              ),
            if (hasApprovalPending && !isPendingConfirmation)
              statusItem(
                icon: Icons.hourglass_bottom,
                title: 'Payment Proof Submitted',
                subtitle: 'Renter has submitted payment proof. Please verify to approve.',
                color: const Color(0xFFF59E0B),
              ),
            if (hasPaymentApproved && isRentalActive && isPenaltyPaymentApproved)
              statusItem(
                icon: Icons.check_circle,
                title: 'Rental Period Over',
                subtitle: 'Penalty has been paid. Waiting for return request by renter.',
                color: const Color(0xFF10B981),
              )
            else if (hasPaymentApproved && isRentalActive)
              statusItem(
                icon: Icons.check_circle,
                title: 'Rental Approved & Active',
                subtitle: 'You approved this rental. Rental period has started.',
                color: const Color(0xFF10B981),
              ),
            if (hasPaymentApproved && !isRentalActive)
              statusItem(
                icon: Icons.verified,
                title: 'Payment Approved',
                subtitle: 'Payment has been verified and approved.',
                color: const Color(0xFF10B981),
              ),
            // Show "Approval Pending" when return is requested (for owner view)
            if (paymentStatus == 'return_requested')
              statusItem(
                icon: Icons.hourglass_bottom,
                title: 'Approval Pending',
                subtitle: 'Renter has requested return. Review and process the return.',
                color: const Color(0xFFF59E0B),
              ),
          ]
          // Renter-specific status messages (only if not returned)
          else ...[
            if (isPendingConfirmation && hasApprovalPending)
              statusItem(
                icon: Icons.hourglass_bottom,
                title: 'Approval Pending',
                subtitle: 'Your payment proof is under review by the owner.',
                color: const Color(0xFFF59E0B),
              ),
            if (isPendingConfirmation && rental['latest_payment'] == null && paymentStatus != 'submitted')
              statusItem(
                icon: Icons.payment,
                title: 'Payment Required',
                subtitle: 'Please submit payment proof to proceed.',
                color: const Color(0xFF6B7280),
              ),
            if (hasApprovalPending && !isPendingConfirmation)
              statusItem(
                icon: Icons.hourglass_bottom,
                title: 'Approval Pending',
                subtitle: 'Owner is reviewing your payment proof.',
                color: const Color(0xFFF59E0B),
              ),
            if (hasPaymentApproved && isRentalActive && isPenaltyPaymentApproved)
              statusItem(
                icon: Icons.check_circle,
                title: 'Rental Period Over',
                subtitle: 'Penalty has been paid. Please return the product.',
                color: const Color(0xFF10B981),
              )
            else if (hasPaymentApproved && isRentalActive)
              statusItem(
                icon: Icons.check_circle,
                title: 'Rental Approved & Active',
                subtitle: 'Owner approved your request! Rental period has started.',
                color: const Color(0xFF10B981),
              ),
            if (hasPaymentApproved && !isRentalActive && !isPenaltyPaymentApproved)
              statusItem(
                icon: Icons.verified,
                title: 'Payment Approved',
                subtitle: 'Your payment was approved by the owner.',
                color: const Color(0xFF10B981),
              ),
            // Show "Rental Active" only if penalty is NOT paid yet AND return is NOT requested
            if (isRentalActive && !isPenaltyPaymentApproved && paymentStatus != 'return_requested')
              statusItem(
                icon: Icons.play_circle_fill,
                title: 'Rental Active',
                subtitle: 'You can use the product now. Return by the agreed date.',
                color: const Color(0xFF3B82F6),
              ),
            // Show "Under Review" when return is requested (for renter view)
            if (paymentStatus == 'return_requested')
              statusItem(
                icon: Icons.hourglass_bottom,
                title: 'Return Under Review',
                subtitle: 'Return requested. Owner is reviewing to process the return.',
                color: const Color(0xFFF59E0B),
              ),
          ],
          
          // Don't show duplicate "Rental Period Over" - already shown above for owner view
          // Removed duplicate statusItem here
          
          if (hasPenaltyDue)
            statusItem(
              icon: Icons.warning_amber_rounded,
              title: 'Penalty Due',
              subtitle: ownerView 
                ? 'Renter owes overtime penalty: ₹' + penaltyDue.toStringAsFixed(2) + '. Waiting for renter to pay penalty before return.'
                : 'Overtime penalty due: ₹' + penaltyDue.toStringAsFixed(2) + '. Please pay to complete return.',
              color: const Color(0xFFDC2626),
            ),
          const SizedBox(height: 12),
          if (ownerView && (paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment' || isPendingConfirmation))
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: () => _showPaymentVerificationModal(rental),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Verify Payment'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleablePaymentDetails(Map<String, dynamic> rental, bool ownerView) {
    final rentalId = rental['id'];
    final isExpanded = _expandedPaymentIds.contains(rentalId);
    final isReturned = rental['returned_at'] != null;
    final renterTxn = rental['latest_payment']?['transaction_id'] ?? rental['transaction_id'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: const [
                      Icon(Icons.payment, size: 18, color: Color(0xFF3B82F6)),
                      SizedBox(width: 8),
                      Text(
                        'View Payment Details',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF3B82F6),
                ),
              ],
            ),
                ),
                if (renterTxn != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Renter Txn ID: $renterTxn',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 8),
          _buildPaymentDetailsSection(rental, isReturned: isReturned, ownerView: ownerView),
        ],
      ],
    );
  }

  Widget _buildPaymentDetailsSection(Map<String, dynamic> rental, {bool isReturned = false, required bool ownerView}) {
    // Debug: Print payment info
    debugPrint('Building payment details for rental: ${rental['id']}');
    debugPrint('  latest_payment: ${rental['latest_payment']}');
    debugPrint('  payment_status: ${rental['payment_status']}');
    debugPrint('  payment_id: ${rental['payment_id']}');
    debugPrint('  amount: ${rental['amount']}');
    debugPrint('  paid_at: ${rental['paid_at']}');
    
    // Get screenshot URL from rental or latest payment
    final screenshotUrl = rental['payment_screenshot'] ?? rental['latest_payment']?['receipt_url'];
    
    // Get payment method from payments table or rental if available
    final paymentMethod = rental['payment_method_latest'] ?? 
                          rental['latest_payment']?['method'] ?? 
                          rental['payment_method'];
    
    // Get payment amount and date
    final amountPaid = rental['latest_payment']?['amount'] ?? rental['amount'];
    final paidAt = rental['latest_payment']?['paid_at'] ?? rental['paid_at'];
    
    // Get return date
    final returnedAt = rental['returned_at'] != null ? DateTime.tryParse(rental['returned_at']) : null;
    
    // Calculate overtime hours - use locked late_charge if exists to maintain consistency
    // from return request to completion. Do NOT recalculate from returned_at date.
    int overtimeHours = 0;
    final double? lockedLateCharge = (rental['late_charge'] as num?)?.toDouble();
    final product = rental['products'];
    final pricePerHour = (product?['price'] ?? 0).toDouble();
    
    if (lockedLateCharge != null && lockedLateCharge > 0 && pricePerHour > 0) {
      // Use locked late_charge to calculate overtime hours - ensures consistency
      // Penalty = (pricePerHour / 60) * overdueMinutes * 1.0
      // Therefore: overdueMinutes = penalty / (pricePerHour / 60) = penalty * 60 / pricePerHour
      final overdueMinutesFromPenalty = (lockedLateCharge * 60.0 / pricePerHour).round();
      overtimeHours = (overdueMinutesFromPenalty / 60.0).ceil();
    } else {
      // Fallback: only calculate if no locked late_charge exists
      try {
        if (rental['expected_return_date'] != null) {
          final expected = DateTime.parse(rental['expected_return_date']);
          final end = returnedAt ?? DateTime.now();
          if (end.isAfter(expected)) {
            overtimeHours = end.difference(expected).inHours;
          }
        }
      } catch (_) {}
    }
    
    // Renter-entered transaction id (only display if provided)
    final renterTxnId = rental['latest_payment']?['transaction_id'] ?? rental['transaction_id'];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.payment,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Payment Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Payment summary
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
                    if (amountPaid != null)
                      Text(
                        '₹$amountPaid',
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
                        if (paymentMethod != null)
                          _buildInfoChip(
                            'Payment Mode',
                            paymentMethod.toString().toUpperCase(),
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
                        if (isReturned && returnedAt != null)
                          _buildInfoChip(
                            'Returned on',
                            _formatDate(returnedAt.toString()),
                            Icons.check_circle,
                          ),
                        // Overtime (hours past expected)
                        if (overtimeHours > 0)
                          _buildInfoChip(
                            'Overtime',
                            '$overtimeHours hour(s)',
                            Icons.timer_off,
                            isPenalty: true,
                          ),
                        // Late Fee
                        if (rental['late_charge'] != null && (rental['late_charge'] as num).toDouble() > 0)
                          _buildInfoChip(
                            'Late Fee',
                            '₹${rental['late_charge'].toStringAsFixed(2)}',
                            Icons.warning,
                            isPenalty: true,
                          ),
                      ],
                    ),
              
          // Status timeline
          const SizedBox(height: 16),
          _buildStatusTimeline(rental, ownerView),

            // Payment Breakdown with Status (mirrors Rental History)
            const SizedBox(height: 16),
            Builder(builder: (context) {
              // Calculate rental hours locally
              int rentalHours = rental['rental_days'] ?? 0;
              if (rentalHours == 0 && rental['expected_return_date'] != null && rental['rented_at'] != null) {
                try {
                  final rentedAtLocal = DateTime.parse(rental['rented_at']);
                  final expectedLocal = DateTime.parse(rental['expected_return_date']);
                  rentalHours = ((expectedLocal.difference(rentedAtLocal).inMinutes) / 60).ceil();
                } catch (_) {}
              }
              if (rentalHours <= 0) rentalHours = 1;
              final pricePerHour = (rental['products']?['price'] ?? 0).toDouble();
              final baseAmount = (rentalHours * pricePerHour).toDouble();
              // Determine current late fee and its paid status
              final breakdown = _calculatePaymentBreakdown(rental);
              final recordedLateCharge = (rental['late_charge'] as num?)?.toDouble();
              final hasRecordedLateCharge = recordedLateCharge != null && recordedLateCharge > 0;
              
              // Check if penalty payment has been approved
              // Penalty is paid if: late_charge exists AND latest_payment exists AND latest_payment status is 'paid' or 'approved'
              // Also check if the latest payment amount matches the penalty amount (to distinguish from initial rent payment)
              final String paymentStatusForPenalty = (rental['payment_status'] ?? '').toString();
              final bool hasLatestPayment = rental['latest_payment'] != null;
              final String? latestPaymentStatus = rental['latest_payment']?['status']?.toString();
              final double? latestPaymentAmount = rental['latest_payment']?['amount'] != null 
                  ? (rental['latest_payment']['amount'] as num).toDouble() 
                  : null;
              
              // Check if rental is returned/completed
              final bool isReturned = rental['returned_at'] != null;
              
              // Penalty is paid if:
              // 1. late_charge exists (penalty was calculated/recorded)
              // 2. latest_payment exists with status 'paid' or 'approved'
              // 3. For penalty payments, the payment amount typically matches or is close to the late_charge
              //    OR if payment_status is 'paid' and late_charge exists, it means penalty was approved
              // 4. If payment_status is 'return_requested', penalty must be paid (return can only be requested after all dues cleared)
              // 5. If rental is returned/completed and late_charge exists, penalty was paid (consistent from return request)
              // Also check if payment_status is 'paid' and late_charge exists as fallback
              final bool isLateFeePaid = hasRecordedLateCharge && (
                (hasLatestPayment &&
                 (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
                 (latestPaymentAmount != null && latestPaymentAmount! > 0)) ||
                (paymentStatusForPenalty == 'paid' && hasRecordedLateCharge) ||
                (paymentStatusForPenalty == 'return_requested' && hasRecordedLateCharge) || // Return requested = penalty paid
                (isReturned && hasRecordedLateCharge) // Returned rental with late_charge = penalty paid (consistent from return request)
              );
              
              // Debug logging for penalty payment status
              if (hasRecordedLateCharge) {
                debugPrint('[Payment Breakdown] Rental ${rental['id']}: late_charge=${recordedLateCharge}, hasLatestPayment=$hasLatestPayment, latestPaymentStatus=$latestPaymentStatus, latestPaymentAmount=$latestPaymentAmount, isLateFeePaid=$isLateFeePaid');
              }
              
              final double lateFeeToShow = hasRecordedLateCharge
                  ? recordedLateCharge!
                  : breakdown.penalty; // show computed penalty if not recorded yet

              return Container(
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
                    _buildPaymentRow('Base Rent (' + rentalHours.toString() + ' hours)', baseAmount, isPaid: true),
                    // Show overtime hours if penalty exists for returned products
                    if (breakdown.overdueDays > 0 && lateFeeToShow > 0) ...[
                      _buildDetailRow('Overtime Hours', '${breakdown.overdueDays} hour(s)', isPenalty: true, isPaid: isLateFeePaid),
                    ],
                    _buildPaymentRow('Late Fee (Penalty)', lateFeeToShow, isPaid: isLateFeePaid, isPenalty: true),
                    const Divider(height: 16),
                    // Total should include both base rent and penalty
                    Builder(
                      builder: (context) {
                        final double totalPaid = ((amountPaid ?? 0) as num).toDouble();
                        final double calculatedTotal = baseAmount + lateFeeToShow;
                        return _buildPaymentRow('Total Paid', totalPaid > 0 ? totalPaid : calculatedTotal, isTotal: true);
                      },
                    ),
                  ],
                ),
              );
            }),
              
              // Transaction ID (only renter-entered)
              if (renterTxnId != null) ...[
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
                        renterTxnId.toString(),
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
          // Payment screenshot if available
          if (screenshotUrl != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Payment Proof',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppBar(
                          title: const Text('Payment Screenshot'),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Image.network(
                            screenshotUrl.toString(),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Padding(
                                padding: EdgeInsets.all(32),
                                child: Icon(Icons.error, size: 64, color: Colors.red),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    screenshotUrl.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Colors.red, size: 40),
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

  // Helper: payment row with optional Paid/Unpaid badge
  Widget _buildPaymentRow(String label, double amount, {bool isPaid = false, bool isPenalty = false, bool isTotal = false}) {
    // Change color to green if penalty is paid
    final Color penaltyColor = (isPenalty && isPaid) ? const Color(0xFF10B981) : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF6B7280));
    final Color amountColor = (isPenalty && isPaid) ? const Color(0xFF10B981) : (isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111));
    
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
              color: penaltyColor,
            ),
          ),
          Row(
            children: [
              Text(
                '₹' + amount.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: isTotal ? 18 : 14,
                  fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                  color: amountColor,
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
              if (!isPaid && isPenalty && amount > 0 && !isTotal)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Unpaid',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isOverdue, Map<String, dynamic> rental, bool isPenaltyPaymentApproved, {bool isOwner = false}) {
    Color color;
    String text;
    
    // Check if product is returned - show "Completed" first
    final bool isReturned = rental['returned_at'] != null;
    final String paymentStatus = (rental['payment_status'] ?? '').toString();
    
    if (isReturned) {
      color = const Color(0xFF10B981);
      text = 'Completed';
    }
    // Check if return is requested - show "Approval Pending" for owner, "Under Review" for renter
    else if (paymentStatus == 'return_requested') {
      color = const Color(0xFFF59E0B);
      text = isOwner ? 'Approval Pending' : 'Under Review';
    }
    // Check if penalty is paid - show "Penalty Paid" in green instead of "Overdue"
    else if (isOverdue && isPenaltyPaymentApproved) {
      color = const Color(0xFF10B981);
      text = 'Penalty Paid';
    } else if (isOverdue) {
      color = const Color(0xFFDC2626);
      text = 'Overdue';
    } else if ((paymentStatus == 'submitted' || paymentStatus == 'awaiting_payment')) {
      color = const Color(0xFFF59E0B);
      text = 'Approval Pending';
    } else {
      switch (status) {
        case 'active':
            case 'completed':
          color = const Color(0xFF10B981);
          text = 'Active';
          break;
        case 'awaiting_payment':
          color = const Color(0xFFF59E0B);
          text = 'Awaiting Payment';
          break;
        case 'pending_confirmation':
          color = const Color(0xFF6B7280);
          text = 'Pending';
          break;
        default:
          color = const Color(0xFF6B7280);
          text = status;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> rental, bool isOwner, String status, bool isOverdue) {
    final product = rental['products'];
    final qrUrl = product['qr_code_url'];
    final upiId = product['upi_id'];
    final hasPaymentMethods = qrUrl != null || upiId != null;
    final paymentBreakdown = _calculatePaymentBreakdown(rental);
    final double lateChargeValue = (rental['late_charge'] as num?)?.toDouble() ?? 0.0;
    bool isOverdueNow = false;
    // minutes until due (for renter warnings)
    int minutesUntilDue = 0;
    try {
      DateTime? expected;
      expected = _parseLocalIgnoringTimezone(rental['expected_return_date']);
      expected ??= _parseLocalIgnoringTimezone(rental['rented_at'])?.add(Duration(hours: paymentBreakdown.rentalDays));
      if (expected != null) {
        final now = DateTime.now();
        if (now.isBefore(expected)) {
          minutesUntilDue = expected.difference(now).inMinutes;
        } else {
          isOverdueNow = true;
        }
      }
    } catch (_) {}

    // Determine the real penalty amount due now
    final double computedPenalty = paymentBreakdown.penalty;
    final String paymentStatusForRent = (rental['payment_status'] ?? '').toString();
    final bool isRentalActive = status == 'active' || status == 'overdue';
    
    // Check if penalty has been paid and approved
    // Penalty is approved if:
    // 1. late_charge exists (penalty amount was recorded)
    // 2. latest_payment exists with status 'paid' or 'approved'
    // 3. The payment amount matches the penalty (to distinguish from initial rent payment)
    final bool hasLatestPayment = rental['latest_payment'] != null;
    final String? latestPaymentStatus = rental['latest_payment']?['status']?.toString();
    final double? latestPaymentAmount = rental['latest_payment']?['amount'] != null 
        ? (rental['latest_payment']['amount'] as num).toDouble() 
        : null;
    
    // Check payment_status as well - if it's 'paid' and late_charge exists, penalty was approved
    final String paymentStatusForPenalty = (rental['payment_status'] ?? '').toString();
    final bool penaltyApproved = lateChargeValue > 0.0 && (
      (hasLatestPayment &&
       (latestPaymentStatus == 'paid' || latestPaymentStatus == 'approved') &&
       (latestPaymentAmount != null && latestPaymentAmount! > 0)) ||
      (paymentStatusForPenalty == 'paid' && lateChargeValue > 0.0)
    );
    
    // Debug logging for action buttons penalty status
    if (lateChargeValue > 0.0 || computedPenalty > 0.0) {
      debugPrint('[Action Buttons] Rental ${rental['id']}: lateChargeValue=$lateChargeValue, computedPenalty=$computedPenalty, hasLatestPayment=$hasLatestPayment, latestPaymentStatus=$latestPaymentStatus, latestPaymentAmount=$latestPaymentAmount, penaltyApproved=$penaltyApproved');
    }
    
    // Penalty is outstanding ONLY if:
    // 1. There's a computed penalty > 0 OR late_charge > 0
    // 2. AND penalty payment has NOT been approved
    final bool hasOutstandingPenalty = (computedPenalty > 0.0 || lateChargeValue > 0.0) && 
                                        !penaltyApproved;
    
    // Check if initial rent payment is cleared
    final bool initialRentPaid = paymentStatusForRent == 'paid' || paymentStatusForRent == 'completed' || paymentStatusForRent == 'approved';
    
    // Check if penalty payment is cleared (if there was a penalty)
    // Penalty is paid if:
    // 1. No outstanding penalty at all, OR
    // 2. Penalty was approved (payment_status == 'paid' and late_charge exists), OR
    // 3. Latest payment exists for penalty and status is 'paid' or 'approved' (owner approved)
    final bool penaltyPaid = !hasOutstandingPenalty || 
      penaltyApproved ||
      (rental['latest_payment'] != null && 
       rental['latest_payment']?['status'] != null &&
       (rental['latest_payment']?['status'] == 'paid' || 
        rental['latest_payment']?['status'] == 'approved'));
    
    // All dues cleared = initial rent paid AND (no outstanding penalty OR penalty payment approved)
    // Strict check: both initial rent and penalty (if any) must be fully paid and approved
    final bool allDuesCleared = initialRentPaid && 
      (!hasOutstandingPenalty || penaltyPaid);
    
    // Penalty due amount for display (only if not yet paid)
    final double penaltyDueAmount = hasOutstandingPenalty ? (lateChargeValue > 0.0 ? lateChargeValue : computedPenalty) : 0.0;
    
    // Don't show Pay Penalty button if return is already requested (penalty should already be paid)
    final bool shouldHidePayPenalty = rental['payment_status'] == 'return_requested';
    // Don't show penalty warning if return is already requested or penalty is already paid/approved
    final bool shouldHidePenaltyWarning = rental['payment_status'] == 'return_requested' || 
                                          (hasOutstandingPenalty && penaltyApproved);

    return Column(
      children: [
        Row(
          children: [
            if (isOwner) ...[
              // Owner actions
              // Show verify payment for rent AND penalty
              if ((rental['payment_status'] == 'submitted' || rental['payment_status'] == 'awaiting_payment' || rental['payment_status'] == 'pending' || status == 'pending_confirmation') && hasOutstandingPenalty)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showPaymentVerificationModal(rental),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Verify Payment'),
                  ),
                ),
              
              // Process Return only after renter requests return
              if (rental['returned_at'] == null && (status == 'active' || status == 'overdue') && rental['payment_status'] == 'return_requested')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showReturnModal(rental),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Process Return'),
                  ),
                ),
              
              // Verify payment for awaiting_payment status
              if (status == 'awaiting_payment')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showPaymentVerificationModal(rental),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Verify Payment'),
                  ),
                ),
            ] else ...[
              // Renter actions (single unified flow) - only show if not already returned
              // Don't show Pay Penalty button if return is already requested (penalty should already be paid)
              if (rental['returned_at'] == null && 
                  ((status == 'awaiting_payment') || hasOutstandingPenalty) &&
                  !shouldHidePayPenalty)
                Flexible(fit: FlexFit.loose,
                  child: ElevatedButton(
                    onPressed: (rental['payment_status'] == 'submitted') ? null : (hasPaymentMethods ? () => _navigateToPayment(rental) : null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasPaymentMethods && rental['payment_status'] != 'submitted' ? const Color(0xFF007BFF) : const Color(0xFF9CA3AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      status == 'awaiting_payment'
                          ? 'Complete Payment'
                          : ('Pay Penalty ₹' + penaltyDueAmount.toStringAsFixed(2)),
                    ),
                  ),
                ),
              if (rental['returned_at'] == null && 
                  ((status == 'awaiting_payment') || hasOutstandingPenalty) &&
                  !shouldHidePayPenalty)
                const SizedBox(width: 12),
              // Only show Request Return if ALL dues are cleared:
              // 1. Initial rent is paid AND approved
              // 2. NO outstanding penalty at all (hasOutstandingPenalty must be false)
              // 3. No payment is pending submission
              // 4. Status is active
              // IMPORTANT: Button is completely hidden if ANY dues are outstanding
              // If penalty exists, it must be paid AND approved before button shows
              if (rental['returned_at'] == null && 
                  initialRentPaid &&  // Initial rent must be paid
                  !hasOutstandingPenalty &&  // NO outstanding penalty allowed
                  rental['payment_status'] != 'submitted' && 
                  rental['payment_status'] != 'awaiting_payment' &&
                  rental['payment_status'] != 'pending' &&
                  status == 'active')
                Flexible(fit: FlexFit.loose,
                  child: OutlinedButton(
                    onPressed: () => _requestReturn(rental),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(color: Color(0xFF3B82F6)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Request Return'),
                  ),
                ),
              
              if (rental['returned_at'] == null && rental['payment_status'] == 'return_requested')
                Flexible(fit: FlexFit.loose,
                  child: OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Return Requested'),
                  ),
                ),
              
              // Actions for pending rentals without payment
              if (status == 'pending_confirmation' && rental['payment_status'] == 'pending' && rental['latest_payment'] == null) ...[
                Expanded(
                  child: ElevatedButton(
                    onPressed: hasPaymentMethods ? () => _navigateToPayment(rental) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasPaymentMethods ? const Color(0xFF007BFF) : const Color(0xFF9CA3AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Complete Payment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _cancelRental(rental),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel Rental'),
                  ),
                ),
              ],
            ],
          ],
        ),
        // Don't show penalty warning if return is already requested or penalty is already paid/approved
        if (rental['returned_at'] == null && 
            hasOutstandingPenalty && 
            !shouldHidePenaltyWarning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  isOwner ? Icons.monetization_on : Icons.info_outline, 
                  size: 16, 
                  color: isOwner ? const Color(0xFFF59E0B) : const Color(0xFF6B7280)
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isOwner 
                      ? 'Renter owes penalty: ₹' + penaltyDueAmount.toStringAsFixed(2) + '. Waiting for renter to pay penalty before return.'
                      : 'Penalty due: ₹' + penaltyDueAmount.toStringAsFixed(2) + '. Pay penalty to enable return.',
                    style: TextStyle(
                      fontSize: 12, 
                      color: isOwner ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                      fontWeight: isOwner ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (rental['returned_at'] == null && status == 'active' && rental['payment_status'] != 'return_requested' && minutesUntilDue > 0 && minutesUntilDue <= 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOwner
                        ? 'Rental due soon. Renter should return item to avoid penalty charges.'
                        : 'Due soon. Request return now to avoid penalty.',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isOwner && rental['payment_status'] == 'return_requested')
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Renter requested a return. Review penalties, damages, and confirm.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _showReturnModal(rental),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Review Return'),
                ),
              ],
            ),
        ),
        if (!hasPaymentMethods && !isOwner)
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
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
                    'No payment methods available. Please contact the owner.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _handleReturnProduct(Map<String, dynamic> rental) {
    // Calculate if there's a penalty
    final paymentBreakdown = _calculatePaymentBreakdown(rental);
    final qrUrl = rental['products']['qr_code_url'];
    final upiId = rental['products']['upi_id'];
    
    if (paymentBreakdown.penalty > 0) {
      // Show payment screen for penalty
      _showPenaltyPaymentModal(rental, paymentBreakdown, qrUrl, upiId);
    } else {
      // No penalty, just return the product
      _showConfirmReturnModal(rental);
    }
  }

  void _showPenaltyPaymentModal(Map<String, dynamic> rental, PaymentBreakdown breakdown, String? qrUrl, String? upiId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PaymentProofModal(
        rental: rental,
        breakdown: breakdown,
        qrUrl: qrUrl,
        upiId: upiId,
        onPaymentSubmitted: () async {
          Navigator.pop(context);
          await _processReturnWithPayment(rental, breakdown);
        },
      ),
    );
  }

  void _showConfirmReturnModal(Map<String, dynamic> rental) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Return'),
        content: const Text('Are you sure you want to return this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _processReturn(rental);
            },
            child: const Text('Return'),
          ),
        ],
      ),
    );
  }

  Future<void> _processReturnWithPayment(Map<String, dynamic> rental, PaymentBreakdown breakdown) async {
    try {
      // Create payment record for penalty
      final renterId = rental['renter_id'];
      final ownerId = rental['user_id'];
      
      await SupabaseService.client.from('payments').insert({
        'rental_id': rental['id'],
        'payer_id': renterId,
        'payee_id': ownerId,
        'amount': breakdown.penalty.toString(),
        'method': 'qr',
        'status': 'completed',
        'paid_at': DateTime.now().toIso8601String(),
      });

      // Update rental with penalty paid and mark as returned
      await SupabaseService.client.from('rentals').update({
        'status': 'completed',
        'late_charge': breakdown.penalty,
        'returned_at': DateTime.now().toIso8601String(),
      }).eq('id', rental['id']);

      // Free the product (this will also set status to completed)
      await SupabaseService().markRentalAsReturned(rentalId: rental['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product returned successfully! Penalty of ₹${breakdown.penalty.toStringAsFixed(2)} applied.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        _loadRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process return: $e')),
        );
      }
    }
  }

  Future<void> _processReturn(Map<String, dynamic> rental) async {
    try {
      // Free the product and mark as completed (markRentalAsReturned will set status to completed)
      await SupabaseService().markRentalAsReturned(rentalId: rental['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product returned successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        _loadRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process return: $e')),
        );
      }
    }
  }

  void _showPaymentVerificationModal(Map<String, dynamic> rental) {
    final breakdown = _calculatePaymentBreakdown(rental);
    final isPenaltyPayment = rental['status'] == 'active' && breakdown.penalty > 0;
    final paymentAmount = rental['latest_payment']?['amount'] != null
        ? (rental['latest_payment']['amount'] as num).toDouble()
        : (breakdown.total);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_user, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                            'Payment Verification',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Review payment proof and verify',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rental Summary Card
                      Container(
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
                                const Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 20),
                                const SizedBox(width: 8),
              const Text(
                                  'Rental Summary',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111111),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildVerificationRow(Icons.person, 'Renter', rental['renter_name'] ?? 'Unknown'),
              const SizedBox(height: 12),
                            _buildVerificationRow(Icons.inventory_2, 'Product', rental['products']['name'] ?? 'Unknown'),
                            const SizedBox(height: 12),
                            _buildVerificationRow(
                              Icons.currency_rupee,
                              'Amount Paid',
                              '₹${paymentAmount.toStringAsFixed(2)}',
                              isAmount: true,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Payment Breakdown (if penalty payment)
                      if (isPenaltyPayment) ...[
                Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Penalty Payment',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildBreakdownRow('Base Rent', breakdown.baseRent, isPenalty: false),
                              if (breakdown.overdueDays > 0)
                                _buildBreakdownRow('Overtime Hours', null, text: '${breakdown.overdueDays} hours', isPenalty: true),
                              _buildBreakdownRow('Penalty', breakdown.penalty, isPenalty: true),
                              const Divider(height: 24),
                              _buildBreakdownRow('Total Amount', breakdown.total, isTotal: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Verification Instructions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.checklist, color: Color(0xFF3B82F6), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'What to verify:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCheckItem('Payment amount matches the due amount'),
                                  _buildCheckItem('Transaction ID is valid and visible'),
                                  _buildCheckItem('Payment screenshot is clear and readable'),
                                  _buildCheckItem('Payment date is recent'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Payment Screenshot
                      if (rental['latest_payment']?['receipt_url'] != null || rental['payment_screenshot'] != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: const Text(
                                'Payment Screenshot',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111111),
                                ),
                              ),
                            ),
                            Flexible(
                              child: TextButton.icon(
                                onPressed: () {
                                  final screenshotUrl = (rental['latest_payment']?['receipt_url'] ?? rental['payment_screenshot']).toString();
                                  showDialog(
                                    context: context,
                                    barrierColor: Colors.black87,
                                    builder: (context) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: const EdgeInsets.all(0),
                                      child: Stack(
                                        children: [
                                          InteractiveViewer(
                                            minScale: 0.5,
                                            maxScale: 4.0,
                                            child: Image.network(
                                              screenshotUrl,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  height: 400,
                                                  color: Colors.grey.shade900,
                                                  child: const Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.error_outline, color: Colors.red, size: 64),
                                                      SizedBox(height: 16),
                                                      Text(
                                                        'Failed to load image',
                                                        style: TextStyle(color: Colors.white, fontSize: 18),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          Positioned(
                                            top: 16,
                                            right: 16,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: IconButton(
                                                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                                onPressed: () => Navigator.pop(context),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.fullscreen, size: 16),
                                label: const Text(
                                  'View Full',
                                  style: TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3B82F6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            final screenshotUrl = (rental['latest_payment']?['receipt_url'] ?? rental['payment_screenshot']).toString();
                            showDialog(
                              context: context,
                              barrierColor: Colors.black87,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(0),
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      minScale: 0.5,
                                      maxScale: 4.0,
                                      child: Image.network(
                                        screenshotUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            height: 400,
                                            color: Colors.grey.shade900,
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.error_outline, color: Colors.red, size: 64),
                                                SizedBox(height: 16),
                                                Text(
                                                  'Failed to load image',
                                                  style: TextStyle(color: Colors.white, fontSize: 18),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      top: 16,
                                      right: 16,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                          onPressed: () => Navigator.pop(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                  width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                  ),
                  child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                children: [
                                  Image.network(
                      (rental['latest_payment']?['receipt_url'] ?? rental['payment_screenshot']).toString(),
                                    fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 200,
                                        color: Colors.grey.shade100,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Failed to load image',
                                              style: TextStyle(color: Colors.red),
                                            ),
                                          ],
                                        ),
                        );
                      },
                    ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.fullscreen, color: Colors.white, size: 16),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to enlarge',
                                            style: TextStyle(color: Colors.white, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Transaction ID
              if (rental['latest_payment']?['transaction_id'] != null || rental['transaction_id'] != null) ...[
                Container(
                          padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                                child: const Icon(Icons.receipt_long, color: Color(0xFF3B82F6), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                                      'Transaction ID',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500,
                                      ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        (rental['latest_payment']?['transaction_id'] ?? rental['transaction_id']).toString(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF111111),
                                        fontFamily: 'monospace',
                                        letterSpacing: 0.5,
                                      ),
                      ),
                    ],
                  ),
                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Renter Notes (if any)
                      if (rental['notes'] != null || rental['latest_payment']?['notes'] != null) ...[
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
                              Row(
                                children: [
                                  const Icon(Icons.note_alt, color: Color(0xFF6B7280), size: 18),
                                  const SizedBox(width: 8),
                      const Text(
                                    'Renter Notes',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (rental['latest_payment']?['notes'] ?? rental['notes']).toString(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF374151),
                  ),
                ),
              ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Action Instructions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info, color: Colors.blue.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'After verification:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Different instructions based on payment type
                            if (isPenaltyPayment) ...[
                              // Scenario 2: Penalty Payment
                              _buildInstructionItem(
                                Icons.check_circle, 
                                'Approve Payment', 
                                'Penalty payment accepted. Rental usage ends. Renter must return the product.',
                                Colors.green as MaterialColor
              ),
              const SizedBox(height: 8),
                              _buildInstructionItem(
                                Icons.cancel, 
                                'Reject Payment', 
                                'Request new payment proof from renter',
                                Colors.red as MaterialColor
                              ),
                            ] else ...[
                              // Scenario 1: Initial Rent Payment
                              _buildInstructionItem(
                                Icons.check_circle, 
                                'Approve Payment', 
                                'Mark rental as active and allow renter to use the product',
                                Colors.green as MaterialColor
                              ),
                              const SizedBox(height: 8),
                              _buildInstructionItem(
                                Icons.cancel, 
                                'Reject Payment', 
                                'Request new payment proof from renter',
                                Colors.red as MaterialColor
                              ),
                            ],
            ],
          ),
        ),
                    ],
                  ),
                ),
              ),
              
              // Action Buttons
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 400;
                    
                    if (isSmallScreen) {
                      // Stack buttons vertically on small screens
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _approvePayment(rental),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Approve Payment',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
            onPressed: () => _rejectPayment(rental),
            style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.close, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Reject',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    } else {
                      // Horizontal layout for larger screens
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _rejectPayment(rental),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.close, size: 20),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Reject',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
            onPressed: () => _approvePayment(rental),
            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 20),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Approve Payment',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
          ),
        ],
      ),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationRow(IconData icon, String label, String value, {bool isAmount = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isAmount ? 18 : 14,
            fontWeight: isAmount ? FontWeight.w700 : FontWeight.w600,
            color: isAmount ? const Color(0xFF10B981) : const Color(0xFF111111),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(String label, double? amount, {bool isPenalty = false, bool isTotal = false, String? text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
          if (text != null)
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
              ),
            )
          else if (amount != null)
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: isTotal ? 20 : 14,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
                color: isPenalty ? const Color(0xFFDC2626) : (isTotal ? const Color(0xFF111111) : const Color(0xFF111111)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(IconData icon, String title, String subtitle, MaterialColor color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color.shade700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: color.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _approvePayment(Map<String, dynamic> rental) async {
    try {
      final breakdown = _calculatePaymentBreakdown(rental);
      // Detect if this is a penalty payment: rental is already active AND has penalty
      final isPenaltyPayment = rental['status'] == 'active' && breakdown.penalty > 0;
      
      if (!isPenaltyPayment && rental['status'] != 'active') {
        // SCENARIO 1: Initial rent approval - renter gets permission to use the product
        // For initial rent approval only: set rental period and start.
        int rentalHours = rental['rental_days'] ?? 0;
        if (rentalHours == 0 && rental['amount_due'] != null) {
          try {
            final pricePerHour = (rental['products']?['price'] ?? 0).toDouble();
            final due = (rental['amount_due'] as num).toDouble();
            if (pricePerHour > 0) {
              rentalHours = (due / pricePerHour).ceil();
            }
          } catch (_) {}
        }
        if (rentalHours == 0 && rental['expected_return_date'] != null && rental['rented_at'] != null) {
          try {
            final rentedAt = DateTime.parse(rental['rented_at']);
            final expected = DateTime.parse(rental['expected_return_date']);
            rentalHours = ((expected.difference(rentedAt).inMinutes) / 60).ceil();
          } catch (_) {}
        }
        if (rentalHours <= 0) rentalHours = 1;
        final now = DateTime.now();
        final expectedReturn = now.add(Duration(hours: rentalHours));
        await SupabaseService.client.from('rentals').update({
          'status': 'active',
          'payment_status': 'paid',
          'paid_at': now.toIso8601String(),
          'rented_at': now.toIso8601String(),
          'expected_return_date': expectedReturn.toIso8601String(),
        }).eq('id', rental['id']);
        // Mark product as rented upon approval - renter can now use it
        try {
          await SupabaseService.client.from('products').update({
            'is_rented': true,
            'renter_id': rental['renter_id'],
            'rented_at': now.toIso8601String(),
          }).eq('id', rental['product_id']);
        } catch (_) {}
      } else {
        // SCENARIO 2: Penalty payment approval - usage ends, renter must return product
        // For penalty/late-fee payment approval: update payment status, late_charge, and paid_at
        // IMPORTANT: DO NOT overwrite 'amount' field - it should keep the base rent
        // Get penalty amount from latest payment or calculate current penalty
        double penaltyAmount = 0.0;
        if (rental['latest_payment'] != null && rental['latest_payment']?['amount'] != null) {
          penaltyAmount = (rental['latest_payment']['amount'] as num).toDouble();
        } else {
          // Calculate penalty if not in payment record
          penaltyAmount = breakdown.penalty;
        }
        
        // Preserve base rent: If 'amount' was overwritten with penalty, restore it from amount_due or calculate it
        double? baseRentToPreserve;
        if (rental['amount_due'] != null) {
          baseRentToPreserve = (rental['amount_due'] as num).toDouble();
        } else {
          // Calculate base rent from rental hours and price per hour
          try {
            final pricePerHour = (rental['products']?['price'] ?? 0).toDouble();
            int rentalHours = rental['rental_days'] ?? 0;
            if (rentalHours == 0) rentalHours = 1;
            baseRentToPreserve = (rentalHours * pricePerHour).toDouble();
          } catch (_) {
            // If calculation fails, keep existing amount (might be base rent already)
            baseRentToPreserve = rental['amount'] != null ? (rental['amount'] as num).toDouble() : null;
          }
        }
        
        // Build update object - only update late_charge and payment status, preserve base rent in 'amount'
        final updateData = <String, dynamic>{
          'payment_status': 'paid',
          'paid_at': DateTime.now().toIso8601String(),
          'late_charge': penaltyAmount, // Update late_charge when penalty is approved
          // DO NOT change status to 'active' - rental usage is ending, renter must return
        };
        
        // Only update 'amount' if we have a valid base rent value to preserve
        if (baseRentToPreserve != null && baseRentToPreserve > 0) {
          updateData['amount'] = baseRentToPreserve.toString();
          debugPrint('[Approval] Preserving base rent: ₹${baseRentToPreserve.toStringAsFixed(2)} in amount field');
        }
        
        await SupabaseService.client.from('rentals').update(updateData).eq('id', rental['id']);
        
        // Mark product as NOT rented (available) - renter can no longer use it, must return
        try {
          await SupabaseService.client.from('products').update({
            'is_rented': false,
            'renter_id': null,
            'rented_at': null,
          }).eq('id', rental['product_id']);
        } catch (_) {}
        
        // Also update payment record status to 'paid'
        // Always try to find and update the payment record for this penalty payment
        String? updatedPaymentId;
        final now = DateTime.now();
        
        debugPrint('[Approval] === STARTING PAYMENT RECORD UPDATE ===');
        debugPrint('[Approval] Rental ID: ${rental['id']}');
        debugPrint('[Approval] Latest payment ID: ${rental['latest_payment']?['id']}');
        debugPrint('[Approval] Latest payment status: ${rental['latest_payment']?['status']}');
        
        // First, try using latest_payment if available
        if (rental['latest_payment']?['id'] != null) {
          final paymentId = rental['latest_payment']['id'].toString();
          try {
            debugPrint('[Approval] Step 1: Updating payment $paymentId from status ${rental['latest_payment']?['status']} to paid');
            final result = await SupabaseService.client
                .from('payments')
                .update({
                  'status': 'paid',
                  'paid_at': now.toIso8601String(),
                })
                .eq('id', paymentId)
                .select();
            debugPrint('[Approval] Update result: ${result.toString()}');
            if (result != null && result.isNotEmpty) {
              updatedPaymentId = paymentId;
              debugPrint('✓ Successfully updated payment $paymentId status to paid');
              // Verify the update immediately
              await Future.delayed(const Duration(milliseconds: 200));
              final verify = await SupabaseService.client
                  .from('payments')
                  .select('status')
                  .eq('id', paymentId)
                  .maybeSingle();
              debugPrint('✓ Verification: payment $paymentId now has status: ${verify?['status']}');
            } else {
              debugPrint('⚠ No rows updated for payment $paymentId - trying alternative approach');
            }
          } catch (e, stackTrace) {
            debugPrint('✗ Error updating payment $paymentId: $e');
            debugPrint('✗ Stack trace: $stackTrace');
          }
        } else {
          debugPrint('[Approval] latest_payment is null, will search by rental_id');
        }
        
        // If payment wasn't found in latest_payment, search by rental_id
        if (updatedPaymentId == null) {
          try {
            debugPrint('[Approval] Step 2: Searching for payment records for rental ${rental['id']}');
            // Look for the most recent payment with status 'submitted' or 'awaiting_payment' (penalty payment)
            final payments = await SupabaseService.client
                .from('payments')
                .select('*')
                .eq('rental_id', rental['id'])
                .inFilter('status', ['submitted', 'awaiting_payment', 'pending'])
                .order('created_at', ascending: false)
                .limit(1);
            
            debugPrint('[Approval] Found ${payments.length} payments with status submitted/awaiting_payment/pending');
            
            if (payments.isNotEmpty && payments[0]['id'] != null) {
              final paymentId = payments[0]['id'].toString();
              debugPrint('[Approval] Found payment $paymentId with status ${payments[0]['status']}');
              final result = await SupabaseService.client
                  .from('payments')
                  .update({
                    'status': 'paid',
                    'paid_at': now.toIso8601String(),
                  })
                  .eq('id', paymentId)
                  .select();
              debugPrint('[Approval] Update result: ${result.toString()}');
              if (result != null && result.isNotEmpty) {
                updatedPaymentId = paymentId;
                debugPrint('✓ Successfully updated payment $paymentId status to paid (found by rental_id)');
              } else {
                debugPrint('⚠ Update query returned empty result');
              }
            } else {
              debugPrint('[Approval] No payments with status submitted/awaiting_payment/pending, trying fallback');
              // Fallback: get the most recent payment regardless of status
              final allPayments = await SupabaseService.client
                  .from('payments')
                  .select('*')
                  .eq('rental_id', rental['id'])
                  .order('created_at', ascending: false)
                  .limit(1);
              
              debugPrint('[Approval] Found ${allPayments.length} total payments');
              
              if (allPayments.isNotEmpty && allPayments[0]['id'] != null) {
                final paymentId = allPayments[0]['id'].toString();
                debugPrint('[Approval] Using fallback: payment $paymentId with status ${allPayments[0]['status']}');
                final result = await SupabaseService.client
                    .from('payments')
                    .update({
                      'status': 'paid',
                      'paid_at': now.toIso8601String(),
                    })
                    .eq('id', paymentId)
                    .select();
                debugPrint('[Approval] Fallback update result: ${result.toString()}');
                if (result != null && result.isNotEmpty) {
                  updatedPaymentId = paymentId;
                  debugPrint('✓ Successfully updated payment $paymentId status to paid (fallback)');
                } else {
                  debugPrint('⚠ Fallback update query returned empty result');
                }
              } else {
                debugPrint('⚠ No payments found at all for rental ${rental['id']}');
              }
            }
          } catch (e, stackTrace) {
            debugPrint('✗ Error finding/updating payment record: $e');
            debugPrint('✗ Stack trace: $stackTrace');
          }
        }
        
        if (updatedPaymentId == null) {
          debugPrint('⚠⚠⚠ WARNING: Could not find or update payment record for rental ${rental['id']}');
          // Try one more time with a direct query using the payment_id from rental
          if (rental['payment_id'] != null) {
            try {
              final directPaymentId = rental['payment_id'].toString();
              debugPrint('[Approval] Retry: Attempting direct update of payment_id $directPaymentId');
              final retryResult = await SupabaseService.client
                  .from('payments')
                  .update({
                    'status': 'paid',
                    'paid_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', directPaymentId)
                  .select();
              if (retryResult != null && retryResult.isNotEmpty) {
                debugPrint('✓ Retry successful: Updated payment $directPaymentId status to paid');
                updatedPaymentId = directPaymentId;
              } else {
                debugPrint('✗ Retry failed: No rows updated for payment $directPaymentId');
              }
            } catch (e) {
              debugPrint('✗ Retry error: $e');
            }
          }
        } else {
          debugPrint('[Approval] === PAYMENT RECORD UPDATE COMPLETE: $updatedPaymentId ===');
        }
      }
      if (mounted) {
        Navigator.pop(context);
        
        // Force a refresh by clearing state and reloading
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }
        
        // Add a delay to ensure database updates are committed and propagated
        // Increased delay for better reliability
        await Future.delayed(const Duration(milliseconds: 1500));
        
        // Reload rentals to update UI with new payment status
        await _loadRentals();
        
        // Add another small delay and force another rebuild to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Force another rebuild to ensure UI updates
        if (mounted) {
          setState(() {});
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPenaltyPayment 
              ? 'Penalty payment approved! Renter can now request return.'
              : 'Payment approved! Rental is now active.'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve payment: $e')),
        );
      }
    }
  }

  Future<void> _rejectPayment(Map<String, dynamic> rental) async {
    try {
      // Reset rental payment status and mark last payment as rejected if exists
      await SupabaseService.client.from('rentals').update({
        'status': 'awaiting_payment',
        'payment_status': 'pending',
      }).eq('id', rental['id']);

      if (rental['latest_payment']?['id'] != null) {
        await SupabaseService.client.from('payments').update({
          'status': 'rejected',
        }).eq('id', rental['latest_payment']['id']);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment rejected. Renter will be notified to provide new proof.'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
        _loadRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject payment: $e')),
        );
      }
    }
  }

  Future<void> _cancelRental(Map<String, dynamic> rental) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel Rental'),
          content: const Text('Are you sure you want to cancel this rental? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Mark rental as cancelled
        await SupabaseService.client.from('rentals').update({
          'status': 'cancelled',
          'payment_status': 'cancelled',
        }).eq('id', rental['id']);

        // Mark product as available
        await SupabaseService.client.from('products').update({
          'is_rented': false,
          'renter_id': null,
          'rented_at': null,
        }).eq('id', rental['product_id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rental cancelled successfully. Product is now available.'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          _loadRentals();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel rental: $e')),
        );
      }
    }
  }

  Widget _buildAmountRow(String label, double amount, {bool isPenalty = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
          ),
        ),
      ],
    );
  }

  void _navigateToPayment(Map<String, dynamic> rental) {
    // Extract payment info from product
    final product = rental['products'];
    final qrUrl = product?['qr_code_url'];
    final upiId = product?['upi_id'];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentDashboard(
          rentalId: rental['id'],
          productId: rental['product_id'],
          ownerId: rental['user_id'],
          qrCodeUrl: qrUrl,
          upiId: upiId,
        ),
      ),
    ).then((_) => _loadRentals()); // Refresh after payment
  }

  void _showReturnModal(Map<String, dynamic> rental) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RentalReturnModal(
        rental: rental,
        onReturnComplete: () => _loadRentals(),
      ),
    );
  }

  Future<void> _requestReturn(Map<String, dynamic> rental) async {
    try {
      await SupabaseService.client.from('rentals').update({
        'payment_status': 'return_requested',
        'return_requested_at': DateTime.now().toIso8601String(),
      }).eq('id', rental['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Return requested. Owner will review and confirm.'),
            backgroundColor: Color(0xFF3B82F6),
          ),
        );
        _loadRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request return: $e')),
        );
      }
    }
  }
}

class _PaymentProofModal extends StatefulWidget {
  final Map<String, dynamic> rental;
  final PaymentBreakdown breakdown;
  final String? qrUrl;
  final String? upiId;
  final VoidCallback onPaymentSubmitted;

  const _PaymentProofModal({
    required this.rental,
    required this.breakdown,
    this.qrUrl,
    this.upiId,
    required this.onPaymentSubmitted,
  });

  @override
  State<_PaymentProofModal> createState() => _PaymentProofModalState();
}

class _PaymentProofModalState extends State<_PaymentProofModal> {
  final _transactionIdController = TextEditingController();
  final _notesController = TextEditingController();
  String? _paymentScreenshot;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _transactionIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          // Upload to Supabase Storage
          final fileName = 'payment_${DateTime.now().millisecondsSinceEpoch}.${file.extension}';
          final fileBytes = await File(file.path!).readAsBytes();
          
          final uploadResult = await SupabaseService.client.storage
              .from('payment_screenshots')
              .uploadBinary(fileName, fileBytes);

          if (uploadResult != null) {
            final publicUrl = SupabaseService.client.storage
                .from('payment_screenshots')
                .getPublicUrl(fileName);

            setState(() {
              _paymentScreenshot = publicUrl;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload screenshot: $e')),
        );
      }
    }
  }

  Future<void> _submitPayment() async {
    if (_transactionIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter transaction ID')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Update rental with payment proof
      await SupabaseService.client.from('rentals').update({
        'transaction_id': _transactionIdController.text.trim(),
        'payment_screenshot': _paymentScreenshot,
        'notes': _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        'status': 'awaiting_payment', // Owner needs to verify
      }).eq('id', widget.rental['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment proof submitted! Owner will verify your payment.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        widget.onPaymentSubmitted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit payment proof: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Payment Proof Required'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Payment breakdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAmountRow('Penalty Amount', widget.breakdown.penalty, isPenalty: true),
                  const SizedBox(height: 8),
                  _buildAmountRow('Total Amount', widget.breakdown.total, isTotal: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // QR Code
            if (widget.qrUrl != null) ...[
              const Text('Owner\'s QR Code:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.qrUrl!,
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
              const SizedBox(height: 16),
            ],
            
            // UPI ID
            if (widget.upiId != null) ...[
              const Text('Owner\'s UPI ID:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(widget.upiId!),
              ),
              const SizedBox(height: 16),
            ],
            
            // Transaction ID
            TextField(
              controller: _transactionIdController,
              decoration: const InputDecoration(
                labelText: 'Transaction ID *',
                hintText: 'Enter UPI transaction ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Payment Screenshot
            const Text('Payment Screenshot:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_paymentScreenshot != null) ...[
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _paymentScreenshot!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Colors.red),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            ElevatedButton.icon(
              onPressed: _pickScreenshot,
              icon: const Icon(Icons.camera_alt),
              label: Text(_paymentScreenshot != null ? 'Change Screenshot' : 'Upload Screenshot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue,
                side: BorderSide(color: Colors.blue.shade200),
              ),
            ),
            const SizedBox(height: 16),
            
            // Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Additional Notes (Optional)',
                hintText: 'Any additional information for the owner',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            const Text(
              'After making payment, upload the screenshot and enter transaction details. The owner will verify your payment.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007BFF),
          ),
          child: _isSubmitting 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Payment Proof'),
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
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
            color: isPenalty ? const Color(0xFFDC2626) : const Color(0xFF111111),
          ),
        ),
      ],
    );
  }
}
