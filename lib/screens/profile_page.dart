// File: lib/screens/profile_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:rental_app/screens/login_page.dart';
import 'package:rental_app/screens/my_listed_products_page.dart';
import 'package:rental_app/screens/rental_history_page.dart';
import 'package:rental_app/screens/rental_management_page.dart';
import 'package:rental_app/screens/qr_upload_modal.dart';
import 'package:rental_app/screens/payment_dashboard.dart';
import 'package:file_picker/file_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  List<Map<String, dynamic>> _listedProducts = [];
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _stateController = TextEditingController();
  final _districtController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _localityController = TextEditingController();
  final SupabaseService _supabase = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchListedProducts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _stateController.dispose();
    _districtController.dispose();
    _pincodeController.dispose();
    _localityController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _userData = data;
        _isLoading = false;

        if (data != null) {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _stateController.text = data['state'] ?? '';
          _districtController.text = data['district'] ?? '';
          _pincodeController.text = data['pincode'] ?? '';
          _localityController.text = data['locality'] ?? '';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      final user = context.read<AuthProvider>().user;
      if (user == null) return;

      await SupabaseService.client.from('profiles').update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'state': _stateController.text.trim(),
        'district': _districtController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'locality': _localityController.text.trim(),
      }).eq('id', user.id);

      setState(() => _isEditing = false);
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    }
  }

  Future<void> _fetchListedProducts() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    try {
      final data = await SupabaseService.client
          .from('products')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _listedProducts = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error fetching products: $e')));
      }
    }
  }

  Future<void> _uploadQR(String productId, String? existingQRUrl, String? existingUPIId) async {
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

  /// NEW: Handle Return with Late Penalty from Profile Page
  Future<void> _handleReturn(Map<String, dynamic> product) async {
    try {
      final rentalId = product['rental_id'];
      final rentalDays = product['rental_days'] ?? 1;
      final pricePerDay = product['price']?.toDouble() ?? 0;
      final rentedAt = DateTime.parse(product['rented_at']);
      final dueDate = rentedAt.add(Duration(days: rentalDays));
      final now = DateTime.now();

      int overdueDays = 0;
      if (now.isAfter(dueDate)) {
        overdueDays = now.difference(dueDate).inDays;
      }

      final qrUrl = product['qr_code_url'];
      if (qrUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Owner has not uploaded QR code yet')),
        );
        return;
      }

      double penalty = (overdueDays * (pricePerDay * 0.5)).toDouble();

      if (overdueDays > 0) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Late Return Penalty'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Product is returned $overdueDays day(s) late.'),
                const SizedBox(height: 12),
                Text('Penalty amount: ₹$penalty'),
                const SizedBox(height: 12),
                Image.network(qrUrl),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await _supabase.markRentalAsPaid(
                    rentalId: rentalId,
                    amountPaid: penalty,
                  );
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Penalty paid successfully!')),
                  );
                  await _supabase.markRentalAsReturned(rentalId: rentalId);
                  await _fetchListedProducts();
                },
                child: const Text('I Have Paid Penalty'),
              ),
            ],
          ),
        );
      } else {
        await _supabase.markRentalAsReturned(rentalId: rentalId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product returned successfully!')),
        );
        await _fetchListedProducts();
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to return product: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _isEditing ? _buildEditForm() : _buildProfileView(),
            ),
    );
  }

  Widget _buildProfileView() {
    if (_userData == null) return const Center(child: Text("No profile data found"));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
              const SizedBox(height: 16),
              Text(_userData?['name'] ?? 'User', style: Theme.of(context).textTheme.headlineSmall),
              Text(_userData?['email'] ?? '',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Information',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildDetailRow('Name', _userData?['name']),
                _buildDetailRow('Phone', _userData?['phone']),
                _buildDetailRow('Member Since', _formatDate(_userData?['created_at'])),
                _buildDetailRow('State', _userData?['state']),
                _buildDetailRow('District', _userData?['district']),
                _buildDetailRow('Pincode', _userData?['pincode']),
                _buildDetailRow('Locality', _userData?['locality']),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          title: 'My Listed Products',
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF007BFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF007BFF),
                  size: 28,
                ),
              ),
              title: const Text(
                'Manage My Products',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                _listedProducts.isEmpty
                    ? 'No products listed yet. Tap to add products.'
                    : '${_listedProducts.length} product${_listedProducts.length == 1 ? '' : 's'} listed. Tap to view and setup.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Color(0xFF6B7280),
              ),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyListedProductsPage()),
                );
                // Refresh products when returning from My Listed Products page
                if (result == true || mounted) {
                  await _fetchListedProducts();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          title: 'My Activities',
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('My Listed Products'),
              subtitle: const Text('View your listed products'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyListedProductsPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Rental History'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RentalHistoryPage())),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Rental Management'),
              subtitle: const Text('Manage active rentals and process returns'),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const RentalManagementPage())),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          title: 'Account',
          children: [
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () => _showLogoutDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 48,
                  color: theme.primaryColor,
                ),
                const SizedBox(height: 12),
                Text(
                  'Update Profile',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111111),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your personal information',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Form Section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'Enter your full name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'Enter your phone number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please enter a phone number';
                        if (!RegExp(r'^\+?[0-9]{10,13}$').hasMatch(v)) return 'Enter a valid phone number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _stateController,
                      decoration: InputDecoration(
                        labelText: 'State',
                        hintText: 'Enter your state',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _districtController,
                      decoration: InputDecoration(
                        labelText: 'District',
                        hintText: 'Enter your district',
                        prefixIcon: const Icon(Icons.location_city_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pincodeController,
                      decoration: InputDecoration(
                        labelText: 'Pincode',
                        hintText: 'Enter 6-digit pincode',
                        prefixIcon: const Icon(Icons.pin_drop_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _localityController,
                      decoration: InputDecoration(
                        labelText: 'Locality',
                        hintText: 'Enter your locality/address',
                        prefixIcon: const Icon(Icons.home_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _isEditing = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _updateProfile,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    final displayValue = (value == null || value.toString().isEmpty) ? 'Not set' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(flex: 3, child: Text(displayValue, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Card(margin: const EdgeInsets.symmetric(horizontal: 8), child: Column(children: children)),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    // Capture the outer context before showing dialog
    final outerContext = context;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 12),
              // Message
              const Text(
                'Are you sure you want to logout?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        // Close dialog first
                        Navigator.pop(dialogContext);
                        // Wait a frame to ensure dialog is fully closed
                        await Future.delayed(const Duration(milliseconds: 100));
                        // Sign out using the outer context
                        await outerContext.read<AuthProvider>().signOut();
                        // Navigate using the outer context with rootNavigator
                        if (outerContext.mounted) {
                          Navigator.of(outerContext, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                            (route) => false,
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Not available';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'Not available';
    return '${date.day}/${date.month}/${date.year}';
  }
}




