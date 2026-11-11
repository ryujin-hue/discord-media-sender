import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/security.dart';
import '../../core/validators.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/distribution_service.dart';
import '../../services/discord_api.dart';
import '../../widgets/common.dart';

/// The credential manager.
///
/// Holds the bot and webhook credential profiles of the app. The secrets
/// themselves never appear here: they live in the Android Keystore backed
/// secure storage and only their masked status is rendered.
class CredentialsScreen extends ConsumerWidget {
  const CredentialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CredentialProfile> profiles =
        ref.watch(credentialProfilesProvider).value ??
        const <CredentialProfile>[];
    final List<CredentialProfile> bots = profiles
        .where((CredentialProfile profile) => profile.type == 'bot')
        .toList();
    final List<CredentialProfile> webhooks = profiles
        .where((CredentialProfile profile) => profile.type != 'bot')
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Credential manager'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Bot profiles'),
              Tab(text: 'Webhook profiles'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _SecurityNote(),
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _BotProfilesTab(profiles: bots),
                    _WebhookProfilesTab(profiles: webhooks),
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

// -----------------------------------------------------------------------------
// Security note
// -----------------------------------------------------------------------------

/// The short explanation of how credentials are protected.
class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.colorSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.colorSuccess.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.shield_rounded,
            size: 18,
            color: AppConstants.colorSuccess,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tokens and webhook URLs are stored in the Android Keystore. They '
              'are never written to the database, the logs or an export.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Bot profiles
// -----------------------------------------------------------------------------

/// The tab that lists the bot credential profiles.
class _BotProfilesTab extends ConsumerWidget {
  const _BotProfilesTab({required this.profiles});

  final List<CredentialProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    _openAddProfileDialog(context, ref, isBot: true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add profile'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: profiles.isEmpty
                    ? null
                    : () => _openCreateWebhookDialog(context, ref),
                icon: const Icon(Icons.add_link_rounded, size: 18),
                label: const Text('Create webhook'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (profiles.isEmpty)
          const SizedBox(
            height: 280,
            child: EmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'No bot profile',
              message:
                  'Add a profile with its token to enable bot uploads and to '
                  'create webhooks from Discord.',
            ),
          )
        else
          for (final CredentialProfile profile in profiles) ...<Widget>[
            _ProfileCard(
              profile: profile,
              onValidate: () =>
                  _validateProfile(context, ref, profile, isBot: true),
              onReplace: () =>
                  _openReplaceSecretDialog(context, ref, profile, isBot: true),
              onDelete: () => _deleteProfile(context, ref, profile),
              onTest: () => _openTestConnectionDialog(context, ref, profile),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Webhook profiles
// -----------------------------------------------------------------------------

/// The tab that lists the webhook credential profiles.
class _WebhookProfilesTab extends ConsumerWidget {
  const _WebhookProfilesTab({required this.profiles});

  final List<CredentialProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => _openAddProfileDialog(context, ref, isBot: false),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add profile'),
        ),
        const SizedBox(height: 16),
        if (profiles.isEmpty)
          const SizedBox(
            height: 280,
            child: EmptyState(
              icon: Icons.link_off_rounded,
              title: 'No webhook profile',
              message:
                  'Add a webhook profile with its URL, or create a webhook from '
                  'the bot tab.',
            ),
          )
        else
          for (final CredentialProfile profile in profiles) ...<Widget>[
            _ProfileCard(
              profile: profile,
              onValidate: () =>
                  _validateProfile(context, ref, profile, isBot: false),
              onReplace: () =>
                  _openReplaceSecretDialog(context, ref, profile, isBot: false),
              onDelete: () => _deleteProfile(context, ref, profile),
              onTest: () => _testWebhook(context, ref, profile),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Profile card
// -----------------------------------------------------------------------------

/// A single credential profile with its masked secret and its actions.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onValidate,
    required this.onReplace,
    required this.onDelete,
    this.onTest,
  });

  final CredentialProfile profile;
  final VoidCallback onValidate;
  final VoidCallback onReplace;
  final VoidCallback onDelete;
  final VoidCallback? onTest;

  /// The mask that replaces a stored secret.
  ///
  /// The real value is never read back from the secure store, so the mask has
  /// a fixed length and never hints at the length of the secret.
  static const String _mask = '••••••••••••';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isBot = profile.type == 'bot';
    final bool hasSecret = isBot ? profile.hasBotToken : profile.hasWebhook;
    final Color statusColor = profile.isValid == null
        ? AppConstants.colorTextSecondary
        : (profile.isValid!
              ? AppConstants.colorSuccess
              : AppConstants.colorError);
    final String statusLabel = profile.isValid == null
        ? 'Unknown'
        : (profile.isValid! ? 'Valid' : 'Invalid');

    return SectionCard(
      title: profile.name,
      subtitle: isBot ? 'Bot profile' : 'Webhook profile',
      icon: isBot ? Icons.smart_toy_rounded : Icons.link_rounded,
      trailing: StatusPill(label: statusLabel, color: statusColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MetricRow(
            label: isBot ? 'Bot token' : 'Webhook URL',
            value: hasSecret ? _mask : 'Not set',
          ),
          if (profile.botUserName != null && profile.botUserName!.isNotEmpty)
            MetricRow(label: 'Bot user', value: profile.botUserName!),
          MetricRow(
            label: 'Checked',
            value: _formatRelative(profile.lastValidatedAt),
          ),
          if (profile.statusMessage != null &&
              profile.statusMessage!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(profile.statusMessage!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: onValidate,
                child: const Text('Validate'),
              ),
              if (onTest != null)
                OutlinedButton(onPressed: onTest, child: const Text('Test')),
              OutlinedButton(
                onPressed: onReplace,
                child: Text(isBot ? 'Replace token' : 'Replace URL'),
              ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.colorError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Actions
// -----------------------------------------------------------------------------

/// Validates a profile against Discord and refreshes the list.
Future<void> _validateProfile(
  BuildContext context,
  WidgetRef ref,
  CredentialProfile profile, {
  required bool isBot,
}) async {
  final CredentialValidation result = isBot
      ? await DistributionService.instance.validateBotProfile(profile.id)
      : await DistributionService.instance.validateWebhookProfile(profile.id);
  ref.invalidate(credentialProfilesProvider);
  if (!context.mounted) return;
  showAppSnack(
    context,
    result.message ??
        (result.isValid ? 'The credential is valid' : 'The validation failed'),
    isSuccess: result.isValid,
    isError: !result.isValid,
  );
}

/// Deletes a profile and its stored secret after a confirmation.
Future<void> _deleteProfile(
  BuildContext context,
  WidgetRef ref,
  CredentialProfile profile,
) async {
  final bool confirmed = await showConfirmDialog(
    context,
    title: 'Delete profile',
    message:
        'Delete "${profile.name}" and its stored secret? The profile cannot '
        'be recovered afterwards.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed) return;
  await DistributionService.instance.removeProfile(profile.id);
  ref.invalidate(credentialProfilesProvider);
  if (!context.mounted) return;
  showAppSnack(context, 'Profile "${profile.name}" deleted', isSuccess: true);
}

/// Opens the dialog that adds a new credential profile.
Future<void> _openAddProfileDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool isBot,
}) async {
  final bool? added = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _AddProfileDialog(isBot: isBot),
  );
  if (added != true) return;
  ref.invalidate(credentialProfilesProvider);
  if (!context.mounted) return;
  showAppSnack(
    context,
    isBot ? 'Bot profile added' : 'Webhook profile added',
    isSuccess: true,
  );
}

/// Opens the dialog that replaces the secret of an existing profile.
Future<void> _openReplaceSecretDialog(
  BuildContext context,
  WidgetRef ref,
  CredentialProfile profile, {
  required bool isBot,
}) async {
  final bool? replaced = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) =>
        _ReplaceSecretDialog(profile: profile, isBot: isBot),
  );
  if (replaced != true) return;
  ref.invalidate(credentialProfilesProvider);
  if (!context.mounted) return;
  showAppSnack(context, 'The secret was replaced', isSuccess: true);
}

/// Opens the dialog that sends a test message through a bot profile.
Future<void> _openTestConnectionDialog(
  BuildContext context,
  WidgetRef ref,
  CredentialProfile profile,
) async {
  final String? channelId = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _TestConnectionDialog(),
  );
  if (channelId == null || channelId.isEmpty) return;
  final bool success = await DistributionService.instance.testProfile(
    profile.id,
    channelId: channelId,
  );
  if (!context.mounted) return;
  showAppSnack(
    context,
    success
        ? 'Test message sent to $channelId'
        : 'The test message could not be sent. Check the channel id and the '
              'permissions of the bot.',
    isSuccess: success,
    isError: !success,
  );
}

/// Sends a test message through a webhook profile.
///
/// A webhook carries its own channel, so no channel id is needed.
Future<void> _testWebhook(
  BuildContext context,
  WidgetRef ref,
  CredentialProfile profile,
) async {
  final bool success = await DistributionService.instance.testProfile(
    profile.id,
  );
  if (!context.mounted) return;
  showAppSnack(
    context,
    success
        ? 'Test message sent'
        : 'The test message could not be sent. Check the webhook URL.',
    isSuccess: success,
    isError: !success,
  );
}

/// Opens the flow that creates a webhook with a bot profile.
Future<void> _openCreateWebhookDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final bool? created = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => const _CreateWebhookDialog(),
  );
  if (created != true) return;
  ref.invalidate(credentialProfilesProvider);
  ref.invalidate(destinationsProvider);
  if (!context.mounted) return;
  showAppSnack(context, 'Webhook destination created', isSuccess: true);
}

// -----------------------------------------------------------------------------
// Dialogs
// -----------------------------------------------------------------------------

/// The dialog that creates a new bot or webhook credential profile.
class _AddProfileDialog extends ConsumerStatefulWidget {
  const _AddProfileDialog({required this.isBot});

  final bool isBot;

  @override
  ConsumerState<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends ConsumerState<_AddProfileDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final String name = _nameController.text.trim();
    final String secret = _secretController.text.trim();
    try {
      if (widget.isBot) {
        await DistributionService.instance.addBotProfile(
          name: name,
          botToken: secret,
        );
      } else {
        await DistributionService.instance.addWebhookProfile(
          name: name,
          webhookUrl: secret,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'The profile could not be saved', isError: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isBot ? 'Add bot profile' : 'Add webhook profile'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Profile name',
                hintText: 'Media bot',
              ),
              validator: Validators.requiredName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _secretController,
              obscureText: true,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: widget.isBot ? 'Bot token' : 'Webhook URL',
                hintText: widget.isBot
                    ? 'Paste the bot token'
                    : 'https://discord.com/api/webhooks/…',
                helperText: 'The value stays masked.',
              ),
              validator: widget.isBot
                  ? Validators.botToken
                  : Validators.webhookUrl,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// The dialog that replaces the secret of an existing credential profile.
///
/// The current secret is never displayed: it cannot be read back from the
/// secure storage, so the field starts empty and waits for the new value.
class _ReplaceSecretDialog extends ConsumerStatefulWidget {
  const _ReplaceSecretDialog({required this.profile, required this.isBot});

  final CredentialProfile profile;
  final bool isBot;

  @override
  ConsumerState<_ReplaceSecretDialog> createState() =>
      _ReplaceSecretDialogState();
}

class _ReplaceSecretDialogState extends ConsumerState<_ReplaceSecretDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _secretController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final String secret = _secretController.text.trim();
    try {
      if (widget.isBot) {
        await DistributionService.instance.replaceSecret(
          widget.profile.id,
          botToken: secret,
        );
      } else {
        await DistributionService.instance.replaceSecret(
          widget.profile.id,
          webhookUrl: secret,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'The secret could not be replaced', isError: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isBot ? 'Replace bot token' : 'Replace webhook URL'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'The stored secret of "${widget.profile.name}" is never displayed. '
              'Paste the new value to replace it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _secretController,
              obscureText: true,
              maxLines: 1,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.isBot
                    ? 'Paste the new token'
                    : 'Paste the new webhook URL',
                helperText: 'The value stays masked.',
              ),
              validator: widget.isBot
                  ? Validators.botToken
                  : Validators.webhookUrl,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Replace'),
        ),
      ],
    );
  }
}

/// The dialog that asks for the channel used by the connection test.
class _TestConnectionDialog extends StatefulWidget {
  const _TestConnectionDialog();

  @override
  State<_TestConnectionDialog> createState() => _TestConnectionDialogState();
}

class _TestConnectionDialogState extends State<_TestConnectionDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _channelController = TextEditingController();

  @override
  void dispose() {
    _channelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test connection'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'A short test message is sent to the channel below. The bot needs '
              'the "Send Messages" permission in that channel.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _channelController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Channel ID',
                hintText: '17-20 digit snowflake',
              ),
              validator: Validators.channelId,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_channelController.text.trim());
          },
          child: const Text('Send test message'),
        ),
      ],
    );
  }
}

/// The steps of the "create a webhook with a bot" flow.
enum _WebhookStep { configure, token }

/// The dialog that creates a webhook in a Discord channel with a bot.
///
/// Discord only hands out the webhook token once, right after the creation,
/// and the REST client of the app does not expose it. The flow therefore asks
/// the user to paste the token so that a real webhook URL can be built
/// instead of guessing one.
class _CreateWebhookDialog extends ConsumerStatefulWidget {
  const _CreateWebhookDialog();

  @override
  ConsumerState<_CreateWebhookDialog> createState() =>
      _CreateWebhookDialogState();
}

class _CreateWebhookDialogState extends ConsumerState<_CreateWebhookDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  List<CredentialProfile> _profiles = const <CredentialProfile>[];
  CredentialProfile? _profile;
  List<DiscordGuild> _guilds = const <DiscordGuild>[];
  DiscordGuild? _guild;
  List<DiscordChannel> _channels = const <DiscordChannel>[];
  DiscordChannel? _channel;
  WebhookInfo? _created;
  _WebhookStep _step = _WebhookStep.configure;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  /// Loads the bot profiles that can create a webhook.
  Future<void> _loadProfiles() async {
    final List<CredentialProfile> profiles = await DistributionService.instance
        .listProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles
          .where((CredentialProfile profile) => profile.type == 'bot')
          .toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// Loads the servers the selected bot has joined.
  Future<void> _selectProfile(CredentialProfile? profile) async {
    setState(() {
      _profile = profile;
      _guild = null;
      _guilds = const <DiscordGuild>[];
      _channels = const <DiscordChannel>[];
      _channel = null;
      _error = null;
    });
    if (profile == null) return;
    final List<DiscordGuild> guilds = await DistributionService.instance
        .listGuilds(profile.id);
    if (!mounted) return;
    setState(() => _guilds = guilds);
  }

  /// Loads the channels of the selected server.
  Future<void> _selectGuild(DiscordGuild? guild) async {
    final CredentialProfile? profile = _profile;
    setState(() {
      _guild = guild;
      _channels = const <DiscordChannel>[];
      _channel = null;
      _error = null;
    });
    if (profile == null || guild == null) return;
    final List<DiscordChannel> channels = await DistributionService.instance
        .listChannels(profile.id, guild.id);
    if (!mounted) return;
    setState(() {
      _channels = channels
          .where((DiscordChannel channel) => channel.supportsFiles)
          .toList();
    });
  }

  /// Creates the webhook in Discord.
  Future<void> _create() async {
    final CredentialProfile? profile = _profile;
    final DiscordChannel? channel = _channel;
    final String name = _nameController.text.trim();
    if (profile == null || channel == null) {
      setState(() => _error = 'Pick a bot, a server and a channel first.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Give the webhook a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final WebhookInfo info = await DistributionService.instance.createWebhook(
        profileId: profile.id,
        channelId: channel.id,
        name: name,
      );
      if (!mounted) return;
      setState(() {
        _created = info;
        _step = _WebhookStep.token;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'The webhook could not be created: '
            '${Security.redactSecrets(error.toString())}';
      });
    }
  }

  /// Builds the webhook URL and stores it as a destination.
  Future<void> _save() async {
    final WebhookInfo? info = _created;
    final DiscordChannel? channel = _channel;
    if (info == null) return;
    final String token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste the webhook token to continue.');
      return;
    }
    final String url = _buildWebhookUrl(info.id, token);
    final String? invalid = Validators.webhookUrl(url);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DistributionService.instance.addWebhookDestination(
        name: _nameController.text.trim().isEmpty
            ? info.name
            : _nameController.text.trim(),
        webhookUrl: url,
        channelId: info.channelId ?? channel?.id,
        channelName: channel?.name,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The destination could not be created.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _step == _WebhookStep.configure
            ? 'Create a webhook with a bot'
            : 'Webhook created',
      ),
      content: SizedBox(
        width: 420,
        child: _step == _WebhookStep.configure
            ? _buildConfigureStep(theme)
            : _buildTokenStep(theme),
      ),
      actions: _step == _WebhookStep.configure
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? 'Creating…' : 'Create webhook'),
              ),
            ]
          : <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save webhook'),
              ),
            ],
    );
  }

  Widget _buildConfigureStep(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_profiles.isEmpty) {
      return Text(
        'No bot profile is available. Add one before creating a webhook.',
        style: theme.textTheme.bodySmall,
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _profile?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bot profile'),
            items: <DropdownMenuItem<String>>[
              for (final CredentialProfile profile in _profiles)
                DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(profile.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (String? value) {
              CredentialProfile? selected;
              for (final CredentialProfile profile in _profiles) {
                if (profile.id == value) {
                  selected = profile;
                  break;
                }
              }
              unawaited(_selectProfile(selected));
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_profile?.id ?? 'no-profile'),
            initialValue: _guild?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Server'),
            items: <DropdownMenuItem<String>>[
              for (final DiscordGuild guild in _guilds)
                DropdownMenuItem<String>(
                  value: guild.id,
                  child: Text(guild.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _guilds.isEmpty
                ? null
                : (String? value) {
                    DiscordGuild? selected;
                    for (final DiscordGuild guild in _guilds) {
                      if (guild.id == value) {
                        selected = guild;
                        break;
                      }
                    }
                    unawaited(_selectGuild(selected));
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_guild?.id ?? 'no-guild'),
            initialValue: _channel?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Channel'),
            items: <DropdownMenuItem<String>>[
              for (final DiscordChannel channel in _channels)
                DropdownMenuItem<String>(
                  value: channel.id,
                  child: Text(channel.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _channels.isEmpty
                ? null
                : (String? value) {
                    DiscordChannel? selected;
                    for (final DiscordChannel channel in _channels) {
                      if (channel.id == value) {
                        selected = channel;
                        break;
                      }
                    }
                    setState(() => _channel = selected);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Webhook name',
              hintText: 'Media Sender',
            ),
          ),
          if (_guilds.isNotEmpty && _profile != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'The bot needs the "Manage Webhooks" permission in the selected '
              'channel.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppConstants.colorError,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTokenStep(ThemeData theme) {
    final WebhookInfo? info = _created;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'The webhook was created${info == null ? '' : ' (id ${info.id})'}. '
            'Discord only returns the webhook token once, at creation time, so '
            'it has to be pasted manually to build the webhook URL.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Paste the webhook token',
              helperText: 'The value stays masked.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The token is shown in Discord under Server settings → '
            'Integrations → the webhook.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppConstants.colorError,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// Builds the public webhook URL of a webhook.
///
/// Webhooks are served by the public `/api/webhooks` endpoint of Discord and
/// not by the versioned REST base, so the URL is assembled from
/// [AppConstants.discordWebBase] with the webhook id and its token.
String _buildWebhookUrl(String webhookId, String token) =>
    '${AppConstants.discordWebBase}/api/webhooks/$webhookId/$token';

/// Formats a timestamp as a short relative duration.
String _formatRelative(DateTime? time) {
  if (time == null) return 'never';
  final Duration difference = DateTime.now().difference(time);
  if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
