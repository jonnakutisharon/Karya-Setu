// File: lib/screens/my_listed_products_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:rental_app/screens/terms_and_conditions_page.dart';
import 'package:rental_app/screens/login_page.dart';
import 'package:rental_app/screens/rental_management_page.dart';
import 'package:rental_app/screens/qr_scan_page.dart';
import 'package:rental_app/screens/qr_upload_modal.dart';

class MyListedProductsPage extends StatefulWidget {
  const MyListedProductsPage({super.key});

  @override
  State<MyListedProductsPage> createState() => _MyListedProductsPageState();
}

class _MyListedProductsPageState extends State<MyListedProductsPage> {
  List<Map<String, dynamic>> _listedProducts = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0 for Available, 1 for Rented
  final SupabaseService _supabase = SupabaseService();

  @override
  void initState() {
    super.initState();
    _fetchListedProducts();
  }

  Future<void> _fetchListedProducts() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final data = await SupabaseService.client
          .from('products')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _listedProducts = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error fetching products: $e')));
    }
  }

  List<Map<String, dynamic>> get _availableProducts {
    return _listedProducts.where((product) => product['is_rented'] != true).toList();
  }

  List<Map<String, dynamic>> get _rentedProducts {
    return _listedProducts.where((product) => product['is_rented'] == true).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Listed Products')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _listedProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFF9CA3AF)),
                      const SizedBox(height: 12),
                      const Text('No products listed'),
                      const SizedBox(height: 6),
                      Text(
                        'List a product to start receiving rental requests.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
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
                              title: 'Available',
                              icon: Icons.check_circle,
                              iconColor: const Color(0xFF10B981),
                              isSelected: _selectedTabIndex == 0,
                              count: _availableProducts.length,
                              onTap: () {
                                setState(() {
                                  _selectedTabIndex = 0;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: _buildTabButton(
                              title: 'Rented',
                              icon: Icons.inventory,
                              iconColor: const Color(0xFF007BFF),
                              isSelected: _selectedTabIndex == 1,
                              count: _rentedProducts.length,
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
                        onRefresh: _fetchListedProducts,
                        child: _selectedTabIndex == 0
                            ? _buildAvailableContent()
                            : _buildRentedContent(),
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

  Widget _buildAvailableContent() {
    if (_availableProducts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No available products.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _availableProducts.length,
      itemBuilder: (context, index) {
        final product = _availableProducts[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildRentedContent() {
    if (_rentedProducts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No rented products.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _rentedProducts.length,
      itemBuilder: (context, index) {
        final product = _rentedProducts[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final images =
        (product['images'] as List?)?.cast<String>() ?? [];
    final isRented = product['is_rented'] == true;
    final hasQr = product['qr_code_url'] != null && (product['qr_code_url'] as String).isNotEmpty;
    final hasUpi = product['upi_id'] != null && (product['upi_id'] as String).isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            GestureDetector(
              onTap: () => _showFullScreenImage(context, images),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: images.first,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    ),
                    // Show indicator if multiple images
                    if (images.length > 1)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${images.length} images',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'] ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  product['description'] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${(product['price'] is num ? (product['price'] as num).toDouble() : double.tryParse(product['price']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}/day',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 8),
                Text(
                  '${product['category']} > ${product['subcategory']}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip(
                      isRented ? 'Rented' : 'Available',
                      isRented ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                    ),
                    _buildChip(
                      hasQr ? 'QR Added' : 'QR Missing',
                      hasQr ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                    _buildChip(
                      hasUpi ? 'UPI Set' : 'UPI Missing',
                      hasUpi ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RentalManagementPage(),
                          ),
                        ).then((_) => _fetchListedProducts()),
                        child: Text(isRented ? 'View Current Rental' : 'View Rental Connections'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _uploadQR(product['id']),
                        child: Text(hasQr || hasUpi ? 'Update QR/UPI' : 'Setup QR/UPI'),
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

  /// Handle Rent Flow
  Future<void> _handleRent(BuildContext context, Map<String, dynamic> product) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please login to rent products')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
      return;
    }

    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TermsAndConditionsPage(
          onAccept: () => Navigator.pop(context, true),
          onDecline: () => Navigator.pop(context, false),
        ),
      );
      if (accepted != true) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final rental = await _supabase.rentProduct(
        productId: product['id'],
        renterId: authProvider.user!.id,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      int rentalDays = 1;
      final pricePerDay = product['price']?.toDouble() ?? 0;

      final daysSelected = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Select Rental Days'),
          content: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Price per day: ₹$pricePerDay'),
                const SizedBox(height: 12),
                DropdownButton<int>(
                  value: rentalDays,
                  items: List.generate(30, (index) => index + 1)
                      .map((day) => DropdownMenuItem(value: day, child: Text("$day Days")))
                      .toList(),
                  onChanged: (val) => setState(() => rentalDays = val ?? 1),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total: ₹${_supabase.calculateRentalAmount(pricePerDay: pricePerDay, rentalDays: rentalDays)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, rentalDays), child: const Text('Proceed')),
          ],
        ),
      );

      if (daysSelected == null) return;

      await _supabase.updateRentalDays(
        rentalId: rental['id'],
        rentalDays: daysSelected,
        pricePerDay: pricePerDay,
      );

      final qrUrl = product['qr_code_url'];
      if (qrUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Owner has not uploaded QR code yet')),
        );
        return;
      }

      // Navigate to QRScanPage for payment (amount calculated internally)
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QRScanPage(rentalId: rental['id']),
        ),
      );

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rental Confirmed'),
          content: Text('You have rented "${product['name']}" for $daysSelected day(s).'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RentalManagementPage()),
                );
              },
              child: const Text('View Rental Connections'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to process rental. Please try again later.\n\nError: ${e.toString()}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  /// Handle Return Flow
  Future<void> _handleReturn(BuildContext context, Map<String, dynamic> product) async {
    try {
      final rentalId = product['rental_id'];
      final rentalDays = product['rental_days'] ?? 1;
      final pricePerDay = product['price']?.toDouble() ?? 0;
      final rentedAt = DateTime.parse(product['rented_at']);
      final dueDate = rentedAt.add(Duration(days: rentalDays));
      final now = DateTime.now();

      int overdueDays = 0;
      if (now.isAfter(dueDate)) overdueDays = now.difference(dueDate).inDays;

      final qrUrl = product['qr_code_url'];
      if (qrUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Owner has not uploaded QR code yet')),
        );
        return;
      }

      double penalty = (overdueDays * (pricePerDay * 0.5)).toDouble(); // 50% penalty

      if (overdueDays > 0) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QRScanPage(rentalId: rentalId),
          ),
        );
      }

      await _supabase.markRentalAsReturned(rentalId: rentalId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product returned successfully!')),
      );
      await _fetchListedProducts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to return product: $e')),
      );
    }
  }

  /// Upload QR and UPI for owner
  Future<void> _uploadQR(String productId) async {
    final product = _listedProducts.firstWhere((prod) => prod['id'] == productId);
    final existingQRUrl = product['qr_code_url'] as String?;
    final existingUPIId = product['upi_id'] as String?;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QRUploadModal(
        productId: productId,
        existingQRUrl: existingQRUrl,
        existingUPIId: existingUPIId,
        onUploadComplete: () {
          _fetchListedProducts(); // refresh products
        },
      ),
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
                    child: CachedNetworkImage(
                      imageUrl: images[index],
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
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

// Helper: status/capability chip for product list
Widget _buildChip(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}
