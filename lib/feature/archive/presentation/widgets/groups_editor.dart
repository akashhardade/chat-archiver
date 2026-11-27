import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/groups_controller.dart';

/// The list of configured groups with add / edit / remove / enable.
class GroupsEditor extends StatelessWidget {
  const GroupsEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<GroupsController>();
    return Obx(() {
      final groups = c.groups.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isEmpty)
            AppCard(
              child: Text(
                TranslatorConst.groupsEmpty.tr,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _GroupTile(group: groups[i], controller: c),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showGroupDialog(context, c),
            icon: const Icon(Icons.add),
            label: Text(TranslatorConst.groupAdd.tr),
          ),
        ],
      );
    });
  }
}

class _GroupTile extends StatelessWidget {
  final ArchivedGroup group;
  final GroupsController controller;
  const _GroupTile({required this.group, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Switch(
        value: group.enabled,
        onChanged: (v) => controller.setEnabled(group.id, v),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: TranslatorConst.edit.tr,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGroupDialog(context, controller, group: group),
          ),
          IconButton(
            tooltip: TranslatorConst.remove.tr,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmRemove(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslatorConst.groupRemoveTitle.tr),
        content: Text('"${group.name}"\n\n${TranslatorConst.groupRemoveBody.tr}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslatorConst.cancel.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslatorConst.remove.tr),
          ),
        ],
      ),
    );
    if (ok == true) await controller.remove(group.id);
  }
}

/// Add (group == null) or edit dialog with the "exact title" guidance.
Future<void> showGroupDialog(
  BuildContext context,
  GroupsController controller, {
  ArchivedGroup? group,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _GroupDialog(controller: controller, group: group),
  );
}

class _GroupDialog extends StatefulWidget {
  final GroupsController controller;
  final ArchivedGroup? group;
  const _GroupDialog({required this.controller, this.group});

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.group?.name ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final g = widget.group;
    final error = g == null
        ? await widget.controller.add(_text.text)
        : await widget.controller.rename(g.id, _text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.group;
    final hasArchive = editing != null && editing.messageCount > 0;
    return AlertDialog(
      title: Text(
        editing == null
            ? TranslatorConst.groupAddTitle.tr
            : TranslatorConst.groupEditTitle.tr,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: TranslatorConst.groupNameLabel.tr,
                hintText: TranslatorConst.groupNameHint.tr,
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _saving ? null : _submit(),
            ),
            const SizedBox(height: 12),
            Text(
              TranslatorConst.groupNameGuidance.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (hasArchive) ...[
              const SizedBox(height: 12),
              Text(
                TranslatorConst.groupRenameWarning.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(TranslatorConst.cancel.tr),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _saving ? null : _submit,
          child: Text(
            editing == null ? TranslatorConst.add.tr : TranslatorConst.save.tr,
          ),
        ),
      ],
    );
  }
}
