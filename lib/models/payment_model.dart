class PaymentModel {
  final String id;
  final String rentalId;
  final String productId;
  final String renterId;
  final String ownerId;
  final double baseAmount;
  final double penaltyAmount;
  final double totalAmount;
  final PaymentStatus status;
  final PaymentMethod method;
  final String? qrCodeUrl;
  final String? upiId;
  final String? transactionId;
  final String? paymentScreenshot;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? notes;

  PaymentModel({
    required this.id,
    required this.rentalId,
    required this.productId,
    required this.renterId,
    required this.ownerId,
    required this.baseAmount,
    required this.penaltyAmount,
    required this.totalAmount,
    required this.status,
    required this.method,
    this.qrCodeUrl,
    this.upiId,
    this.transactionId,
    this.paymentScreenshot,
    required this.createdAt,
    this.paidAt,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rental_id': rentalId,
      'product_id': productId,
      'renter_id': renterId,
      'owner_id': ownerId,
      'base_amount': baseAmount,
      'penalty_amount': penaltyAmount,
      'total_amount': totalAmount,
      'status': status.name,
      'method': method.name,
      'qr_code_url': qrCodeUrl,
      'upi_id': upiId,
      'transaction_id': transactionId,
      'payment_screenshot': paymentScreenshot,
      'created_at': createdAt.toIso8601String(),
      'paid_at': paidAt?.toIso8601String(),
      'notes': notes,
    };
  }

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] ?? '',
      rentalId: json['rental_id'] ?? '',
      productId: json['product_id'] ?? '',
      renterId: json['renter_id'] ?? '',
      ownerId: json['owner_id'] ?? '',
      baseAmount: (json['base_amount'] ?? 0).toDouble(),
      penaltyAmount: (json['penalty_amount'] ?? 0).toDouble(),
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      status: PaymentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PaymentStatus.pending,
      ),
      method: PaymentMethod.values.firstWhere(
        (e) => e.name == json['method'],
        orElse: () => PaymentMethod.qr,
      ),
      qrCodeUrl: json['qr_code_url'],
      upiId: json['upi_id'],
      transactionId: json['transaction_id'],
      paymentScreenshot: json['payment_screenshot'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at']) : null,
      notes: json['notes'],
    );
  }

  PaymentModel copyWith({
    String? id,
    String? rentalId,
    String? productId,
    String? renterId,
    String? ownerId,
    double? baseAmount,
    double? penaltyAmount,
    double? totalAmount,
    PaymentStatus? status,
    PaymentMethod? method,
    String? qrCodeUrl,
    String? upiId,
    String? transactionId,
    String? paymentScreenshot,
    DateTime? createdAt,
    DateTime? paidAt,
    String? notes,
  }) {
    return PaymentModel(
      id: id ?? this.id,
      rentalId: rentalId ?? this.rentalId,
      productId: productId ?? this.productId,
      renterId: renterId ?? this.renterId,
      ownerId: ownerId ?? this.ownerId,
      baseAmount: baseAmount ?? this.baseAmount,
      penaltyAmount: penaltyAmount ?? this.penaltyAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      method: method ?? this.method,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      upiId: upiId ?? this.upiId,
      transactionId: transactionId ?? this.transactionId,
      paymentScreenshot: paymentScreenshot ?? this.paymentScreenshot,
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
    );
  }
}

enum PaymentStatus {
  pending,
  processing,
  completed,
  failed,
  refunded,
}

enum PaymentMethod {
  qr,
  upi,
  cash,
  card,
}

class PaymentBreakdown {
  final double baseRent;
  final double penalty;
  final double total;
  final int rentalDays;
  final int overdueDays;
  final double pricePerDay;

  PaymentBreakdown({
    required this.baseRent,
    required this.penalty,
    required this.total,
    required this.rentalDays,
    required this.overdueDays,
    required this.pricePerDay,
  });

  Map<String, dynamic> toJson() {
    return {
      'base_rent': baseRent,
      'penalty': penalty,
      'total': total,
      'rental_days': rentalDays,
      'overdue_days': overdueDays,
      'price_per_day': pricePerDay,
    };
  }

  factory PaymentBreakdown.fromJson(Map<String, dynamic> json) {
    return PaymentBreakdown(
      baseRent: (json['base_rent'] ?? 0).toDouble(),
      penalty: (json['penalty'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      rentalDays: json['rental_days'] ?? 0,
      overdueDays: json['overdue_days'] ?? 0,
      pricePerDay: (json['price_per_day'] ?? 0).toDouble(),
    );
  }
}

class UPIInfo {
  final String upiId;
  final String? displayName;
  final String? bankName;
  final bool isValid;

  UPIInfo({
    required this.upiId,
    this.displayName,
    this.bankName,
    required this.isValid,
  });

  static UPIInfo parseUPI(String upiString) {
    // Basic UPI validation
    final upiRegex = RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9]+$');
    final isValid = upiRegex.hasMatch(upiString);
    
    String? displayName;
    String? bankName;
    
    if (isValid) {
      final parts = upiString.split('@');
      displayName = parts[0];
      bankName = parts[1];
    }

    return UPIInfo(
      upiId: upiString,
      displayName: displayName,
      bankName: bankName,
      isValid: isValid,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'upi_id': upiId,
      'display_name': displayName,
      'bank_name': bankName,
      'is_valid': isValid,
    };
  }

  factory UPIInfo.fromJson(Map<String, dynamic> json) {
    return UPIInfo(
      upiId: json['upi_id'] ?? '',
      displayName: json['display_name'],
      bankName: json['bank_name'],
      isValid: json['is_valid'] ?? false,
    );
  }
}
