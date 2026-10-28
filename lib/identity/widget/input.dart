import 'package:e1547/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HostFormField extends StatefulWidget {
  const HostFormField({
    super.key,
    required this.controller,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final bool readOnly;

  @override
  State<HostFormField> createState() => _HostFormFieldState();
}

class _HostFormFieldState extends State<HostFormField> {
  late final TextEditingController controller = TextEditingController(
    text: widget.controller.text,
  );
  final FocusNode focusNode = FocusNode();
  final GlobalKey<TooltipState> tooltipKey = GlobalKey<TooltipState>();
  bool isHttps = true;

  final String http = 'http://';
  final String https = 'https://';

  @override
  void initState() {
    super.initState();
    controller.addListener(_updateController);
    widget.controller.addListener(_syncFromParent);
    focusNode.addListener(_showReadOnlyHint);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateController();
    });
  }

  void _syncFromParent() {
    final parent = widget.controller.text;
    String stripped = parent;
    if (stripped.startsWith(https)) {
      if (!isHttps) setState(() => isHttps = true);
      stripped = stripped.replaceFirst(https, '');
    } else if (stripped.startsWith(http)) {
      if (isHttps) setState(() => isHttps = false);
      stripped = stripped.replaceFirst(http, '');
    }
    if (controller.text != stripped) {
      controller.text = stripped;
    }
  }

  void _showReadOnlyHint() {
    if (!widget.readOnly) return;
    if (focusNode.hasFocus) {
      tooltipKey.currentState?.ensureTooltipVisible();
    } else {
      Tooltip.dismissAllToolTips();
    }
  }

  void _updateController() {
    if (controller.text.startsWith(http)) {
      setState(() => isHttps = false);
      controller.text = controller.text.replaceFirst(http, '');
    } else if (controller.text.startsWith(https)) {
      setState(() => isHttps = true);
      controller.text = controller.text.replaceFirst(https, '');
    }
    widget.controller.text = '${isHttps ? https : http}${controller.text}';
  }

  void _selectPreset(String url) {
    if (url.startsWith(https)) {
      setState(() => isHttps = true);
      controller.text = url.replaceFirst(https, '');
    } else if (url.startsWith(http)) {
      setState(() => isHttps = false);
      controller.text = url.replaceFirst(http, '');
    } else {
      controller.text = url;
    }
    _updateController();
  }

  @override
  void dispose() {
    controller.removeListener(_updateController);
    widget.controller.removeListener(_syncFromParent);
    focusNode.removeListener(_showReadOnlyHint);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentFull = widget.controller.text.toLowerCase();
    Widget field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: widget.readOnly,
      decoration: InputDecoration(
        labelText: 'Site',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.public),
        prefixText: isHttps ? 'https://' : 'http://',
      ),
      inputFormatters: [FilteringTextInputFormatter.deny(' ')],
      autofillHints: const [AutofillHints.url],
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value!.trim().isEmpty) {
          return 'You must provide a host URL.';
        }
        try {
          if (isHttps) {
            value = 'https://$value';
          } else {
            value = 'http://$value';
          }
          Uri.parse(value);
        } on FormatException {
          return 'Invalid host URL';
        }
        return null;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.readOnly) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _PresetChip(
                  label: 'e621',
                  selected: currentFull.contains('e621.net'),
                  onSelected: () => _selectPreset('https://e621.net'),
                ),
                _PresetChip(
                  label: 'e926',
                  selected: currentFull.contains('e926.net'),
                  onSelected: () => _selectPreset('https://e926.net'),
                ),
                _PresetChip(
                  label: 'Derpibooru',
                  selected: currentFull.contains('derpibooru.org'),
                  onSelected: () => _selectPreset('https://derpibooru.org'),
                ),
                _PresetChip(
                  label: 'Rule34.xxx',
                  selected: currentFull.contains('rule34.xxx'),
                  onSelected: () => _selectPreset('https://api.rule34.xxx'),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: widget.readOnly
              ? Tooltip(
                  key: tooltipKey,
                  triggerMode: TooltipTriggerMode.manual,
                  verticalOffset: 44,
                  message:
                      'Site can\'t be changed. '
                      'Add a new account to use a different one.',
                  child: field,
                )
              : field,
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: scheme.primaryContainer,
      visualDensity: VisualDensity.compact,
    );
  }
}

class UsernameFormField extends StatelessWidget {
  const UsernameFormField({
    super.key,
    required this.controller,
    this.labelText = 'Username',
    this.hintText,
    this.helperText,
    this.optional = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final String? helperText;
  final bool optional;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        autocorrect: false,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          helperText: helperText,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.person_outline),
        ),
        inputFormatters: [FilteringTextInputFormatter.deny(' ')],
        autofillHints: const [AutofillHints.username],
        textInputAction: TextInputAction.next,
        validator: (value) {
          if (optional) return null;
          if (value == null || value.trim().isEmpty) {
            return 'You must provide a username or user ID.';
          }
          return null;
        },
      ),
    );
  }
}

class ApikeyFormField extends StatefulWidget {
  const ApikeyFormField({
    super.key,
    required this.controller,
    this.canOmit = false,
    this.host = '',
    this.labelText = 'API key',
    this.hintText,
    this.helperText,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool canOmit;
  final String host;
  final String labelText;
  final String? hintText;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  State<ApikeyFormField> createState() => _ApikeyFormFieldState();
}

class _ApikeyFormFieldState extends State<ApikeyFormField> {
  final String apiKeyExample = '1ca1d165e973d7f8d35b7deb7a2ae54c';
  bool obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final engine = BooruEngine.fromHost(widget.host);
    final allowSpaces = engine == BooruEngine.rule34;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        autocorrect: false,
        controller: widget.controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.key),
          suffixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: obscurePassword ? 'Show' : 'Hide',
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                ),
              ],
            ),
          ),
        ),
        obscureText: obscurePassword,
        inputFormatters: [
          if (!allowSpaces) FilteringTextInputFormatter.deny(' '),
          if (widget.canOmit) OmittedPasswordTextInputFormatter(),
        ],
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'You must provide credentials or an API key.';
          }

          if (widget.canOmit &&
              value == OmittedPasswordTextInputFormatter.passwordOmitted) {
            return null;
          }

          if (engine == BooruEngine.rule34) {
            if (Rule34Credentials.parse(value) != null) return null;
            if (value.trim().length >= 8) return null;
            return 'Provide your API key or paste the API Access Credentials.';
          }

          if (engine == BooruEngine.derpibooru) {
            if (value.trim().length >= 8) return null;
            return 'Derpibooru API key is at least 8 characters.';
          }

          if (!RegExp(r'^[A-Za-z\d]{16,32}$').hasMatch(value)) {
            return 'API key is a sequence of letters and digits\n'
                'e.g. $apiKeyExample';
          }

          return null;
        },
      ),
    );
  }
}

class OmittedPasswordTextInputFormatter extends TextInputFormatter {
  static final String passwordOmitted = '-' * 24;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == passwordOmitted) {
      if (newValue.text.contains(passwordOmitted)) {
        newValue = newValue.copyWith(
          text: newValue.text.replaceAll(passwordOmitted, ''),
        );
      } else {
        newValue = newValue.copyWith(text: '');
      }
      newValue = newValue.copyWith(
        selection: TextSelection.collapsed(offset: newValue.text.length),
      );
    }
    return newValue;
  }
}
