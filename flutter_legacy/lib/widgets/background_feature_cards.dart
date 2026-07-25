import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/app_config.dart';
import 'dart:math' as math;

class BackgroundFeatureCards extends StatefulWidget {
  final int cardCount;
  final double opacity;
  final double maxRotation;

  const BackgroundFeatureCards({
    super.key,
    this.cardCount = 8,
    this.opacity = 0.15,
    this.maxRotation = 20.0,
  });

  @override
  State<BackgroundFeatureCards> createState() => _BackgroundFeatureCardsState();
}

class _BackgroundFeatureCardsState extends State<BackgroundFeatureCards>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final List<Map<String, dynamic>> _cardPositions = [];

  @override
  void initState() {
    super.initState();
    _initializeCards();
  }

  void _initializeCards() {
    // Use a fixed seed for completely consistent card distribution across all screens
    final random = math.Random(42);

    _controllers = List.generate(
      widget.cardCount,
      (index) => AnimationController(
        duration: Duration(seconds: 3 + random.nextInt(4)),
        vsync: this,
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      ));
    }).toList();

    _cardPositions.clear();

    // Fixed card dimensions for collision detection (as screen ratios)
    final cardWidth = 0.12; // 12% of screen width
    final cardHeight = 0.10; // 10% of screen height
    final minDistance = math.max(cardWidth, cardHeight) *
        1.3; // Minimum distance between card centers

    // Use completely deterministic positioning for identical distribution across all screens
    // Redistributed evenly across the screen in a grid-like pattern
    final List<Map<String, double>> predefinedPositions = [
      {'left': 0.10, 'top': 0.15}, // Top-left
      {'left': 0.35, 'top': 0.12}, // Top-center-left
      {'left': 0.60, 'top': 0.18}, // Top-center-right
      {'left': 0.85, 'top': 0.14}, // Top-right
      {'left': 0.15, 'top': 0.40}, // Middle-left-top
      {'left': 0.40, 'top': 0.38}, // Middle-center-top
      {'left': 0.65, 'top': 0.42}, // Middle-center-bottom
      {'left': 0.90, 'top': 0.36}, // Middle-right-top
      {'left': 0.20, 'top': 0.65}, // Middle-left-bottom
      {'left': 0.45, 'top': 0.68}, // Middle-center-bottom
      {'left': 0.70, 'top': 0.70}, // Middle-right-bottom
      {'left': 0.95, 'top': 0.62}, // Middle-right-bottom
    ];

    for (int i = 0; i < widget.cardCount; i++) {
      final card = AppConfig.featureCards[i % AppConfig.featureCards.length];

      // Use predefined positions for exact consistency across all screens
      final position = predefinedPositions[i % predefinedPositions.length];

      _cardPositions.add({
        'card': card,
        'left': position['left']!,
        'top': position['top']!,
        'rotation': (random.nextDouble() - 0.5) * 2 * widget.maxRotation,
        'scale': 1.0, // All cards same size
        'delay': random.nextDouble() * 2.0,
      });
    }

    // Start animations with staggered delays
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(
          Duration(milliseconds: (_cardPositions[i]['delay'] * 1000).round()),
          () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  bool _hasCollision(Map<String, dynamic> newPosition,
      List<Map<String, dynamic>> existingPositions, double minDistance) {
    for (final existing in existingPositions) {
      final dx = newPosition['left'] - existing['left'];
      final dy = newPosition['top'] - existing['top'];
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance < minDistance) {
        return true; // Collision detected
      }
    }
    return false; // No collision
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _cardPositions.asMap().entries.map((entry) {
        final index = entry.key;
        final position = entry.value;
        final card = position['card'] as Map<String, dynamic>;

        return Positioned(
          left: position['left'] * MediaQuery.of(context).size.width,
          top: position['top'] * MediaQuery.of(context).size.height,
          child: AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Transform.rotate(
                angle: (position['rotation'] * math.pi / 180),
                child: Transform.scale(
                  scale: position['scale'] *
                      (0.95 + 0.05 * _animations[index].value),
                  child: Opacity(
                    opacity:
                        widget.opacity * (0.8 + 0.2 * _animations[index].value),
                    child: _buildFeatureCard(card),
                  ),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeatureCard(Map<String, dynamic> card) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            _getIcon(card['icon']),
            color: Colors.white.withOpacity(0.8),
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            card['title'],
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            card['description'],
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 9,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'gamepad':
        return FontAwesomeIcons.gamepad;
      case 'compass':
        return FontAwesomeIcons.compass;
      case 'map-pin':
        return FontAwesomeIcons.mapPin;
      case 'bolt':
        return FontAwesomeIcons.bolt;
      case 'camera':
        return FontAwesomeIcons.camera;
      case 'map':
        return FontAwesomeIcons.map;
      case 'rocket':
        return FontAwesomeIcons.rocket;
      case 'robot':
        return FontAwesomeIcons.robot;
      case 'satellite-dish':
        return FontAwesomeIcons.satelliteDish;
      default:
        return FontAwesomeIcons.circle;
    }
  }
}
