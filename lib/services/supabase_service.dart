// File: lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class SupabaseService {
  /// Initialize Supabase client
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: 'https://mwahoublnmjfmhmlwxmw.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im13YWhvdWJsbm1qZm1obWx3eG13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU3NTQ5NzAsImV4cCI6MjA3MTMzMDk3MH0.zclMLWVdP30yAaV-fdHAKt-4zl3TeZ4apVOw38-0tCI',
        debug: true,
      );

      // Test connection
      final response =
          await Supabase.instance.client.from('users').select().limit(1);
      print('Supabase initialized successfully: $response');
    } catch (e) {
      print('Supabase initialization error: $e');
      rethrow;
    }
  }

  /// Get Supabase client
  static SupabaseClient get client => Supabase.instance.client;

  /// ------------------- AUTH METHODS -------------------
  Future<AuthResponse> signUp({
    required String phone,
    required String password,
    required String name,
    String? email,
  }) async {
    final response = await client.auth.signUp(
      phone: phone,
      password: password,
      data: {'name': name, 'email': email},
    );

    if (response.user != null) {
      await client.from('users').insert({
        'id': response.user!.id,
        'name': name,
        'phone': phone,
        'email': email,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async => await client.auth.signOut();
  Future<void> resetPassword(String email) async =>
      await client.auth.resetPasswordForEmail(email);
  Future<void> sendOtp(String phone) async {
    try {
      await client.auth.signInWithOtp(phone: phone);
    } catch (e) {
      throw Exception('Failed to send OTP: $e');
    }
  }

  /// ------------------- USER METHODS -------------------
  Future<void> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;

    if (updates.isNotEmpty) {
      await client.from('users').update(updates).eq('id', userId);
    }
  }

  Future<Map<String, dynamic>> getUserDetails(String userId) async {
    final data = await client.from('users').select().eq('id', userId).single();
    return data;
  }

  /// ------------------- PRODUCT METHODS -------------------
  Future<void> addProduct({
    required String userId,
    required String name,
    required String description,
    required double price,
    required String category,
    required String subcategory,
    required List<File> images,
  }) async {
    List<String> imageUrls = [];
    for (var image in images) {
      final imageUrl = await _uploadImage(image);
      imageUrls.add(imageUrl);
    }

    await client.from('products').insert({
      'user_id': userId,
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'subcategory': subcategory,
      'images': imageUrls,
      'created_at': DateTime.now().toIso8601String(),
      'is_rented': false,
    });
  }

  Future<String> _uploadImage(File image) async {
    final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = 'images/$fileName';
    final bytes = await image.readAsBytes();

    await client.storage.from('products').uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(cacheControl: '3600', upsert: true),
        );

    final imageUrl = client.storage.from('products').getPublicUrl(filePath);
    print('Image uploaded: $imageUrl');
    return imageUrl;
  }

  Stream<List<Map<String, dynamic>>> getProducts() {
    return client
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('is_rented', false)
        .order('created_at');
  }

  Stream<List<Map<String, dynamic>>> getProductsByCategory({
    required String category,
    required String subcategory,
  }) {
    return client.from('products').stream(primaryKey: ['id']).map((data) {
      final List<Map<String, dynamic>> products =
          List<Map<String, dynamic>>.from(data);
      return products
          .where((product) =>
              product['category'] == category &&
              product['subcategory'] == subcategory &&
              (product['is_rented'] == null || product['is_rented'] == false))
          .toList();
    });
  }

  /// ------------------- RENTAL METHODS -------------------
  Future<Map<String, dynamic>> rentProduct({
    required String productId,
    required String renterId,
  }) async {
    final product = await client
        .from('products')
        .select('user_id, price')
        .eq('id', productId)
        .single();

    if (product == null) throw Exception('Product not found');
    
    // IMPORTANT: Do NOT mark product as rented here. Only mark rented after owner approval.
    // Also, ensure product is not already rented by checking for active rentals
    final activeRentals = await client
        .from('rentals')
        .select('id')
        .eq('product_id', productId)
        .inFilter('status', ['active', 'pending_confirmation'])
        .isFilter('returned_at', null);
    
    if (activeRentals.isNotEmpty) {
      throw Exception('Product is already rented or has pending rentals');
    }

    // Create rental with a placeholder rented_at that will be updated on approval
    final now = DateTime.now();
    final rental = await client.from('rentals').insert({
      'product_id': productId,
      'renter_id': renterId,
      'user_id': product['user_id'],
      'status': 'pending_confirmation',
      'rented_at': now.toIso8601String(), // Set initial timestamp but rental time starts only on approval
      'payment_status': 'pending',
    }).select().single();

    print('Rental created successfully: $rental');
    return rental;
  }

  /// Force cleanup using direct SQL (bypasses RLS)
  Future<void> forceCleanupRentedProducts() async {
    try {
      print('Starting FORCE cleanup of rented products...');
      
      // Use RPC function to bypass RLS
      final result = await client.rpc('cleanup_rented_products');
      print('Force cleanup result: $result');
      
    } catch (e) {
      print('Error in force cleanup: $e');
      
      // Fallback: Manual cleanup with detailed logging
      try {
        final rentedProducts = await client
            .from('products')
            .select('id, name, is_rented, renter_id')
            .eq('is_rented', true);
        
        print('Found ${rentedProducts.length} rented products');
        
        for (final product in rentedProducts) {
          print('Product: ${product['name']}, is_rented: ${product['is_rented']}, renter_id: ${product['renter_id']}');
          
          // Check for any active rentals
          final rentals = await client
              .from('rentals')
              .select('id, status, payment_status')
              .eq('product_id', product['id'])
              .inFilter('status', ['active', 'pending_confirmation'])
              .isFilter('returned_at', null);
          
          print('Found ${rentals.length} rentals for this product');
          
          bool hasValidRental = false;
          for (final rental in rentals) {
            print('Rental ${rental['id']}: status=${rental['status']}, payment_status=${rental['payment_status']}');
            
            if (rental['status'] == 'active') {
              hasValidRental = true;
              break;
            }
            
            if (rental['payment_status'] == 'submitted' || 
                rental['payment_status'] == 'paid' || 
                rental['payment_status'] == 'completed') {
              hasValidRental = true;
              break;
            }
          }
          
          if (!hasValidRental) {
            print('No valid rentals found, marking product as available');
            await client
                .from('products')
                .update({
                  'is_rented': false,
                  'renter_id': null,
                  'rented_at': null,
                })
                .eq('id', product['id']);
            
            // Delete pending rentals - try multiple approaches
            try {
              // First try: Delete by specific criteria
              await client
                  .from('rentals')
                  .delete()
                  .eq('product_id', product['id'])
                  .eq('status', 'pending_confirmation')
                  .eq('payment_status', 'pending');
              print('Successfully deleted pending rentals');
            } catch (deleteError) {
              print('First delete attempt failed: $deleteError');
              
              // Second try: Delete all pending rentals for this product
              try {
                await client
                    .from('rentals')
                    .delete()
                    .eq('product_id', product['id'])
                    .eq('status', 'pending_confirmation');
                print('Successfully deleted all pending rentals for product');
              } catch (secondDeleteError) {
                print('Second delete attempt failed: $secondDeleteError');
                
                // Third try: Update status instead of delete
                try {
                  await client
                      .from('rentals')
                      .update({
                        'status': 'cancelled',
                        'payment_status': 'cancelled',
                      })
                      .eq('product_id', product['id'])
                      .eq('status', 'pending_confirmation')
                      .eq('payment_status', 'pending');
                  print('Marked pending rentals as cancelled');
                } catch (updateError) {
                  print('All cleanup attempts failed: $updateError');
                }
              }
            }
          }
        }
      } catch (fallbackError) {
        print('Fallback cleanup also failed: $fallbackError');
      }
    }
  }

  /// Clean up products that are marked as rented but have no active rentals
  Future<void> cleanupRentedProducts() async {
    try {
      print('Starting cleanup of rented products...');
      
      // Find products marked as rented
      final rentedProducts = await client
          .from('products')
          .select('id, name')
          .eq('is_rented', true);
      
      print('Found ${rentedProducts.length} products marked as rented');
      
      for (final product in rentedProducts) {
        print('Checking product: ${product['name']} (${product['id']})');
        
        // Check if there are any active rentals for this product
        final activeRentals = await client
            .from('rentals')
            .select('id, status, payment_status')
            .eq('product_id', product['id'])
            .inFilter('status', ['active'])
            .isFilter('returned_at', null);
        
        print('Active rentals for ${product['name']}: ${activeRentals.length}');
        
        // Also check for pending rentals with payments
        final pendingRentals = await client
            .from('rentals')
            .select('id, payment_status')
            .eq('product_id', product['id'])
            .eq('status', 'pending_confirmation')
            .isFilter('returned_at', null);
        
        print('Pending rentals for ${product['name']}: ${pendingRentals.length}');
        
        bool hasValidRental = false;
        
        // Check if any pending rental has payment by looking in payments table
        for (final rental in pendingRentals) {
          final paymentStatus = rental['payment_status']?.toString();
          print('Pending rental ${rental['id']} has payment_status: $paymentStatus');
          
          if (paymentStatus == 'submitted' || paymentStatus == 'paid' || paymentStatus == 'completed') {
            hasValidRental = true;
            print('Found valid rental with payment status: $paymentStatus');
            break;
          }
          
          // Also check if there's a payment record for this rental
          final payments = await client
              .from('payments')
              .select('id')
              .eq('rental_id', rental['id'])
              .limit(1);
          
          if (payments.isNotEmpty) {
            hasValidRental = true;
            print('Found payment record for rental ${rental['id']}');
            break;
          }
        }
        
        // If no active rentals AND no pending rentals with payments, mark product as available
        if (activeRentals.isEmpty && !hasValidRental) {
          print('Cleaning up product ${product['name']} - no valid rentals found');
          
          try {
            await client
                .from('products')
                .update({
                  'is_rented': false,
                  'renter_id': null,
                  'rented_at': null,
                })
                .eq('id', product['id']);
            
            print('Successfully updated product ${product['id']} to available');
          } catch (updateError) {
            print('Error updating product ${product['id']}: $updateError');
          }
          
          // Delete pending rentals without payments to clean up the database
          try {
            final deleteResult = await client
                .from('rentals')
                .delete()
                .eq('product_id', product['id'])
                .eq('status', 'pending_confirmation')
                .eq('payment_status', 'pending')
                .isFilter('returned_at', null);
            
            print('Deleted pending rentals for product ${product['id']}');
          } catch (deleteError) {
            print('Error deleting rentals for product ${product['id']}: $deleteError');
          }
        } else {
          print('Product ${product['name']} has valid rentals, keeping as rented');
        }
      }
      
      print('Cleanup completed');
    } catch (e) {
      print('Error cleaning up rented products: $e');
    }
  }

  Future<void> confirmRental({
    required String rentalId,
    required bool isConfirmed,
  }) async {
    await client
        .from('rentals')
        .update({
          'status': isConfirmed ? 'active' : 'cancelled',
          'confirmed_at': isConfirmed ? DateTime.now().toIso8601String() : null,
        })
        .eq('id', rentalId);
  }

  Future<void> updateRentalDays({
    required String rentalId,
    required int rentalDays,
    required double pricePerDay,
  }) async {
    final expectedReturnDate = DateTime.now().add(Duration(days: rentalDays));
    final rentalAmount = rentalDays * pricePerDay;

    await client.from('rentals').update({
      'rental_days': rentalDays,
      'expected_return_date': expectedReturnDate.toIso8601String(),
      'amount_due': rentalAmount,
      'status': 'awaiting_payment',
    }).eq('id', rentalId);
  }

  /// Update rental with days (for daily rentals)
  Future<void> updateRentalHours({
    required String rentalId,
    required int rentalHours, // rentalDays stored in rental_days field
    required double pricePerHour, // pricePerDay
  }) async {
    final rentalAmount = rentalHours * pricePerHour; // rentalDays * pricePerDay

    await client.from('rentals').update({
      // Do NOT set expected_return_date here; start time only after owner approval
      // Avoid writing to non-existent columns
      'amount_due': rentalAmount,
    }).eq('id', rentalId);
  }

  double calculateRentalAmount({
    required double pricePerDay,
    required int rentalDays,
  }) =>
      pricePerDay * rentalDays;

  double calculatePenalty({
    required double pricePerDay,
    required int lateDays,
    double penaltyRate = 1.5,
  }) =>
      pricePerDay * lateDays * penaltyRate;

  /// Mark rental as paid, includes penalty if any
  Future<void> markRentalAsPaid({
    required String rentalId,
    required double amountPaid,
    bool isPenalty = false,
  }) async {
    final status = isPenalty ? 'penalty_paid' : 'completed';
    await client.from('rentals').update({
      'amount_paid': amountPaid,
      'status': status,
      'payment_date': DateTime.now().toIso8601String(),
    }).eq('id', rentalId);
  }

  /// Mark rental as returned and free the product
  Future<void> markRentalAsReturned({required String rentalId}) async {
    try {
      // Get the rental data first
      final rental = await client.from('rentals').select('product_id').eq('id', rentalId).single();
      final productId = rental['product_id'];
      
      // Free the product (this is the most important part)
      await client.from('products').update({
        'is_rented': false,
        'renter_id': null,
        'rented_at': null,
      }).eq('id', productId);
      
      // Update rental status to completed and add returned_at timestamp
      try {
        await client.from('rentals').update({
          'status': 'completed',
          'returned_at': DateTime.now().toIso8601String(),
        }).eq('id', rentalId);
        print('Rental status updated to completed for rental: $rentalId');
      } catch (statusError) {
        print('Could not update rental status to completed: $statusError');
        // Try alternative approach - just set returned_at without changing status
        await client.from('rentals').update({
          'returned_at': DateTime.now().toIso8601String(),
        }).eq('id', rentalId);
        print('Set returned_at timestamp for rental: $rentalId');
      }
      
      print('Product freed successfully for rental: $rentalId');
    } catch (e) {
      print('Error in markRentalAsReturned: $e');
      rethrow;
    }
  }

  /// Calculate penalty for overdue rental
  double calculateOverduePenalty({
    required double pricePerDay,
    required DateTime expectedReturnDate,
    double penaltyRate = 0.5, // 50% of daily rate per day
  }) {
    final now = DateTime.now();
    if (now.isBefore(expectedReturnDate)) return 0;
    
    final overdueDays = now.difference(expectedReturnDate).inDays;
    return pricePerDay * overdueDays * penaltyRate;
  }

  /// Calculate penalty for overdue rental (hourly)
  double calculateOverduePenaltyHourly({
    required double pricePerHour,
    required DateTime expectedReturnDate,
    double penaltyRate = 0.5, // 50% of hourly rate per hour
  }) {
    final now = DateTime.now();
    if (now.isBefore(expectedReturnDate)) return 0;
    
    final overdueHours = now.difference(expectedReturnDate).inHours;
    return pricePerHour * overdueHours * penaltyRate;
  }

  /// Get rental with penalty calculation
  Future<Map<String, dynamic>> getRentalWithPenalty({required String rentalId}) async {
    final rental = await client
        .from('rentals')
        .select('*, products(*)')
        .eq('id', rentalId)
        .single();

    if (rental != null) {
      final product = rental['products'];
      final pricePerDay = (product['price'] ?? 0).toDouble();
      
      double penalty = 0;
      if (rental['expected_return_date'] != null) {
        final expectedDate = DateTime.parse(rental['expected_return_date']);
        penalty = calculateOverduePenalty(
          pricePerDay: pricePerDay,
          expectedReturnDate: expectedDate,
        );
      }

      rental['calculated_penalty'] = penalty;
      rental['is_overdue'] = penalty > 0;
    }

    return rental;
  }

  /// ------------------- QR UPLOAD -------------------
  Future<String> uploadQrCode({
    required String productId,
    required File qrImage,
  }) async {
    try {
      final fileName = 'qr_${productId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = 'qr_codes/$fileName';
      final bytes = await qrImage.readAsBytes();

      print('Uploading QR code to storage: $filePath');
      await client.storage.from('products').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(cacheControl: '3600', upsert: true),
          );

      final qrUrl = client.storage.from('products').getPublicUrl(filePath);
      print('QR code uploaded successfully: $qrUrl');
      return qrUrl;
    } catch (e) {
      print('Error in uploadQrCode: $e');
      rethrow;
    }
  }

  /// ------------------- PAYMENT METHODS -------------------
  Future<void> updatePaymentMethods({
    required String productId,
    String? qrCodeUrl,
    String? upiId,
  }) async {
    final updates = <String, dynamic>{};
    
    if (qrCodeUrl != null) {
      updates['qr_code_url'] = qrCodeUrl;
    }
    
    if (upiId != null) {
      updates['upi_id'] = upiId;
    }

    if (updates.isNotEmpty) {
      await client.from('products').update(updates).eq('id', productId);
    }
  }

  /// Get payment dashboard data
  Future<Map<String, dynamic>> getPaymentDashboardData({
    required String rentalId,
  }) async {
    final rental = await client
        .from('rentals')
        .select('*, products(*, profiles(*))')
        .eq('id', rentalId)
        .single();

    return rental;
  }

  /// Create payment record
  Future<void> createPaymentRecord({
    required String rentalId,
    required String productId,
    required String renterId,
    required String ownerId,
    required double baseAmount,
    required double penaltyAmount,
    required double totalAmount,
    required String method,
  }) async {
    await client.from('payments').insert({
      'rental_id': rentalId,
      'payer_id': renterId, // Renter pays
      'payee_id': ownerId, // Owner receives
      'amount': totalAmount, // Store total amount
      'method': method,
      'status': 'completed',
      'paid_at': DateTime.now().toIso8601String(),
    });
  }

  /// Update payment status
  Future<void> updatePaymentStatus({
    required String rentalId,
    required String status,
    String? transactionId,
    String? paymentScreenshot,
    String? notes,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (transactionId != null) {
      updates['transaction_id'] = transactionId;
    }

    if (paymentScreenshot != null) {
      updates['payment_screenshot'] = paymentScreenshot;
    }

    if (notes != null) {
      updates['notes'] = notes;
    }

    if (status == 'completed') {
      updates['paid_at'] = DateTime.now().toIso8601String();
    }

    await client.from('rentals').update(updates).eq('id', rentalId);
  }
}



