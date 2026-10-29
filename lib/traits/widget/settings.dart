import 'package:e1547/app/app.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/material.dart';

class DenyListPage extends StatelessWidget {
  const DenyListPage({super.key});

  Future<void> _showCopyFromAccountDialog(
    BuildContext context,
    Client client,
    Traits traits,
  ) async {
    final identityClient = context.read<IdentityClient>();
    final allIdentities = await identityClient.all().stream.first;
    final otherIdentities =
        allIdentities.where((id) => id.id != client.identity.id).toList();

    if (otherIdentities.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other accounts found to copy from.')),
      );
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Copy blacklist from...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherIdentities.length,
            itemBuilder: (context, index) {
              final id = otherIdentities[index];
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(id.usernameOrAnon),
                subtitle: Text(id.host),
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  final storage = context.read<AppStorage>();
                  final source =
                      await TraitsRepository(storage.sqlite).getOrNull(id.id);
                  if (source != null && source.denylist.isNotEmpty) {
                    final List<String> merged = <String>{
                      ...traits.denylist,
                      ...source.denylist,
                    }.toList();
                    await client.accounts.push(
                      traits: traits.copyWith(denylist: merged),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied ${source.denylist.length} tags from ${id.usernameOrAnon}!',
                          ),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Selected account has an empty blacklist.',
                          ),
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildEditTextField(
      BuildContext context, {
      required String title,
      required SubmitString submit,
      String? value,
    }) => Material(
      child: ControlledTextWrapper(
        textController: TextEditingController(text: value),
        submit: submit,
        builder: (context, controller, submit) => TagInput(
          controller: controller,
          decoration: const InputDecoration(suffix: PromptTextFieldSuffix()),
          textInputAction: TextInputAction.done,
          direction: VerticalDirection.up,
          labelText: title,
          submit: submit,
          readOnly: PromptActions.of(context).isLoading,
        ),
      ),
    );

    return PromptActions(
      child: LimitedWidthLayout(
        child: Consumer<Client>(
          builder: (context, client, child) => ValueListenableBuilder(
            valueListenable: client.traits,
            builder: (context, traits, child) {
              List<String> denylist = traits.denylist.toList();
              return AdaptiveScaffold(
                appBar: DefaultAppBar(
                  title: const Text('Blacklist'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy blacklist from another account',
                      onPressed: () =>
                          _showCopyFromAccountDialog(context, client, traits),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const DenyListEditor(),
                        ),
                      ),
                    ),
                  ],
                ),
                floatingActionButton: PromptFab(
                  builder: (context) => buildEditTextField(
                    context,
                    title: 'Add tag',
                    submit: (value) async {
                      value = value.trim();
                      if (value.isEmpty) return;
                      try {
                        await client.accounts.push(
                          traits: traits.copyWith(
                            denylist: denylist..add(value),
                          ),
                        );
                      } on ClientException {
                        throw const ActionControllerException(
                          message: 'Failed to update blacklist!',
                        );
                      }
                    },
                  ),
                  icon: const Icon(Icons.add),
                ),
                body: PullToRefresh(
                  onRefresh: () async {
                    await client.accounts.pull();
                  },
                  child: denylist.isEmpty
                      ? const Center(
                          child: IconMessage(
                            icon: Icon(Icons.check),
                            title: Text('Your blacklist is empty'),
                          ),
                        )
                      : ListView.builder(
                          primary: true,
                          padding: defaultActionListPadding.add(
                            LimitedWidthLayout.of(context).padding,
                          ),
                          itemCount: denylist.length,
                          itemBuilder: (context, index) => DenylistTile(
                            tag: denylist[index],
                            onEdit: () {
                              String tag = denylist[index];
                              PromptActions.of(context).show(
                                context,
                                buildEditTextField(
                                  context,
                                  value: tag,
                                  title: 'Edit tag',
                                  submit: (value) async {
                                    value = value.trim();
                                    try {
                                      if (value.isEmpty) {
                                        await client.accounts.push(
                                          traits: traits.copyWith(
                                            denylist: List.of(denylist)
                                              ..remove(tag),
                                          ),
                                        );
                                      } else {
                                        await client.accounts.push(
                                          traits: traits.copyWith(
                                            denylist: List.of(denylist)
                                              ..[denylist.indexOf(tag)] = value,
                                          ),
                                        );
                                      }
                                    } on ClientException {
                                      throw const ActionControllerException(
                                        message: 'Failed to update blacklist!',
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                            onDelete: () => client.accounts.push(
                              traits: traits.copyWith(
                                denylist: denylist..remove(denylist[index]),
                              ),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
