import 'package:flutter/material.dart';
import '../utils/language_names.dart';

class SearchableLanguageSelector extends StatefulWidget {
  final String selectedLanguage;
  final ValueChanged<String> onChanged;
  final String title;
  final bool isDark;
  final List<String>? availableLanguages;
  final String? excludedLanguage;
  final bool showSections;

  const SearchableLanguageSelector({
    super.key,
    required this.selectedLanguage,
    required this.onChanged,
    this.title = 'Select Language',
    this.isDark = false,
    this.availableLanguages,
    this.excludedLanguage,
    this.showSections = false,
  });

  @override
  State<SearchableLanguageSelector> createState() => _SearchableLanguageSelectorState();
}

class _SearchableLanguageSelectorState extends State<SearchableLanguageSelector> {
  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguagePickerSheet(
        initialLanguage: widget.selectedLanguage,
        onChanged: widget.onChanged,
        title: widget.title,
        availableLanguages: widget.availableLanguages,
        excludedLanguage: widget.excludedLanguage,
        showSections: widget.showSections,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: _showLanguagePicker,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isDark 
              ? Colors.white.withValues(alpha: 0.1) 
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark 
                ? Colors.white.withValues(alpha: 0.2) 
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.selectedLanguage,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: widget.isDark ? Colors.white : colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: widget.isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatefulWidget {
  final String initialLanguage;
  final ValueChanged<String> onChanged;
  final String title;
  final List<String>? availableLanguages;
  final String? excludedLanguage;
  final bool showSections;

  const _LanguagePickerSheet({
    required this.initialLanguage,
    required this.onChanged,
    required this.title,
    this.availableLanguages,
    this.excludedLanguage,
    this.showSections = false,
  });

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  
  late List<String> _majorLanguages;
  late List<String> _allLanguages;
  
  late List<String> _filteredMajorLanguages;
  late List<String> _filteredAllLanguages;
  late List<String> _filteredLanguages;

  @override
  void initState() {
    super.initState();
    
    // 1. Initialize Major Languages (kTargetLanguageNames)
    if (widget.showSections) {
      _majorLanguages = List.from(kTargetLanguageNames);
      _majorLanguages.sort();
      if (widget.excludedLanguage != null) {
        _majorLanguages.remove(widget.excludedLanguage);
      }
      _filteredMajorLanguages = _majorLanguages;
    } else {
      _majorLanguages = [];
      _filteredMajorLanguages = [];
    }

    // 2. Initialize All Languages
    _allLanguages = widget.availableLanguages != null 
        ? List.from(widget.availableLanguages!)
        : kLanguageCodeToName.keys.toList();
    _allLanguages.sort();
    if (widget.excludedLanguage != null) {
      _allLanguages.remove(widget.excludedLanguage);
    }
    
    if (widget.showSections) {
      _filteredAllLanguages = _allLanguages;
      _filteredLanguages = [];
    } else {
      _filteredAllLanguages = [];
      _filteredLanguages = _allLanguages;
    }
  }

  void _filterLanguages(String query) {
    setState(() {
      if (widget.showSections) {
        _filteredMajorLanguages = _majorLanguages
            .where((lang) => lang.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _filteredAllLanguages = _allLanguages
            .where((lang) => lang.toLowerCase().contains(query.toLowerCase()))
            .toList();
      } else {
        _filteredLanguages = _allLanguages
            .where((lang) => lang.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    // Build flat list of items based on configuration
    final List<_PickerItem> items = [];
    if (widget.showSections) {
      if (_filteredMajorLanguages.isNotEmpty) {
        items.add(_PickerItem.header('Major languages'));
        for (final lang in _filteredMajorLanguages) {
          items.add(_PickerItem.language(lang));
        }
      }
      if (_filteredAllLanguages.isNotEmpty) {
        items.add(_PickerItem.header('All languages'));
        for (final lang in _filteredAllLanguages) {
          items.add(_PickerItem.language(lang));
        }
      }
    } else {
      for (final lang in _filteredLanguages) {
        items.add(_PickerItem.language(lang));
      }
    }

    return Container(
      height: mediaQuery.size.height * 0.8,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: _filterLanguages,
              decoration: InputDecoration(
                hintText: '${_allLanguages.length} languages available',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                if (item.type == _PickerItemType.header) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
                    child: Text(
                      item.text,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                }

                final lang = item.text;
                final isSelected = lang == widget.initialLanguage;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () {
                      widget.onChanged(lang);
                      Navigator.pop(context);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor: isSelected 
                        ? colorScheme.primaryContainer.withValues(alpha: 0.3) 
                        : null,
                    title: Text(
                      lang,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

enum _PickerItemType { header, language }

class _PickerItem {
  final _PickerItemType type;
  final String text;

  _PickerItem.header(this.text) : type = _PickerItemType.header;
  _PickerItem.language(this.text) : type = _PickerItemType.language;
}
