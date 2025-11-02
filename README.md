# 🤝 Karya Setu - Rental Platform

<div align="center">

![Karya Setu Logo](assets/icon/icon2.png)

**Connecting owners and renters for seamless product sharing**

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Rent Anything, Anytime** 🚀

</div>

---

## 📱 About

**Karya Setu** is a comprehensive rental platform built with Flutter that enables seamless product sharing between owners and renters. Whether you need items temporarily or want to monetize unused products, Karya Setu provides an intuitive, secure, and efficient rental marketplace.

### Key Features

- 🏠 **Product Listings**: Browse and list products with detailed categories
- 💳 **Secure Payments**: QR code and UPI payment integration
- 📊 **Rental Management**: Track active, pending, and completed rentals
- ⏰ **Penalty System**: Automated late fee calculation for overdue returns
- 📸 **Image Management**: Product images with tap-to-enlarge functionality
- 🔐 **User Authentication**: Secure signup, login, and profile management
- 📱 **Responsive Design**: Beautiful, modern UI optimised for all devices

---

## 🎨 Screenshots

### Login & Authentication
- Modern login page with purple-blue theme (#746397)
- Secure authentication with email/phone number
- Password recovery functionality

### Product Management
- Browse products by categories and subcategories
- Detailed product views with image gallery
- Product listing with image uploads

### Rental System
- Active rentals tracking (Owner & Renter views)
- Payment dashboard with QR/UPI integration
- Return processing with penalty calculations
- Rental history with status tracking

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / VS Code
- Supabase account and project

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/karya-setu.git
   cd karya-setu
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Supabase**
   - Create a `.env` file or update `lib/services/supabase_service.dart` with your Supabase credentials:
     ```dart
     SUPABASE_URL = 'your-supabase-url'
     SUPABASE_ANON_KEY = 'your-supabase-anon-key'
     ```

4. **Generate launcher icons**
   ```bash
   flutter pub run flutter_launcher_icons
   ```

5. **Run the app**
   ```bash
   flutter run
   ```

---

## 📁 Project Structure

```
lib/
├── models/              # Data models and enums
│   └── payment_model.dart
├── providers/           # State management
│   └── auth_provider.dart
├── screens/             # UI screens
│   ├── home_page.dart
│   ├── login_page.dart
│   ├── signup_page.dart
│   ├── browse_products_page.dart
│   ├── categories_page.dart
│   ├── rental_management_page.dart
│   ├── rental_history_page.dart
│   ├── payment_dashboard.dart
│   └── ...
├── services/            # Business logic and API
│   └── supabase_service.dart
└── main.dart           # App entry point
```

---

## 🏗️ Architecture

### Technology Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Storage, Auth)
- **State Management**: Provider
- **Image Handling**: CachedNetworkImage
- **Payment Integration**: QR Code & UPI

### Key Components

#### 1. Authentication System
- Email/Phone authentication via Supabase
- Secure password management
- Session persistence

#### 2. Product Management
- Category-based browsing
- Product listing with images
- Availability tracking

#### 3. Rental System
- Rental creation and tracking
- Payment processing
- Return management with penalties

#### 4. Payment Integration
- QR code scanning and display
- UPI payment integration
- Payment status tracking

---

## 💳 Payment System

### Owner Features
- Upload QR code images (PNG/JPG)
- Add UPI ID for direct payments
- Manage payment methods in profile

### Renter Features
- Scan QR codes for payment
- Launch UPI apps with a pre-filled amount
- Upload payment screenshots as proof
- Real-time payment status updates

### Payment Flow
1. Owner sets up QR/UPI in product profile
2. Renter selects rental duration
3. The payment dashboard shows available methods
4. Renter completes payment
5. Owner receives payment confirmation

---

## 📋 Rental Management

### Owner View
- **Active Rentals**: Track products currently rented
- **Pending Returns**: Rentals awaiting return
- **Completed Rentals**: Historical rental data
- **Penalty Calculation**: Automatic late fee computation

### Renter View
- **Active Rentals**: Currently rented items
- **Payment Status**: Track payment completion
- **Return Requests**: Submit return requests
- **Penalty Payments**: Pay late fees if applicable

### Penalty System
- Calculated as: `Daily Rate × Overdue Days × 1.0`
- Visual indicators for overdue rentals
- Automatic penalty application on late returns

---

## 🎨 Design System

### Color Palette
- **Primary**: `#746397` (Muted Purple-Blue)
- **Accent**: `#007BFF` (Blue)
- **Success**: `#10B981` (Green)
- **Error**: `#DC2626` (Red)

### Typography
- Clean, readable fonts
- Consistent text hierarchy
- Responsive font sizing

### UI Components
- Material Design 3
- Custom card components
- Animated transitions
- Image viewers with zoom

---

## 🔧 Configuration

### Android Setup
- Minimum SDK: 21 (Android 5.0+)
- Target SDK: Latest
- App name configured in `strings.xml`

### iOS Setup
- Minimum iOS version: 12.0+
- Bundle identifier configured
- App icons generated automatically

### Web Setup
- Responsive layout
- PWA support ready
- Manifest configured

---

## 📦 Building APK

### Release APK
```bash
flutter build apk --release
```

The APK will be generated at:
```
build/app/outputs/flutter-apk/app-release.apk
```

### App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

---

## 🔐 Environment Variables

Create a `.env` file or configure in your Supabase service:

```env
SUPABASE_URL=your-supabase-project-url
SUPABASE_ANON_KEY=your-supabase-anon-key
```

---

## 📝 Database Schema

### Key Tables
- `users` - User profiles and authentication
- `products` - Product listings
- `rentals` - Rental transactions
- `payments` - Payment records
- `categories` - Product categories

See `supabase_policies.sql` for detailed schema and RLS policies.

---

## 🧪 Testing

Run tests with:
```bash
flutter test
```



## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Sharon**

- GitHub: [@jonnakutisharon](https://github.com/jonnakutisharon)

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Supabase for backend infrastructure
- All contributors and users of Karya Setu

---

## 📞 Support

For support, email support@karyasetu.com or create an issue in the repository.

---

<div align="center">

**Built with ❤️ using Flutter**

⭐ Star this repo if you find it helpful!

</div>
