// File: lib/screens/terms_and_conditions_page.dart
import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const TermsAndConditionsPage({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final padding = screenWidth < 400 ? 16.0 : 20.0;
          return Container(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            padding: EdgeInsets.symmetric(horizontal: padding, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description,
                    color: Color(0xFF3B82F6),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Terms and Conditions',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF111111),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      number: '1',
                      title: 'Rental Agreement',
                      content: 'By accepting these terms, you enter into a rental agreement with the owner. The rental period begins only after the owner approves your request and confirms payment receipt.',
                    ),
                    const SizedBox(height: 20),
                    
                    _buildSection(
                      number: '2',
                      title: 'Your Responsibilities',
                      children: [
                        _buildBulletPoint('You are fully responsible for the item during the rental period'),
                        _buildBulletPoint('Report any damages or issues immediately to the owner'),
                        _buildBulletPoint('Return the item in the same condition as received'),
                        _buildBulletPoint('Pay for any damages, losses, or late return fees'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    _buildSection(
                      number: '3',
                      title: 'Rental Period',
                      children: [
                        _buildBulletPoint('The rental period begins when the owner approves your request'),
                        _buildBulletPoint('You must return the item by the agreed-upon date and time'),
                        _buildBulletPoint('Late returns will incur overtime charges based on hourly rates'),
                        _buildBulletPoint('Overtime charges accumulate until the item is returned'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    _buildSection(
                      number: '4',
                      title: 'Payment Terms',
                      children: [
                        _buildBulletPoint('All payments are processed securely through the platform'),
                        _buildBulletPoint('Rental fees are charged upfront before the rental begins'),
                        _buildBulletPoint('Owner must verify your payment proof before approving the rental'),
                        _buildBulletPoint('Additional charges may apply for damages, late returns, or overtime'),
                        _buildBulletPoint('All payments are final once approved by the owner'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    _buildSection(
                      number: '5',
                      title: 'Cancellation Policy',
                      children: [
                        _buildBulletPoint('Cancellations must be made at least 24 hours before the approved rental start time'),
                        _buildBulletPoint('Refunds are subject to the platform\'s refund policy'),
                        _buildBulletPoint('Late cancellations may result in partial or no refund'),
                        _buildBulletPoint('Once the rental period has started, cancellations are not permitted'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            
                // Action Buttons
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    TextButton(
                      onPressed: onDecline,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Accept & Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String number,
    required String title,
    String? content,
    List<Widget>? children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF111111),
                    ),
                  ),
                  if (content != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4B5563),
                        height: 1.5,
                      ),
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                  ],
                  if (children != null) ...[
                    const SizedBox(height: 8),
                    ...children,
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF3B82F6),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4B5563),
                height: 1.5,
              ),
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
