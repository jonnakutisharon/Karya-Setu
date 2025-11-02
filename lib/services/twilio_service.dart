import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TwilioService {
  static String get accountSid => dotenv.env['TWILIO_ACCOUNT_SID'] ?? '';
  static String get authToken => dotenv.env['TWILIO_AUTH_TOKEN'] ?? '';
  static String get twilioNumber => dotenv.env['TWILIO_PHONE_NUMBER'] ?? '';  
  
  Future<String> sendOtp(String phoneNumber) async {
    try {
      // Generate a 6-digit OTP
      final otp = _generateOTP();
      print('Generated new OTP: $otp'); // Debug print
      
      // Message body
      final message = 'Your KaryaSetu verification code is: $otp';
      
      // Twilio API endpoint
      final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json'
      );
      
      // Encode credentials
      final basicAuth = 'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}';
      
      print('Sending OTP to: $phoneNumber'); // Debug print
      
      // Send SMS via Twilio
      final response = await http.post(
        url,
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'From': twilioNumber,
          'To': phoneNumber,
          'Body': message,
        },
      );
      
      print('Twilio Response Status: ${response.statusCode}'); // Debug print
      print('Twilio Response Body: ${response.body}'); // Debug print
      
      if (response.statusCode == 201) {
        print('SMS sent successfully, returning OTP: $otp'); // Debug print
        return otp;
      } else {
        throw Exception('Failed to send OTP: ${response.body}');
      }
    } catch (e) {
      print('Error in sendOtp: $e'); // Debug print
      throw Exception('Error sending OTP: $e');
    }
  }
  
  String _generateOTP() {
    // Generate a random 6-digit number
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }
} 