import 'package:flutter/material.dart';

import '../models/comic.dart';
import 'app_theme.dart';

class GrungeBackground extends StatelessWidget {
  const GrungeBackground({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(-.8, -.9),
        radius: 1.2,
        colors: [Color(0x332D0B08), Colors.transparent],
      ),
    ),
  );
}

class EditionProgressRow extends StatelessWidget {
  const EditionProgressRow({
    super.key,
    required this.name,
    required this.comics,
  });

  final String name;
  final List<Comic> comics;

  @override
  Widget build(BuildContext context) {
    final owned = comics.where((comic) => comic.owned).length;
    final progress = comics.isEmpty ? 0.0 : owned / comics.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 62,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: ComicCover(
                    label: name.split(' · ').first,
                    seed: name.hashCode,
                    assetPath: comics.first.coverAsset,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$owned/${comics.length}',
                          style: const TextStyle(color: tan, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: const Color(0xFF080909),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'još ${comics.length - owned} do kompleta',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.label,
    required this.seed,
    this.assetPath = '',
  });
  final String label;
  final int seed;
  final String assetPath;
  @override
  Widget build(BuildContext context) {
    if (assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    const colors = [
      Color(0xFFB5281E),
      Color(0xFF1F5FA8),
      Color(0xFFE0C530),
      Color(0xFF1E4A42),
      Color(0xFF5A2A6E),
      Color(0xFF3A2C20),
    ];
    final color = colors[seed.abs() % colors.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: .95),
            Color.lerp(color, Colors.black, .55)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: DotPainter()),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF2D02B),
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: .16);
    for (double y = 4; y < size.height; y += 8) {
      for (double x = 4; x < size.width; x += 8) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value, label;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: tan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: tan,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Text(text, style: const TextStyle(color: tan)),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .4),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: tan)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
