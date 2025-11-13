// File: lib/screens/rent_product_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rental_app/screens/login_page.dart';
import 'package:rental_app/screens/terms_and_conditions_page.dart';
import 'package:rental_app/screens/rental_flow_page.dart';

class RentProductPage extends StatelessWidget {
  const RentProductPage({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = SupabaseService();
    final authProvider = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Available Products')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.getProducts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data!;
          if (products.isEmpty) {
            return const Center(child: Text('No products available for rent'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              final List images = (p['images'] as List?) ?? const [];
              final String? imageUrl =
                  images.isNotEmpty ? images.first as String : null;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      GestureDetector(
                        onTap: () {
                          // Get all images if available, otherwise use single image
                          final images = (p['images'] as List?)?.cast<String>() ?? [imageUrl];
                          _showFullScreenImage(context, images);
                        },
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['name'] ?? 'Unnamed',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(p['description'] ?? ''),
                          const SizedBox(height: 8),
                          Text(
                            '₹${(p['price'] ?? 0).toString()} /day',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),

                          // Show QR if uploaded by owner
                          if (p['qr_code_url'] != null) ...[
                            const Text('Pay via QR Code:'),
                            const SizedBox(height: 8),
                            Image.network(
                              p['qr_code_url'],
                              height: 200,
                              width: 200,
                              fit: BoxFit.contain,
                            ),
                          ] else
                            const Text(
                                'QR code not yet uploaded by owner'),

                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: authProvider.user == null
                                  ? () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Please login to rent products')));
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const LoginPage(),
                                        ),
                                      );
                                    }
                                  : () async {
                                      // Continue to rental flow; payment methods will be handled there

                                      // Step 1: Terms & Conditions
                                      final accepted =
                                          await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              TermsAndConditionsPage(
                                            onAccept: () =>
                                                Navigator.pop(context, true),
                                            onDecline: () =>
                                                Navigator.pop(context, false),
                                          ),
                                        ),
                                      );
                                      if (accepted != true ||
                                          !context.mounted) return;

                                      // Route to rental flow where renter selects hours and pays
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RentalFlowPage(
                                            product: Map<String, dynamic>.from(p),
                                          ),
                                        ),
                                      );
                                    },
                              child: const Text('Rent Now'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _simulatePayment(
      BuildContext context, String productName) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Payment'),
            content:
                Text('Pay for "$productName"? (Simulated Payment)'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Pay'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _simulatePenaltyPayment(
      BuildContext context, double penaltyAmount) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Late Return Penalty'),
            content:
                Text('You have a late return penalty of ₹$penaltyAmount.\nPay now?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Pay'),
              ),
            ],
          ),
        ) ??
        false;
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




