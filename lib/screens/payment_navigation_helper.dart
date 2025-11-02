import 'package:flutter/material.dart';
import 'package:rental_app/screens/payment_dashboard.dart';

class PaymentNavigationHelper {
  /// Navigate to payment dashboard for a rental
  static Future<void> navigateToPayment({
    required BuildContext context,
    required String rentalId,
    required String productId,
    required String ownerId,
    String? qrCodeUrl,
    String? upiId,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentDashboard(
          rentalId: rentalId,
          productId: productId,
          ownerId: ownerId,
          qrCodeUrl: qrCodeUrl,
          upiId: upiId,
        ),
      ),
    );
  }

  /// Show payment options for a rental
  static Future<void> showPaymentOptions({
    required BuildContext context,
    required String rentalId,
    required String productId,
    required String ownerId,
    required String productName,
    required double amount,
    String? qrCodeUrl,
    String? upiId,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                    'Payment Options',
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Product info
                    Container(
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
                          Text(
                            productName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111111),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Amount: ₹${amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Payment methods
                    if (qrCodeUrl != null || upiId != null) ...[
                      const Text(
                        'Available Payment Methods',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111111),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      if (qrCodeUrl != null)
                        _buildPaymentMethodCard(
                          context: context,
                          title: 'QR Code Payment',
                          subtitle: 'Scan QR code to pay',
                          icon: Icons.qr_code_2,
                          color: const Color(0xFF007BFF),
                          onTap: () {
                            Navigator.pop(context);
                            navigateToPayment(
                              context: context,
                              rentalId: rentalId,
                              productId: productId,
                              ownerId: ownerId,
                              qrCodeUrl: qrCodeUrl,
                              upiId: upiId,
                            );
                          },
                        ),
                      
                      if (qrCodeUrl != null && upiId != null)
                        const SizedBox(height: 12),
                      
                      if (upiId != null)
                        _buildPaymentMethodCard(
                          context: context,
                          title: 'UPI Payment',
                          subtitle: 'Pay directly via UPI',
                          icon: Icons.account_balance_wallet,
                          color: const Color(0xFF10B981),
                          onTap: () {
                            Navigator.pop(context);
                            navigateToPayment(
                              context: context,
                              rentalId: rentalId,
                              productId: productId,
                              ownerId: ownerId,
                              qrCodeUrl: qrCodeUrl,
                              upiId: upiId,
                            );
                          },
                        ),
                    ] else ...[
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
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPaymentMethodCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
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
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 4),
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
            Icon(
              Icons.arrow_forward_ios,
              color: const Color(0xFF6B7280),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
