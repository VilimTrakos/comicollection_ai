import 'package:flutter/material.dart';

import '../../data/catalog_repository.dart';
import '../../models/catalog_issue.dart';

typedef IssueTextBuilder = String Function(CatalogIssue issue);

Future<CatalogIssue?> showCatalogIssuePicker({
  required BuildContext context,
  required Iterable<CatalogIssue> issues,
  required String labelText,
  required IssueTextBuilder searchableText,
  required IssueTextBuilder title,
  required IssueTextBuilder subtitle,
  int? limit,
}) {
  var query = '';
  final catalogue = issues.toList(growable: false);
  return showModalBottomSheet<CatalogIssue>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final normalized = CatalogRepository.normalize(query);
        Iterable<CatalogIssue> matches = catalogue.where(
          (item) =>
              normalized.isEmpty ||
              CatalogRepository.normalize(
                searchableText(item),
              ).contains(normalized),
        );
        if (limit != null) matches = matches.take(limit);
        final visible = matches.toList(growable: false);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    autofocus: true,
                    onChanged: (value) => setSheetState(() => query = value),
                    decoration: InputDecoration(
                      labelText: labelText,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return ListTile(
                        leading: item.coverAsset == null
                            ? const Icon(Icons.menu_book)
                            : Image.asset(
                                item.coverAsset!,
                                width: 38,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                        title: Text(title(item)),
                        subtitle: Text(subtitle(item)),
                        onTap: () => Navigator.pop(sheetContext, item),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
