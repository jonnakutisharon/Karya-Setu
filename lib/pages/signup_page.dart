import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _stateController = TextEditingController();
  final _districtController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _localityController = TextEditingController();
  bool _loading = false;

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Enter email';
    bool emailValid = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value);
    if (!emailValid) return 'Enter valid email';
    return null;
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final result = await authProvider.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      name: _nameController.text.trim(),
      state: _stateController.text.trim(),
      district: _districtController.text.trim(),
      pincode: _pincodeController.text.trim(),
      locality: _localityController.text.trim(),
    );

    setState(() => _loading = false);

    if (result != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Full Name'),
                validator: (v) => v!.isEmpty ? 'Enter name' : null,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                validator: validateEmail,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Enter password' : null,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _stateController,
                decoration: InputDecoration(labelText: 'State'),
                validator: (v) => v!.isEmpty ? 'Enter state' : null,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _districtController,
                decoration: InputDecoration(labelText: 'District'),
                validator: (v) => v!.isEmpty ? 'Enter district' : null,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _pincodeController,
                decoration: InputDecoration(labelText: 'Pincode'),
                validator: (v) => v!.isEmpty ? 'Enter pincode' : null,
              ),
              SizedBox(height: 10),
              TextFormField(
                controller: _localityController,
                decoration: InputDecoration(labelText: 'Locality'),
                validator: (v) => v!.isEmpty ? 'Enter locality' : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _signup,
                child: _loading
                    ? CircularProgressIndicator()
                    : Text('Sign Up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
