import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class TagFolderRulesPage extends StatefulWidget {
  const TagFolderRulesPage({super.key});

  @override
  State<TagFolderRulesPage> createState() => _TagFolderRulesPageState();
}

class _TagFolderRulesPageState extends State<TagFolderRulesPage> {
  void _editRule({TagFolderRule? existing, int? index}) {
    final settings = context.read<Settings>();
    final folderController = TextEditingController(text: existing?.folder ?? '');
    final tagsController =
        TextEditingController(text: existing?.tags.join(', ') ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add Folder Rule' : 'Edit Folder Rule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: folderController,
              decoration: const InputDecoration(
                labelText: 'Folder Name',
                hintText: 'e.g. furry, female, male',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(
                labelText: 'Matching Tags (comma separated)',
                hintText: 'e.g. furry, anthro',
                helperText:
                    'Tags written together in one entry must all match, '
                    'e.g. "rating:safe female". When several rules match, '
                    'the one asking for the most tags wins.',
                helperMaxLines: 4,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final folder = folderController.text.trim();
              final tags = tagsController.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();

              if (folder.isEmpty || tags.isEmpty) return;

              final currentRules = List<TagFolderRule>.from(settings.tagFolderRules);
              final newRule = TagFolderRule(tags: tags, folder: folder);

              if (index != null && index >= 0 && index < currentRules.length) {
                currentRules[index] = newRule;
              } else {
                currentRules.add(newRule);
              }

              settings.tagFolderRules = currentRules;
              Navigator.of(context).pop();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _deleteRule(int index) {
    final settings = context.read<Settings>();
    final currentRules = List<TagFolderRule>.from(settings.tagFolderRules);
    if (index >= 0 && index < currentRules.length) {
      currentRules.removeAt(index);
      settings.tagFolderRules = currentRules;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();

    return Scaffold(
      appBar: DefaultAppBar(
        title: const Text('Download Folder Rules'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') {
                settings.tagFolderRules = TagFolderRule.defaultRules;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset to Defaults'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editRule(),
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder<String>(
        valueListenable: settings.tagFolderRulesRaw,
        builder: (context, _, __) {
          final rules = settings.tagFolderRules;
          if (rules.isEmpty) {
            return const Center(
              child: Text(
                'No rules defined yet.\nDownloads will be saved directly into the main app folder.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return ListTile(
                leading: const Icon(Icons.folder_special),
                title: Text(
                  rule.folder,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Tags: ${rule.tags.join(', ')}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editRule(existing: rule, index: index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () => _deleteRule(index),
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
}
