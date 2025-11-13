import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rental_app/services/supabase_service.dart';
import 'package:provider/provider.dart';
import 'package:rental_app/providers/auth_provider.dart';
import 'package:rental_app/screens/login_page.dart';
import 'package:rental_app/screens/terms_and_conditions_page.dart';
import 'package:rental_app/screens/rental_flow_page.dart';
import 'package:rental_app/screens/rental_management_page.dart';

class Category {
  final String title;
  final List<String> subcategories;
  final IconData icon;

  Category({
    required this.title,
    required this.subcategories,
    required this.icon,
  });
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Category> filteredCategories = [];
  List<Map<String, dynamic>> searchedProducts = [];
  bool isSearchingProducts = false;

  final List<Category> allCategories = [
    Category(
      title: 'Tools & Equipment',
      icon: Icons.handyman,
      subcategories: [
        'Plumbing Tools',
        'Electrical Tools',
        'Harvesting Tools',
        'Power Tools',
        'Garden Tools',
        'Measuring Tools',
        'Painting Tools',
      ],
    ),
    Category(
      title: 'Kitchen & Cooking',
      icon: Icons.kitchen,
      subcategories: [
        'Cooking Items',
        'Baking Equipment',
        'Food Processors',
        'Serving Dishes',
        'Party Equipment',
        'Special Occasion Items',
      ],
    ),
    Category(
      title: 'Vehicles',
      icon: Icons.directions_car,
      subcategories: [
        'Bike',
        'Car',
        'Scooter',
        'Moving Trucks',
        'Commercial Vehicles',
        'Agricultural Vehicles',
      ],
    ),
    Category(
      title: 'Manpower Services',
      icon: Icons.engineering,
      subcategories: [
        'Labour',
        'Skilled Workers',
        'Professional Services',
        'Domestic Help',
        'Event Staff',
        'Cleaning Services',
      ],
    ),
    Category(
      title: 'Construction & Building Materials',
      icon: Icons.construction,
      subcategories: [
        'Construction Materials',
        'Scaffolding',
        'Heavy Equipment',
        'Safety Equipment',
        'Concrete Tools',
        'Building Supplies',
      ],
    ),
    Category(
      title: 'Electronics',
      icon: Icons.devices,
      subcategories: [
        'Cameras',
        'Audio Equipment',
        'Projectors',
        'Gaming Consoles',
        'Drones',
        'Event Equipment',
      ],
    ),
    Category(
      title: 'Sports & Fitness',
      icon: Icons.sports_basketball,
      subcategories: [
        'Exercise Equipment',
        'Sports Gear',
        'Camping Equipment',
        'Adventure Sports',
        'Recreational Items',
      ],
    ),
    Category(
      title: 'Event & Party',
      icon: Icons.celebration,
      subcategories: [
        'Decorations',
        'Furniture',
        'Sound Systems',
        'Lighting Equipment',
        'Tents & Marquees',
      ],
    ),
  ];

  String? searchSuggestion;

  @override
  void initState() {
    super.initState();
    filteredCategories = allCategories;
    _searchController.addListener(_filterCategories);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _calculateSimilarity(String s1, String s2) {
    // Calculate similarity based on the length of the common substring
    final length1 = s1.length;
    final length2 = s2.length;
    final commonLength = _longestCommonSubstring(s1, s2).length;

    return commonLength / length1; // Return similarity as a fraction
  }

  String _longestCommonSubstring(String s1, String s2) {
    int maxLength = 0;
    String longestSubstring = '';

    for (int i = 0; i < s1.length; i++) {
      for (int j = 0; j < s2.length; j++) {
        int length = 0;
        while (i + length < s1.length &&
            j + length < s2.length &&
            s1[i + length] == s2[j + length]) {
          length++;
        }
        if (length > maxLength) {
          maxLength = length;
          longestSubstring = s1.substring(i, i + length);
        }
      }
    }
    return longestSubstring;
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase().trim();

    // Clear previous search results
    setState(() {
      searchSuggestion = null;
      searchedProducts.clear();
      isSearchingProducts = false;

      if (query.isEmpty) {
        // Show all categories when search is empty
        filteredCategories = allCategories; // Ensure categories are shown
        return; // Exit early for empty search
      }
    });

    // Only search products if there's a query
    if (query.isNotEmpty) {
      SupabaseService.client
          .from('products')
          .stream(primaryKey: ['id']).map((data) {
        final List<Map<String, dynamic>> products =
            List<Map<String, dynamic>>.from(data);
        return products
            .where((product) =>
                (product['is_rented'] == null ||
                    product['is_rented'] == false) &&
                (product['name'].toString().toLowerCase().contains(query) ||
                    product['description']
                        .toString()
                        .toLowerCase()
                        .contains(query)))
            .toList();
      }).listen((products) {
        if (!mounted) return; // Check if widget is still mounted

        setState(() {
          if (products.isNotEmpty) {
            searchedProducts = products;
            isSearchingProducts = true;
            filteredCategories = []; // Clear categories when showing products
          } else {
            // If no products found, search in categories
            filteredCategories = allCategories.where((category) {
              final titleMatch = category.title.toLowerCase().contains(query);
              final subcategoryMatch = category.subcategories
                  .any((sub) => sub.toLowerCase().contains(query));
              return titleMatch || subcategoryMatch;
            }).toList();
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Categories'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products or categories...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          if (searchSuggestion != null && filteredCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Did you mean "$searchSuggestion"?',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _searchController.text =
                              searchSuggestion!.split(' > ').first;
                          _filterCategories();
                        },
                        child: const Text('Try this'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_searchController.text.isNotEmpty &&
              filteredCategories.isEmpty &&
              searchedProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No results found for "${_searchController.text}"',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: isSearchingProducts
                ? _buildProductsList()
                : _buildCategoriesList(),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRent(BuildContext context, Map<String, dynamic> product) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to rent products'),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      );
      return;
    }

    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TermsAndConditionsPage(
          onAccept: () => Navigator.pop(context, true),
          onDecline: () => Navigator.pop(context, false),
        ),
      );

      if (accepted != true) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RentalFlowPage(
            product: Map<String, dynamic>.from(product),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to process rental. Please try again later.\n\nError: ${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildProductsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: searchedProducts.length,
      itemBuilder: (context, index) {
        final product = searchedProducts[index];
        final images = (product['images'] as List?)?.cast<String>() ?? [];
        final isRented = product['is_rented'] == true;
        final pricePerHour = (product['price'] as num?)?.toDouble() ?? 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (images.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final imageList = (images as List?)?.cast<String>() ?? [];
                    _showFullScreenImage(context, imageList);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: images.first,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                const Center(child: CircularProgressIndicator()),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                          ),
                          // Show indicator if multiple images
                          if (images.length > 1)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${images.length} images',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product['description'] ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isRented ? const Color(0xFFDC2626) : const Color(0xFF10B981)).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isRented ? 'Unavailable' : 'Available',
                            style: TextStyle(
                              color: isRented ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₹${pricePerHour.toStringAsFixed(2)}/day',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).primaryColor,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${product['category']} > ${product['subcategory']}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isRented ? null : () => _handleRent(context, product),
                        child: Text(isRented ? 'Currently Rented' : 'Rent Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoriesList() {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filteredCategories.length,
        itemBuilder: (context, index) {
          final category = filteredCategories[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              leading: Icon(
                category.icon,
                color: Theme.of(context).primaryColor,
                size: 28,
              ),
              title: Text(
                category.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              children: category.subcategories.map((subcategory) {
                return ListTile(
                  contentPadding: const EdgeInsets.only(
                    left: 72,
                    right: 16,
                  ),
                  title: Text(subcategory),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SubcategoryItemsPage(
                          category: category.title,
                          subcategory: subcategory,
                          highlightedSubcategory: subcategory,
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full screen image viewer with PageView for multiple images
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: PageView.builder(
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return Center(
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.error, color: Colors.white, size: 48),
                    ),
                  );
                },
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  shape: const CircleBorder(),
                ),
              ),
            ),
            // Image indicator if multiple images
            if (images.length > 1)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Swipe to view all ${images.length} images',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// This is a placeholder page for showing items in a subcategory
class SubcategoryItemsPage extends StatefulWidget {
  final String category;
  final String subcategory;
  final String? highlightedSubcategory;

  const SubcategoryItemsPage({
    super.key,
    required this.category,
    required this.subcategory,
    this.highlightedSubcategory,
  });

  @override
  State<SubcategoryItemsPage> createState() => _SubcategoryItemsPageState();
}

class _SubcategoryItemsPageState extends State<SubcategoryItemsPage> {
  late final SupabaseService _supabase;

  @override
  void initState() {
    super.initState();
    _supabase = SupabaseService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subcategory),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.getProductsByCategory(
          category: widget.category,
          subcategory: widget.subcategory,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final products = snapshot.data!;

          if (products.isEmpty) {
            return const Center(
              child: Text('No products available in this category'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final images = (product['images'] as List?)?.cast<String>() ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (images.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          final imageList = (images as List?)?.cast<String>() ?? [];
                          _showFullScreenImage(context, imageList);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: images.first,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                ),
                                // Show indicator if multiple images
                                if (images.length > 1)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${images.length} images',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'] ?? '',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            product['description'] ?? '',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₹${product['price']?.toString() ?? '0'}/day',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).primaryColor,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${product['category']} > ${product['subcategory']}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.grey[600],
                                  fontWeight: widget.highlightedSubcategory ==
                                          product['subcategory']
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: product['is_rented'] == true
                                  ? null
                                  : () => _handleRent(context, product),
                              child: Text(
                                product['is_rented'] == true
                                    ? 'Currently Rented'
                                    : 'Rent Now',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleRent(
      BuildContext context, Map<String, dynamic> product) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to rent products'),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      );
      return;
    }

    try {
      // Show terms and conditions first
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TermsAndConditionsPage(
          onAccept: () => Navigator.pop(context, true),
          onDecline: () => Navigator.pop(context, false),
        ),
      );

      if (accepted != true) return;

      // Route to rental flow where renter selects hours and pays
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RentalFlowPage(
            product: Map<String, dynamic>.from(product),
          ),
        ),
      );
    } catch (e) {
      // Close loading indicator if it's showing
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        // Show error dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(
              'Failed to process rental. Please try again later.\n\nError: ${e.toString()}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showFullScreenImage(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full screen image viewer with PageView for multiple images
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: PageView.builder(
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return Center(
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.error, color: Colors.white, size: 48),
                    ),
                  );
                },
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  shape: const CircleBorder(),
                ),
              ),
            ),
            // Image indicator if multiple images
            if (images.length > 1)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Swipe to view all ${images.length} images',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
