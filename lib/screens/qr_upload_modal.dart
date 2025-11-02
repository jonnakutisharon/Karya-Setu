import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:rental_app/models/payment_model.dart';
import 'package:rental_app/services/supabase_service.dart';

class QRUploadModal extends StatefulWidget {
  final String productId;
  final String? existingQRUrl;
  final String? existingUPIId;
  final VoidCallback onUploadComplete;

  const QRUploadModal({
    super.key,
    required this.productId,
    this.existingQRUrl,
    this.existingUPIId,
    required this.onUploadComplete,
  });

  @override
  State<QRUploadModal> createState() => _QRUploadModalState();
}

class _QRUploadModalState extends State<QRUploadModal> {
  final _upiIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isUploading = false;
  String? _selectedQRImage;
  UPIInfo? _upiInfo;

  @override
  void initState() {
    super.initState();
    _upiIdController.text = widget.existingUPIId ?? '';
    if (_upiIdController.text.isNotEmpty) {
      _validateUPI(_upiIdController.text);
    }
  }

  @override
  void dispose() {
    _upiIdController.dispose();
    super.dispose();
  }

  void _validateUPI(String upiString) {
    setState(() {
      _upiInfo = UPIInfo.parseUPI(upiString);
    });
  }

  Future<void> _selectQRImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedQRImage = result.files.first.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select image: $e')),
      );
    }
  }

  Future<void> _uploadQRCode() async {
    // Check if at least one payment method is provided
    if (_selectedQRImage == null && (_upiIdController.text.trim().isEmpty || _upiInfo?.isValid != true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide at least one payment method (QR code or valid UPI ID)')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final updates = <String, dynamic>{};

      // Upload QR code if provided
      if (_selectedQRImage != null) {
        try {
          final qrFile = File(_selectedQRImage!);
          if (!await qrFile.exists()) {
            throw Exception('QR image file does not exist');
          }
          
          final qrUrl = await SupabaseService().uploadQrCode(
            productId: widget.productId,
            qrImage: qrFile,
          );
          updates['qr_code_url'] = qrUrl;
          print('QR code uploaded successfully: $qrUrl');
        } catch (e) {
          print('Error uploading QR code: $e');
          // For now, let's allow saving UPI ID even if QR upload fails
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('QR upload failed, but you can still save UPI ID: $e')),
          );
          // Don't throw error, continue with UPI ID if available
        }
      }

      // Add UPI ID if provided and valid
      if (_upiIdController.text.trim().isNotEmpty && _upiInfo?.isValid == true) {
        updates['upi_id'] = _upiIdController.text.trim();
        print('UPI ID added: ${_upiIdController.text.trim()}');
      }

      // Update product with payment methods
      if (updates.isNotEmpty) {
        print('Updating product with: $updates');
        final result = await SupabaseService.client
            .from('products')
            .update(updates)
            .eq('id', widget.productId)
            .select();
        print('Product update result: $result');
      } else {
        // If no updates were made (e.g., QR upload failed and no UPI ID), show error
        throw Exception('No payment methods to update. Please provide at least one valid payment method.');
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onUploadComplete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment methods updated successfully!')),
        );
      }
    } catch (e) {
      print('Error in _uploadQRCode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Setup Payment Methods',
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQRUploadSection(),
                    const SizedBox(height: 32),
                    _buildUPISection(),
                    const SizedBox(height: 100), // Space for button
                  ],
                ),
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
                onPressed: _isUploading ? null : _uploadQRCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Payment Methods',
                        style: TextStyle(
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

  Widget _buildQRUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QR Code Upload',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Upload your QR code image (PNG, JPG)',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 16),
        
        // QR Code Preview/Upload Area
        InkWell(
          onTap: _selectQRImage,
          child: Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: _selectedQRImage != null || widget.existingQRUrl != null 
                  ? Colors.white 
                  : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _selectedQRImage != null || widget.existingQRUrl != null 
                    ? const Color(0xFF10B981) 
                    : const Color(0xFFE5E7EB),
                style: BorderStyle.solid,
                width: 2,
              ),
            ),
            child: _selectedQRImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_selectedQRImage!),
                      fit: BoxFit.cover,
                    ),
                  )
                : widget.existingQRUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          widget.existingQRUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildUploadPlaceholder();
                          },
                        ),
                      )
                    : _buildUploadPlaceholder(),
          ),
        ),
        
        if (_selectedQRImage != null || widget.existingQRUrl != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 16),
              const SizedBox(width: 8),
              const Text(
                'QR code ready',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_2, size: 48, color: Color(0xFF6B7280)),
        SizedBox(height: 12),
        Text(
          'Tap to upload QR code',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'PNG, JPG up to 10MB',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }

  Widget _buildUPISection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'UPI ID (Optional)',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add your UPI ID for direct payments',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _upiIdController,
          decoration: InputDecoration(
            labelText: 'UPI ID',
            hintText: 'yourname@paytm, yourname@ybl, etc.',
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            prefixIcon: const Icon(Icons.account_balance_wallet),
            suffixIcon: _upiInfo != null
                ? Icon(
                    _upiInfo!.isValid ? Icons.check_circle : Icons.error,
                    color: _upiInfo!.isValid ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                  )
                : null,
          ),
          onChanged: _validateUPI,
          validator: (value) {
            if (value != null && value.trim().isNotEmpty) {
              final upiInfo = UPIInfo.parseUPI(value.trim());
              if (!upiInfo.isValid) {
                return 'Please enter a valid UPI ID (e.g., yourname@paytm)';
              }
            }
            return null;
          },
        ),
        
        if (_upiInfo != null && _upiInfo!.isValid) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Valid UPI ID',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (_upiInfo!.displayName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Name: ${_upiInfo!.displayName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
                if (_upiInfo!.bankName != null) ...[
                  Text(
                    'Bank: ${_upiInfo!.bankName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        
        if (_upiInfo != null && !_upiInfo!.isValid && _upiIdController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: const Color(0xFFDC2626), size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Invalid UPI ID format. Use format: yourname@bank',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
