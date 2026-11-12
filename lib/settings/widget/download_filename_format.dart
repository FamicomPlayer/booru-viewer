import 'package:e1547/post/post.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class DownloadFileNameFormatPage extends StatefulWidget {
  const DownloadFileNameFormatPage({super.key});

  @override
  State<DownloadFileNameFormatPage> createState() =>
      _DownloadFileNameFormatPageState();
}

class _DownloadFileNameFormatPageState
    extends State<DownloadFileNameFormatPage> {
  late final TextEditingController _controller;

  static final Post _samplePost = Post(
    id: 12891961,
    file: 'https://example.com/sample.png',
    sample: 'https://example.com/sample.png',
    preview: 'https://example.com/preview.png',
    width: 1920,
    height: 1080,
    ext: 'png',
    size: 2048000,
    variants: null,
    tags: {
      'artist': ['tony_taka'],
      'character': ['agnes_tachyon_(umamusume)'],
      'copyright': ['umamusume'],
      'general': ['1girl', 'solo', 'bikini'],
      'meta': ['highres'],
    },
    uploaderId: 1,
    uploaderName: 'booru_uploader',
    createdAt: DateTime.now(),
    updatedAt: null,
    score: 42,
    vote: null,
    isDeleted: false,
    rating: Rating.s,
    favCount: 25,
    isFavorited: true,
    commentCount: 5,
    description: '',
    sources: [],
    pools: null,
    relationships: const Relationships(
      parentId: null,
      hasChildren: false,
      hasActiveChildren: null,
      children: [],
    ),
  );

  @override
  void initState() {
    super.initState();
    final settings = context.read<Settings>();
    _controller = TextEditingController(
      text: settings.downloadFileNameFormat.value,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String value) {
    context.read<Settings>().downloadFileNameFormat.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final previewName = DownloadFileNameGenerator.generate(
      _samplePost,
      format: _controller.text,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download filename format'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to default',
            onPressed: () {
              setState(() {
                _controller.text = DownloadFileNameGenerator.defaultFormat;
                _save(_controller.text);
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    previewName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Filename Pattern',
              border: OutlineInputBorder(),
              helperText: 'Tokens will be replaced with post metadata',
            ),
            onChanged: (val) {
              setState(() {});
              _save(val);
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Presets',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DownloadFileNameGenerator.presets.map((preset) {
              final isSelected = _controller.text == preset.format;
              return ChoiceChip(
                label: Text(preset.label),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _controller.text = preset.format;
                    _save(preset.format);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text(
            'Available Tokens',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DownloadFileNameGenerator.availableTokens.map((token) {
              return ActionChip(
                label: Text(token),
                onPressed: () {
                  final text = _controller.text;
                  final selection = _controller.selection;
                  final newText = (selection.isValid && selection.start >= 0)
                      ? text.replaceRange(selection.start, selection.end, token)
                      : '$text $token';
                  _controller.text = newText;
                  _save(newText);
                  setState(() {});
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
