import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/chat_models.dart';
import '../../shared/models/job_model.dart';
import '../../shared/models/recording_model.dart';
import '../../shared/widgets/content_section.dart';
import '../chat/chat_controller.dart';
import '../recordings/recordings_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _newRecordingController = TextEditingController();
  final _chatInputController = TextEditingController();

  late final RecordingsController _recordingsController;
  late final ChatController _chatController;

  @override
  void initState() {
    super.initState();
    _recordingsController = RecordingsController();
    _chatController = ChatController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  @override
  void dispose() {
    _newRecordingController.dispose();
    _chatInputController.dispose();
    _recordingsController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final token = widget.authController.accessToken;
    if (token == null) {
      return;
    }

    try {
      await _recordingsController.bootstrap(accessToken: token);
      final selected = _recordingsController.selected;
      if (selected != null) {
        await _chatController.loadForRecording(
          accessToken: token,
          recordingId: selected.id,
        );
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _createRecording() async {
    final token = widget.authController.accessToken;
    final title = _newRecordingController.text.trim();
    if (token == null || title.isEmpty) {
      _showMessage('Informe um titulo para a gravacao.');
      return;
    }

    try {
      await _recordingsController.createRecording(
        accessToken: token,
        title: title,
      );
      _newRecordingController.clear();
      final selected = _recordingsController.selected;
      if (selected != null) {
        await _chatController.loadForRecording(
          accessToken: token,
          recordingId: selected.id,
        );
      } else {
        _chatController.clear();
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _selectRecording(RecordingModel recording) async {
    final token = widget.authController.accessToken;
    if (token == null) {
      return;
    }

    try {
      await _recordingsController.selectRecording(
        accessToken: token,
        recordingId: recording.id,
      );
      await _chatController.loadForRecording(
        accessToken: token,
        recordingId: recording.id,
      );
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _processRecording() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    try {
      await _recordingsController.startProcessing(
        accessToken: token,
        recordingId: selected.id,
        waitForCompletion: true,
      );
      _showMessage(
          'Processamento concluido. Transcricao, resumo e mapa mental atualizados.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _uploadAudio() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: <String>['mp3', 'wav', 'm4a', 'ogg', 'webm', 'flac'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage('Nao foi possivel ler o arquivo selecionado.');
        return;
      }

      await _recordingsController.uploadAudio(
        accessToken: token,
        recordingId: selected.id,
        fileName: file.name,
        bytes: bytes,
        processAfterUpload: true,
        waitForCompletion: true,
      );
      _showMessage('Audio enviado e processado com sucesso.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Falha ao enviar o audio.');
    }
  }

  Future<void> _refreshDetails() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    try {
      await _recordingsController.reloadDetails(
        accessToken: token,
        recordingId: selected.id,
      );
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _refreshChat() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    try {
      await _chatController.loadForRecording(
        accessToken: token,
        recordingId: selected.id,
      );
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _sendChatMessage() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    final content = _chatInputController.text.trim();
    if (token == null || selected == null || content.isEmpty) {
      return;
    }

    try {
      await _chatController.sendMessage(
        accessToken: token,
        recordingId: selected.id,
        content: content,
      );
      _chatInputController.clear();
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _logout() async {
    await widget.authController.logout();
  }

  Future<void> _editProfileName() async {
    final current = widget.authController.currentUser;
    if (current == null) {
      return;
    }

    final controller = TextEditingController(text: current.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Atualizar nome'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null) {
      return;
    }

    try {
      await widget.authController
          .updateProfileName(result.isEmpty ? null : result);
      _showMessage('Nome atualizado.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _editAiSettings() async {
    final current = widget.authController.aiSettings;
    final providerTypeNotifier = ValueNotifier<String>(
      current?.providerType ?? 'openai',
    );
    final baseUrlController = TextEditingController(
      text: current != null && !current.isOpenAi ? current.baseUrl : '',
    );
    final modelController = TextEditingController(
      text: current?.model.isNotEmpty == true ? current!.model : 'gpt-4.1-mini',
    );
    final apiKeyController = TextEditingController();

    final result = await showDialog<_AiSettingsDialogResult?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configurar IA pessoal'),
          content: SizedBox(
            width: 520,
            child: ValueListenableBuilder<String>(
              valueListenable: providerTypeNotifier,
              builder: (context, providerType, _) {
                final overrideActive = current?.isUserOverride ?? false;
                final existingKeyHint = current?.apiKeyHint;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        overrideActive
                            ? 'Override do usuario ativo.'
                            : 'Sem override salvo. O sistema usa a configuracao padrao ate voce salvar a sua.',
                      ),
                      if (existingKeyHint != null && existingKeyHint.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text('Chave salva: $existingKeyHint'),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: providerType,
                        decoration: const InputDecoration(
                          labelText: 'Provider',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'openai',
                            child: Text('OpenAI oficial'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'openai_compatible',
                            child: Text('OpenAI-compatible'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            providerTypeNotifier.value = value;
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      if (providerType == 'openai_compatible') ...<Widget>[
                        TextField(
                          controller: baseUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'https://seu-provedor.com/v1',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: modelController,
                        decoration: const InputDecoration(
                          labelText: 'Modelo',
                          hintText: 'gpt-4.1-mini',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: apiKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          hintText: overrideActive
                              ? 'Deixe vazio para manter a chave atual'
                              : 'Cole sua chave',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            if (current?.isUserOverride == true)
              TextButton(
                onPressed: () => Navigator.of(context).pop(
                  const _AiSettingsDialogResult.clearOverride(),
                ),
                child: const Text('Usar padrao do sistema'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _AiSettingsDialogResult.save(
                  providerType: providerTypeNotifier.value,
                  baseUrl: baseUrlController.text.trim(),
                  model: modelController.text.trim(),
                  apiKey: apiKeyController.text.trim(),
                ),
              ),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    providerTypeNotifier.dispose();
    baseUrlController.dispose();
    modelController.dispose();
    apiKeyController.dispose();

    if (result == null) {
      return;
    }

    try {
      if (result.clearOverride) {
        await widget.authController.clearAiSettings();
        _showMessage('Configuracao de IA do usuario removida. O sistema voltou ao padrao.');
        return;
      }

      if (result.model.trim().isEmpty) {
        _showMessage('Informe o modelo.');
        return;
      }
      if (result.providerType == 'openai_compatible' && result.baseUrl.trim().isEmpty) {
        _showMessage('Informe a Base URL do provider OpenAI-compatible.');
        return;
      }

      await widget.authController.updateAiSettings(
        providerType: result.providerType,
        baseUrl: result.providerType == 'openai' ? null : result.baseUrl.trim(),
        model: result.model.trim(),
        apiKey: result.apiKey.trim().isEmpty ? null : result.apiKey.trim(),
      );
      _showMessage('Configuracao de IA atualizada.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _editSelectedRecording() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    final titleController = TextEditingController(text: selected.title);
    final descriptionController =
        TextEditingController(text: selected.description ?? '');
    final languageController =
        TextEditingController(text: selected.language ?? '');

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar gravacao'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titulo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: languageController,
                  decoration: const InputDecoration(
                    labelText: 'Idioma (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Descricao (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final language = languageController.text.trim();
    titleController.dispose();
    descriptionController.dispose();
    languageController.dispose();

    if (shouldSave != true) {
      return;
    }
    if (title.isEmpty) {
      _showMessage('Titulo nao pode ficar vazio.');
      return;
    }

    try {
      await _recordingsController.updateSelectedRecording(
        accessToken: token,
        recordingId: selected.id,
        title: title,
        description: description.isEmpty ? null : description,
        language: language.isEmpty ? null : language,
      );
      _showMessage('Gravacao atualizada.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _deleteSelectedRecording() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir gravacao'),
          content: Text('Deseja realmente excluir "${selected.title}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    try {
      await _recordingsController.deleteSelectedRecording(
        accessToken: token,
        recordingId: selected.id,
      );
      final currentSelected = _recordingsController.selected;
      if (currentSelected != null) {
        await _chatController.loadForRecording(
          accessToken: token,
          recordingId: currentSelected.id,
        );
      } else {
        _chatController.clear();
      }
      _showMessage('Gravacao excluida.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          <Listenable>[_recordingsController, _chatController]),
      builder: (context, _) {
        final selected = _recordingsController.selected;
        final width = MediaQuery.of(context).size.width;
        final narrow = width < 980;

        return Scaffold(
          appBar: AppBar(
            title: const Text('AnotaAi Dashboard'),
            actions: <Widget>[
              if (widget.authController.currentUser?.name != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(widget.authController.currentUser!.name!),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(widget.authController.currentUser?.email ?? ''),
                ),
              ),
              IconButton(
                tooltip: 'Editar nome',
                onPressed: _editProfileName,
                icon: const Icon(Icons.person),
              ),
              IconButton(
                tooltip: 'Configurar IA',
                onPressed: _editAiSettings,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Sair',
                onPressed: _logout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: narrow
                ? Column(
                    children: <Widget>[
                      Expanded(flex: 5, child: _buildListPanel()),
                      const SizedBox(height: 12),
                      Expanded(flex: 6, child: _buildDetailPanel(selected)),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      SizedBox(width: 360, child: _buildListPanel()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDetailPanel(selected)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildListPanel() {
    final recordings = _recordingsController.recordings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _newRecordingController,
              decoration: const InputDecoration(
                labelText: 'Nova gravacao',
                hintText: 'Ex.: Aula de biologia',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _createRecording(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _recordingsController.isListLoading
                    ? null
                    : _createRecording,
                icon: const Icon(Icons.add),
                label: const Text('Criar gravacao'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text(
                  'Gravacoes (${recordings.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Atualizar lista',
                  onPressed: _recordingsController.isListLoading
                      ? null
                      : () async {
                          final token = widget.authController.accessToken;
                          if (token == null) {
                            return;
                          }
                          try {
                            await _recordingsController.refreshRecordings(
                                accessToken: token);
                          } on ApiException catch (error) {
                            _showMessage(error.message);
                          }
                        },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(height: 12),
            Expanded(
              child: _recordingsController.isListLoading && recordings.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : recordings.isEmpty
                      ? const Center(
                          child: Text('Nenhuma gravacao criada ainda.'))
                      : ListView.builder(
                          itemCount: recordings.length,
                          itemBuilder: (context, index) {
                            final recording = recordings[index];
                            final isSelected =
                                _recordingsController.selected?.id ==
                                    recording.id;
                            return Card(
                              color:
                                  isSelected ? const Color(0xFFE2F2EE) : null,
                              child: ListTile(
                                selected: isSelected,
                                title: Text(recording.title),
                                subtitle: Text('Status: ${recording.status}'),
                                onTap: () => _selectRecording(recording),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel(RecordingModel? selected) {
    if (selected == null) {
      return const Card(
        child: Center(
          child: Text('Selecione uma gravacao para ver detalhes.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _recordingsController.isDetailLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                selected.title,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  Chip(
                                      label:
                                          Text('Status: ${selected.status}')),
                                  Chip(
                                      label: Text(
                                          'Fonte: ${selected.sourceType}')),
                                  if (selected.language != null)
                                    Chip(
                                        label: Text(
                                            'Idioma: ${selected.language}')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Criado em ${_formatDate(selected.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (selected.description != null &&
                                  selected.description!.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  selected.description!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _editSelectedRecording,
                              icon: const Icon(Icons.edit),
                              label: const Text('Editar'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _deleteSelectedRecording,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Excluir'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _uploadAudio,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Enviar audio'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _processRecording,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Processar'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _refreshDetails,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Atualizar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_recordingsController.latestJob != null)
                      ContentSection(
                        title: 'Ultimo Job',
                        child: _buildJobCard(_recordingsController.latestJob!),
                      ),
                    ContentSection(
                      title: 'Transcricao',
                      child: SelectableText(
                        _recordingsController.transcript?.fullText ??
                            'Ainda sem transcricao. Rode o processamento para gerar.',
                      ),
                    ),
                    ContentSection(
                      title: 'Resumo',
                      child: SelectableText(
                        _recordingsController.summary?.contentMd ??
                            'Ainda sem resumo. Rode o processamento para gerar.',
                      ),
                    ),
                    ContentSection(
                      title: 'Mapa Mental (JSON)',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _recordingsController.mindmap?.prettyJson() ??
                              'Ainda sem mapa mental. Rode o processamento para gerar.',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            color: Color(0xFFEDEDED),
                          ),
                        ),
                      ),
                    ),
                    _buildChatSection(selected),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildChatSection(RecordingModel selected) {
    return ContentSection(
      title: 'Chat da Gravacao',
      actions: <Widget>[
        IconButton(
          tooltip: 'Atualizar chat',
          onPressed: _chatController.isLoading ? null : _refreshChat,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 320,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F5),
              border: Border.all(color: const Color(0xFFD7D7D1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _chatController.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _chatController.messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Ainda nao ha mensagens. Pergunte algo sobre a gravacao depois que a transcricao estiver pronta.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _chatController.messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _buildChatBubble(
                              _chatController.messages[index]);
                        },
                      ),
          ),
          if (_chatController.errorMessage != null &&
              _chatController.errorMessage!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _chatController.errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _chatInputController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Pergunte sobre esta gravacao',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _chatController.isSending ? null : _sendChatMessage,
                icon: _chatController.isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sessao: ${_chatController.session?.title ?? 'Chat principal'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessageModel message) {
    final isUser = message.isUser;
    final citations = _citationText(message.citationsJson);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFF1E6F5C) : const Color(0xFFE6ECE8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isUser ? 'Voce' : 'Assistente',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isUser ? Colors.white : const Color(0xFF20443A),
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1D1D1B),
                ),
              ),
              if (citations != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  citations,
                  style: TextStyle(
                    fontSize: 12,
                    color: isUser ? Colors.white70 : const Color(0xFF5C5E57),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobCard(JobModel job) {
    final subtitle = StringBuffer()
      ..writeln('Status: ${job.status}')
      ..writeln('Tipo: ${job.jobType}')
      ..writeln('Tentativas: ${job.attempts}')
      ..writeln('Enfileirado: ${_formatDate(job.queuedAt)}');

    if (job.startedAt != null) {
      subtitle.writeln('Inicio: ${_formatDate(job.startedAt!)}');
    }
    if (job.finishedAt != null) {
      subtitle.writeln('Fim: ${_formatDate(job.finishedAt!)}');
    }
    if (job.errorMessage != null && job.errorMessage!.isNotEmpty) {
      subtitle.writeln('Erro: ${job.errorMessage!}');
    }

    return SelectableText(subtitle.toString());
  }

  String? _citationText(Object? raw) {
    if (raw is! List<dynamic> || raw.isEmpty) {
      return null;
    }

    final items = <String>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final startMs = item['start_ms'];
      final endMs = item['end_ms'];
      if (startMs is int && endMs is int) {
        items.add(
            '[${_formatShortTimestamp(startMs)}-${_formatShortTimestamp(endMs)}]');
      }
    }

    if (items.isEmpty) {
      return null;
    }
    return 'Referencias: ${items.join(', ')}';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }

  String _formatShortTimestamp(int value) {
    final totalSeconds = value ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _AiSettingsDialogResult {
  const _AiSettingsDialogResult.save({
    required this.providerType,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  }) : clearOverride = false;

  const _AiSettingsDialogResult.clearOverride()
      : providerType = 'openai',
        baseUrl = '',
        model = '',
        apiKey = '',
        clearOverride = true;

  final String providerType;
  final String baseUrl;
  final String model;
  final String apiKey;
  final bool clearOverride;
}
