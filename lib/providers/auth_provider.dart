import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  User? _user;
  Map<String, dynamic>? _userProfile;

  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isAuthenticated => _user != null;

  // Sign in with email & password
  Future<void> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    _user = response.user;
    if (_user != null) {
      await getUserProfile();
      notifyListeners();
    } else {
      throw Exception('Login failed');
    }
  }

  // Sign up with email & password
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? state,
    String? district,
    String? pincode,
    String? locality,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    _user = response.user;

    if (_user != null) {
      // ✅ Update instead of insert, because trigger already created the row
      await _client.from('profiles').update({
        'name': name,
        'phone': phone,
        'state': state,
        'district': district,
        'pincode': pincode,
        'locality': locality,
      }).eq('id', _user!.id);

      await getUserProfile();
      notifyListeners();
    } else {
      throw Exception('Sign up failed');
    }
  }

  // Send OTP (stub for first project compatibility)
  Future<void> sendOtp(String phone) async {
    // Implement Supabase phone OTP if needed or just a stub
    print('Sending OTP to $phone');
  }

  // Verify OTP (stub for first project compatibility)
  Future<bool> verifyOtp(String phone, String otp) async {
    // Implement Supabase phone OTP verification if needed
    print('Verifying OTP $otp for $phone');
    return true;
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
    print('Password reset link sent to $email');
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      if (_user == null) return null;

      final data = await _client
          .from('profiles')
          .select()
          .eq('id', _user!.id)
          .single() as Map<String, dynamic>;

      _userProfile = data;
      notifyListeners();
      return _userProfile;
    } catch (e) {
      _userProfile = null;
      notifyListeners();
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
    _user = null;
    _userProfile = null;
    notifyListeners();
  }
}
