import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'dart:io';

class ListProductPage extends StatefulWidget {
  const ListProductPage({super.key});

  @override
  State<ListProductPage> createState() => _ListProductPageState();
}

class _ListProductPageState extends State<ListProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _supabase = SupabaseService();
  final List<File> _images = [];
  bool _isLoading = false;
  String? selectedCategory;
  String? selectedSubcategory;

  // Add categories data structure
  final Map<String, List<String>> categories = {
    'Tools & Equipment': [
      'Plumbing Tools',
      'Electrical Tools',
      'Harvesting Tools',
      'Power Tools',
      'Garden Tools',
      'Measuring Tools',
      'Painting Tools',
    ],
    'Kitchen & Cooking': [
      'Cooking Items',
      'Baking Equipment',
      'Food Processors',
      'Serving Dishes',
      'Party Equipment',
      'Special Occasion Items',
    ],
    'Vehicles': [
      'Bike',
      'Car',
      'Scooter',
      'Moving Trucks',
      'Commercial Vehicles',
      'Agricultural Vehicles',
    ],
    'Manpower Services': [
      'Labour',
      'Skilled Workers',
      'Professional Services',
      'Domestic Help',
      'Event Staff',
      'Cleaning Services',
    ],
    'Construction & Building Materials': [
      'Construction Materials',
      'Scaffolding',
      'Heavy Equipment',
      'Safety Equipment',
      'Concrete Tools',
      'Building Supplies',
    ],
    'Electronics': [
      'Cameras',
      'Audio Equipment',
      'Projectors',
      'Gaming Consoles',
      'Drones',
      'Event Equipment',
    ],
    'Sports & Fitness': [
      'Exercise Equipment',
      'Sports Gear',
      'Camping Equipment',
      'Adventure Sports',
      'Recreational Items',
    ],
    'Event & Party': [
      'Decorations',
      'Furniture',
      'Sound Systems',
      'Lighting Equipment',
      'Tents & Marquees',
    ],
  };

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && _images.length < 2) {
      setState(() {
        _images.add(File(pickedFile.path));
      });
    } else if (_images.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 2 images allowed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('List a Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Text(
                  'Tip: Clear photos and a short, precise description help renters decide faster.',
                  style: TextStyle(color: Color(0xFF1E3A8A)),
                ),
              ),
              const SizedBox(height: 12),
              // Image selection boxes
              SizedBox(
                height: 120,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildImageBox(0),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildImageBox(1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Category Dropdown
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Select Category',
                  border: OutlineInputBorder(),
                ),
                items: categories.keys.map((String category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedCategory = newValue;
                    selectedSubcategory = null; // Reset subcategory when category changes
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a category';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Subcategory Dropdown
              if (selectedCategory != null)
                DropdownButtonFormField<String>(
                  value: selectedSubcategory,
                  decoration: const InputDecoration(
                    labelText: 'Select Subcategory',
                    border: OutlineInputBorder(),
                  ),
                  items: categories[selectedCategory]?.map((String subcategory) {
                    return DropdownMenuItem(
                      value: subcategory,
                      child: Text(subcategory),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedSubcategory = newValue;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a subcategory';
                    }
                    return null;
                  },
                ),

              const SizedBox(height: 16),
              // Existing form fields...
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Please enter product name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  helperText: 'Mention condition and what’s included (e.g., charger, bits).',
                ),
                maxLines: 3,
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Please enter description';
                  }
                  if (value!.length < 10) {
                    return 'Add a bit more detail (min 10 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price per Hour',
                  border: OutlineInputBorder(),
                  prefixText: '₹',
                  suffixText: '/hr',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Please enter price';
                  }
                  if (double.tryParse(value!) == null) {
                    return 'Please enter a valid price';
                  }
                  if (double.tryParse(value)! <= 0) {
                    return 'Price must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton(
                      onPressed: _handleSubmit,
                      child: const Text('List Product'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageBox(int index) {
    final hasImage = index < _images.length;
    
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(12),
        ),
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _images[index],
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _images.removeAt(index);
                        });
                      },
                    ),
                  ),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 32, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'Add Image',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState?.validate() ?? false) {
      if (_images.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one image')),
        );
        return;
      }

      setState(() => _isLoading = true);

      final userId = context.read<AuthProvider>().user?.id;
      if (userId == null) return;

      try {
        // Update your addProduct method to handle multiple images and categories
        await _supabase.addProduct(
          userId: userId,
          name: _nameController.text,
          description: _descriptionController.text,
          price: double.parse(_priceController.text),
          category: selectedCategory!,
          subcategory: selectedSubcategory!,
          images: _images,  // Update your service to handle multiple images
        );

        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }

      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}
