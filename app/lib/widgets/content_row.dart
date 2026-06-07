import 'package:flutter/material.dart';

import '../models/models.dart';
import 'tv_card.dart';

/// A labelled horizontal row of [TvCard]s — one browse category.
class ContentRow extends StatelessWidget {
  final String label;
  final List<SeriesResult> items;
  final void Function(SeriesResult) onSelect;
  final bool autofocusFirst;

  const ContentRow({
    super.key,
    required this.label,
    required this.items,
    required this.onSelect,
    this.autofocusFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 12),
          child: Text(label, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 280,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 48),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => TvCard(
              title: items[i].title,
              posterUrl: items[i].posterUrl,
              autofocus: autofocusFirst && i == 0,
              onActivate: () => onSelect(items[i]),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
