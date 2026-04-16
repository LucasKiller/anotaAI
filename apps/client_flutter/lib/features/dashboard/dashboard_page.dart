import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/chat_models.dart';
import '../../shared/models/job_model.dart';
import '../../shared/models/recording_model.dart';
import '../../shared/models/transcript_model.dart';
import '../../shared/widgets/app_markdown.dart';
import '../../shared/widgets/content_section.dart';
import '../../shared/widgets/mindmap_viewer.dart';
import '../../shared/widgets/recording_audio_player.dart';
import '../../shared/widgets/recording_audio_player_controller.dart';
import '../recordings/audio_recorder_service.dart';
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
  final _chatScrollController = ScrollController();
  final _transcriptScrollController = ScrollController();

  late final RecordingsController _recordingsController;
  late final ChatController _chatController;
  late final AudioRecorderService _audioRecorderService;
  late final RecordingAudioPlayerController _audioPlayerController;

  Timer? _liveRecordingTicker;
  bool _isLiveRecording = false;
  bool _isLiveRecordingPaused = false;
  bool _isLiveRecordingBusy = false;
  bool _isUploadingRecordedAudio = false;
  Duration _liveRecordingElapsed = Duration.zero;
  Duration _liveRecordingAccumulated = Duration.zero;
  DateTime? _liveRecordingStartedAt;
  RecordedAudioCapture? _pendingRecordedAudio;
  String? _liveRecordingError;

  @override
  void initState() {
    super.initState();
    _recordingsController = RecordingsController();
    _chatController = ChatController();
    _audioRecorderService = createAudioRecorderService();
    _audioPlayerController = RecordingAudioPlayerController();
    _chatController.addListener(_handleChatChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  @override
  void dispose() {
    _newRecordingController.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    _transcriptScrollController.dispose();
    _liveRecordingTicker?.cancel();
    unawaited(_audioRecorderService.cancel());
    _chatController.removeListener(_handleChatChanged);
    _audioPlayerController.dispose();
    _recordingsController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _handleChatChanged() {
    _scheduleChatScroll();
  }

  void _scheduleChatScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollChatToEnd();
    });
  }

  void _scrollChatToEnd({bool animated = true}) {
    if (!_chatScrollController.hasClients) {
      return;
    }
    final position = _chatScrollController.position.maxScrollExtent;
    if (animated) {
      _chatScrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _chatScrollController.jumpTo(position);
  }

  bool get _isLiveRecordingSupported => _audioRecorderService.isSupported;

  bool get _isLiveRecordingLocked =>
      _isLiveRecording ||
      _isLiveRecordingBusy ||
      _isUploadingRecordedAudio ||
      _pendingRecordedAudio != null;

  Future<void> _startLiveRecording() async {
    if (!_isLiveRecordingSupported) {
      _showMessage(
        'Gravacao ao vivo disponivel apenas em navegadores com suporte a microfone.',
      );
      return;
    }

    setState(() {
      _isLiveRecordingBusy = true;
      _liveRecordingError = null;
    });

    try {
      await _audioRecorderService.start();
      _liveRecordingTicker?.cancel();
      setState(() {
        _isLiveRecording = true;
        _isLiveRecordingPaused = false;
        _liveRecordingElapsed = Duration.zero;
        _liveRecordingAccumulated = Duration.zero;
        _liveRecordingStartedAt = DateTime.now();
        _pendingRecordedAudio = null;
      });
      _startLiveRecordingTicker();
    } catch (error) {
      setState(() {
        _liveRecordingError = _humanizeLiveRecordingError(error);
      });
      _showMessage(_liveRecordingError!);
    } finally {
      if (mounted) {
        setState(() {
          _isLiveRecordingBusy = false;
        });
      }
    }
  }

  Future<void> _pauseLiveRecording() async {
    if (!_isLiveRecording || _isLiveRecordingPaused) {
      return;
    }

    setState(() {
      _isLiveRecordingBusy = true;
      _liveRecordingError = null;
    });

    try {
      await _audioRecorderService.pause();
      _freezeLiveRecordingElapsed();
      if (!mounted) {
        return;
      }
      setState(() {
        _isLiveRecordingPaused = true;
      });
    } catch (error) {
      setState(() {
        _liveRecordingError = _humanizeLiveRecordingError(error);
      });
      _showMessage(_liveRecordingError!);
    } finally {
      if (mounted) {
        setState(() {
          _isLiveRecordingBusy = false;
        });
      }
    }
  }

  Future<void> _resumeLiveRecording() async {
    if (!_isLiveRecording || !_isLiveRecordingPaused) {
      return;
    }

    setState(() {
      _isLiveRecordingBusy = true;
      _liveRecordingError = null;
    });

    try {
      await _audioRecorderService.resume();
      if (!mounted) {
        return;
      }
      setState(() {
        _isLiveRecordingPaused = false;
        _liveRecordingStartedAt = DateTime.now();
      });
      _startLiveRecordingTicker();
    } catch (error) {
      setState(() {
        _liveRecordingError = _humanizeLiveRecordingError(error);
      });
      _showMessage(_liveRecordingError!);
    } finally {
      if (mounted) {
        setState(() {
          _isLiveRecordingBusy = false;
        });
      }
    }
  }

  Future<void> _stopLiveRecording() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null || !_isLiveRecording) {
      return;
    }

    setState(() {
      _isLiveRecordingBusy = true;
      _liveRecordingError = null;
    });

    try {
      final captured = await _audioRecorderService.stop();
      _resetLiveRecordingState();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingRecordedAudio = captured;
      });
      await _uploadPendingRecordedAudio(
        accessToken: token,
        recordingId: selected.id,
      );
    } catch (error) {
      _resetLiveRecordingState();
      if (!mounted) {
        return;
      }
      setState(() {
        _liveRecordingError = _humanizeLiveRecordingError(error);
      });
      _showMessage(_liveRecordingError!);
    } finally {
      if (mounted) {
        setState(() {
          _isLiveRecordingBusy = false;
        });
      }
    }
  }

  Future<void> _discardLiveRecording() async {
    try {
      if (_isLiveRecording) {
        await _audioRecorderService.cancel();
      }
    } catch (_) {
      // no-op
    }

    _resetLiveRecordingState();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingRecordedAudio = null;
      _liveRecordingError = null;
    });
    _showMessage('Gravacao descartada.');
  }

  Future<void> _uploadPendingRecordedAudio({
    required String accessToken,
    required String recordingId,
  }) async {
    final pending = _pendingRecordedAudio;
    if (pending == null) {
      return;
    }

    setState(() {
      _isUploadingRecordedAudio = true;
      _liveRecordingError = null;
    });

    try {
      await _recordingsController.uploadAudio(
        accessToken: accessToken,
        recordingId: recordingId,
        fileName: pending.fileName,
        bytes: pending.bytes,
        processAfterUpload: true,
        waitForCompletion: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingRecordedAudio = null;
      });
      _audioPlayerController.reset();
      _showMessage('Gravacao enviada e processada com sucesso.');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _liveRecordingError = error.message;
      });
      _showMessage(
        'Falha ao enviar a gravacao. O audio ficou salvo na sessao para reenviar.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingRecordedAudio = false;
        });
      }
    }
  }

  void _startLiveRecordingTicker() {
    _liveRecordingTicker?.cancel();
    _liveRecordingTicker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (!mounted ||
            !_isLiveRecording ||
            _isLiveRecordingPaused ||
            _liveRecordingStartedAt == null) {
          return;
        }
        final elapsed = _liveRecordingAccumulated +
            DateTime.now().difference(_liveRecordingStartedAt!);
        setState(() {
          _liveRecordingElapsed = elapsed;
        });
      },
    );
  }

  void _freezeLiveRecordingElapsed() {
    _liveRecordingTicker?.cancel();
    if (_liveRecordingStartedAt != null) {
      _liveRecordingAccumulated +=
          DateTime.now().difference(_liveRecordingStartedAt!);
    }
    _liveRecordingStartedAt = null;
    _liveRecordingElapsed = _liveRecordingAccumulated;
  }

  void _resetLiveRecordingState() {
    _liveRecordingTicker?.cancel();
    if (!mounted) {
      _isLiveRecording = false;
      _isLiveRecordingPaused = false;
      _liveRecordingElapsed = Duration.zero;
      _liveRecordingAccumulated = Duration.zero;
      _liveRecordingStartedAt = null;
      return;
    }
    setState(() {
      _isLiveRecording = false;
      _isLiveRecordingPaused = false;
      _liveRecordingElapsed = Duration.zero;
      _liveRecordingAccumulated = Duration.zero;
      _liveRecordingStartedAt = null;
    });
  }

  String _humanizeLiveRecordingError(Object error) {
    final raw = error.toString();
    if (raw.contains('NotAllowedError')) {
      return 'Permissao de microfone negada pelo navegador.';
    }
    if (raw.contains('NotFoundError')) {
      return 'Nenhum microfone disponivel foi encontrado.';
    }
    if (raw.contains('UnsupportedError')) {
      return 'O navegador atual nao suporta gravacao ao vivo.';
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de criar outra.',
      );
      return;
    }
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
      _audioPlayerController.reset();
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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de trocar de gravacao.',
      );
      return;
    }
    final token = widget.authController.accessToken;
    if (token == null) {
      return;
    }

    try {
      _audioPlayerController.reset();
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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de processar.',
      );
      return;
    }
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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de enviar outro arquivo.',
      );
      return;
    }
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
      _audioPlayerController.reset();
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

  Future<void> _syncTranscriptSegment(TranscriptSegmentModel segment) async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    if (token == null || selected == null) {
      return;
    }

    try {
      if (_audioPlayerController.loadedRecordingId != selected.id ||
          !_audioPlayerController.isLoaded) {
        await _audioPlayerController.loadForRecording(
          accessToken: token,
          recordingId: selected.id,
        );
      }
      await _audioPlayerController.seek(
        Duration(milliseconds: segment.startMs),
      );
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage(
        error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('StateError: ', ''),
      );
    }
  }

  Future<void> _sendChatMessage() async {
    final token = widget.authController.accessToken;
    final selected = _recordingsController.selected;
    final content = _chatInputController.text.trim();
    if (token == null || selected == null || content.isEmpty) {
      return;
    }

    _chatInputController.clear();

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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de editar a gravacao.',
      );
      return;
    }
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
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao ao vivo atual antes de excluir a gravacao.',
      );
      return;
    }
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
      _audioPlayerController.reset();
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
                onPressed: _recordingsController.isListLoading ||
                        _isLiveRecordingLocked
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
                  onPressed: _recordingsController.isListLoading ||
                          _isLiveRecordingLocked
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
                                onTap: _isLiveRecordingLocked
                                    ? null
                                    : () => _selectRecording(recording),
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
                              onPressed: _isLiveRecordingLocked
                                  ? null
                                  : _editSelectedRecording,
                              icon: const Icon(Icons.edit),
                              label: const Text('Editar'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _isLiveRecordingLocked
                                  ? null
                                  : _deleteSelectedRecording,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Excluir'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed:
                                  _isLiveRecordingLocked ? null : _uploadAudio,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Enviar audio'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _isLiveRecordingLocked
                                  ? null
                                  : _processRecording,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Processar'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _isLiveRecordingLocked
                                  ? null
                                  : _refreshDetails,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Atualizar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildLiveRecordingSection(selected),
                    const SizedBox(height: 16),
                    ContentSection(
                      title: 'Player Da Gravacao',
                      child: RecordingAudioPlayer(
                        key: ValueKey('player-${selected.id}'),
                        controller: _audioPlayerController,
                        accessToken: widget.authController.accessToken ?? '',
                        recordingId: selected.id,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_recordingsController.latestJob != null)
                      ContentSection(
                        title: 'Ultimo Job',
                        child: _buildJobCard(_recordingsController.latestJob!),
                      ),
                    ContentSection(
                      title: 'Transcricao',
                      child: _buildTranscriptSection(),
                    ),
                    ContentSection(
                      title: 'Resumo',
                      child: AppMarkdown(
                        data: _recordingsController.summary?.contentMd ??
                            'Ainda sem resumo. Rode o processamento para gerar.',
                      ),
                    ),
                    ContentSection(
                      title: 'Mapa Mental',
                      child: MindmapViewer(
                        key: ValueKey(_recordingsController.mindmap?.id),
                        artifact: _recordingsController.mindmap,
                        transcript: _recordingsController.transcript,
                        transcriptSegments:
                            _recordingsController.transcriptSegments,
                        emptyMessage:
                            'Ainda sem mapa mental. Rode o processamento para gerar.',
                      ),
                    ),
                    _buildChatSection(selected),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLiveRecordingSection(RecordingModel selected) {
    final statusLabel = _isUploadingRecordedAudio
        ? 'Enviando e processando'
        : _pendingRecordedAudio != null
            ? 'Pronto para enviar'
            : _isLiveRecording
                ? _isLiveRecordingPaused
                    ? 'Pausado'
                    : 'Gravando'
                : 'Parado';

    final statusColor = _isUploadingRecordedAudio
        ? const Color(0xFF9C6B00)
        : _pendingRecordedAudio != null
            ? const Color(0xFF175CD3)
            : _isLiveRecording
                ? (_isLiveRecordingPaused
                    ? const Color(0xFF7A5A00)
                    : const Color(0xFFB42318))
                : const Color(0xFF667085);

    final liveHint = _pendingRecordedAudio != null
        ? 'O audio gravado ficou pronto. Você pode reenviar ou descartar.'
        : _isLiveRecording
            ? 'Ao finalizar, o upload e o processamento serao disparados automaticamente para esta gravacao.'
            : 'Grave direto do navegador, pause se precisar e finalize quando quiser subir o audio gravado.';

    return ContentSection(
      title: 'Gravacao Ao Vivo',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E7EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _StatusChip(
                  label: statusLabel,
                  color: statusColor,
                ),
                _InfoChip(
                  label: _formatRecordingElapsed(_liveRecordingElapsed),
                  icon: Icons.fiber_manual_record,
                  color: _isLiveRecording && !_isLiveRecordingPaused
                      ? const Color(0xFFB42318)
                      : const Color(0xFF475467),
                ),
                _InfoChip(
                  label: selected.title,
                  icon: Icons.mic_external_on_outlined,
                  color: const Color(0xFF344054),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              liveHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475467),
                    height: 1.5,
                  ),
            ),
            if (!_isLiveRecordingSupported) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Esta funcionalidade depende de navegador com acesso a microfone. No MVP, ela fica disponivel no Flutter web.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB42318),
                    ),
              ),
            ],
            if (_liveRecordingError != null &&
                _liveRecordingError!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _liveRecordingError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB42318),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: !_isLiveRecordingSupported ||
                          _isLiveRecording ||
                          _isLiveRecordingBusy ||
                          _isUploadingRecordedAudio ||
                          _pendingRecordedAudio != null
                      ? null
                      : _startLiveRecording,
                  icon: const Icon(Icons.mic),
                  label: const Text('Iniciar gravacao'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: !_isLiveRecording ||
                          _isLiveRecordingPaused ||
                          _isLiveRecordingBusy
                      ? null
                      : _pauseLiveRecording,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Pausar'),
                ),
                OutlinedButton.icon(
                  onPressed: !_isLiveRecording ||
                          !_isLiveRecordingPaused ||
                          _isLiveRecordingBusy
                      ? null
                      : _resumeLiveRecording,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Continuar'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !_isLiveRecording || _isLiveRecordingBusy
                      ? null
                      : _stopLiveRecording,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    _isUploadingRecordedAudio
                        ? 'Finalizando...'
                        : 'Finalizar e enviar',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (_isLiveRecording || _pendingRecordedAudio != null) &&
                          !_isLiveRecordingBusy &&
                          !_isUploadingRecordedAudio
                      ? _discardLiveRecording
                      : null,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Descartar'),
                ),
                if (_pendingRecordedAudio != null)
                  FilledButton.icon(
                    onPressed: _isUploadingRecordedAudio
                        ? null
                        : () {
                            final token = widget.authController.accessToken;
                            if (token == null) {
                              return;
                            }
                            _uploadPendingRecordedAudio(
                              accessToken: token,
                              recordingId: selected.id,
                            );
                          },
                    icon: _isUploadingRecordedAudio
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Enviar novamente'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptSection() {
    final transcript = _recordingsController.transcript;
    final segments = _recordingsController.transcriptSegments;

    if (transcript == null && segments.isEmpty) {
      return const Text(
        'Ainda sem transcricao. Rode o processamento para gerar.',
      );
    }

    if (segments.isEmpty) {
      return SelectableText(transcript?.fullText ?? '');
    }

    return AnimatedBuilder(
      animation: _audioPlayerController,
      builder: (context, _) {
        final currentPositionMs =
            _audioPlayerController.position.inMilliseconds;
        final canSync = !_audioPlayerController.isFetchingAudio;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              canSync
                  ? 'Clique no trecho para carregar o player e sincronizar no timestamp.'
                  : 'Carregando audio para sincronizar a transcricao...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: ListView.separated(
                controller: _transcriptScrollController,
                padding: const EdgeInsets.all(12),
                shrinkWrap: true,
                itemCount: segments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final segment = segments[index];
                  final isActive = currentPositionMs >= segment.startMs &&
                      currentPositionMs <= segment.endMs;
                  return _buildTranscriptSegmentCard(
                    segment: segment,
                    isActive: isActive,
                    canSync: canSync,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTranscriptSegmentCard({
    required TranscriptSegmentModel segment,
    required bool isActive,
    required bool canSync,
  }) {
    final theme = Theme.of(context);
    final timeLabel =
        '${_formatShortTimestamp(segment.startMs)} - ${_formatShortTimestamp(segment.endMs)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canSync ? () => _syncTranscriptSegment(segment) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFEAF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isActive ? const Color(0xFF1B67F8) : const Color(0xFFE4E7EC),
            ),
            boxShadow: isActive
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x141B67F8),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF1B67F8)
                      : const Color(0xFFF2F4F7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.graphic_eq : Icons.schedule,
                  color: isActive ? Colors.white : const Color(0xFF475467),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFD9E8FF)
                                : const Color(0xFFF2F4F7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            timeLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isActive
                                  ? const Color(0xFF1B67F8)
                                  : const Color(0xFF475467),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (segment.speakerLabel != null &&
                            segment.speakerLabel!.trim().isNotEmpty)
                          Text(
                            segment.speakerLabel!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      segment.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF101828),
                        height: 1.55,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
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
            height: 380,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFF111317),
                  Color(0xFF171A1F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF242932)),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: _chatController.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _chatController.messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Ainda nao ha mensagens. Pergunte algo sobre a gravacao depois que a transcricao estiver pronta.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFB3BBC7),
                              height: 1.5,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _chatScrollController,
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
                  decoration: InputDecoration(
                    labelText: 'Pergunte sobre esta gravacao',
                    labelStyle: const TextStyle(color: Color(0xFF7A8492)),
                    filled: true,
                    fillColor: const Color(0xFF15181D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF2B313A)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF2B313A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF377DFF)),
                    ),
                  ),
                  style: const TextStyle(color: Color(0xFFF3F6FB)),
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
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B67F8),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sessao: ${_chatController.session?.title ?? 'Chat principal'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6A717C),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessageModel message) {
    final isUser = message.isUser;
    final citations = _citationText(message.citationsJson);
    final timestamp = _formatDate(message.createdAt);
    final bubbleColor =
        isUser ? const Color(0xFF1B67F8) : const Color(0xFF1A1E25);
    final bubbleBorder =
        isUser ? const Color(0xFF3D85FF) : const Color(0xFF272D38);
    final textColor = isUser ? Colors.white : const Color(0xFFF3F6FB);
    final metaLabelColor =
        isUser ? const Color(0xFFE7ECFF) : const Color(0xFFD7DCE5);
    final metaTimeColor =
        isUser ? const Color(0xFFF1C84C) : const Color(0xFFF1C84C);

    final bubble = Opacity(
      opacity: message.isPending ? 0.84 : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bubbleColor,
            border: Border.all(color: bubbleBorder),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (message.isThinking)
                const _ThinkingBubble()
              else if (message.animateTyping)
                _TypewriterText(
                  text: message.content,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.55,
                  ),
                  onCompleted: () {
                    _chatController.markMessageAnimationCompleted(message.id);
                  },
                  onProgress: () => _scrollChatToEnd(animated: false),
                )
              else
                isUser
                    ? SelectableText(
                        message.content,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          height: 1.55,
                        ),
                      )
                    : AppMarkdown(
                        data: message.content,
                        dark: true,
                      ),
              if (!message.isThinking &&
                  !message.animateTyping &&
                  citations != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  citations,
                  style: TextStyle(
                    fontSize: 12,
                    color: isUser
                        ? const Color(0xFFDCE6FF)
                        : const Color(0xFF8E98A8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: isUser
                ? <Widget>[
                    Text(
                      'Voce',
                      style: TextStyle(
                        color: metaLabelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timestamp,
                      style: TextStyle(
                        color: metaTimeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const _ChatAvatar(
                      label: 'VO',
                      backgroundColor: Color(0xFF1554D1),
                    ),
                  ]
                : <Widget>[
                    const _ChatAvatar(
                      label: 'IA',
                      backgroundColor: Color(0xFF6A34D7),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'IA',
                      style: TextStyle(
                        color: metaLabelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timestamp,
                      style: TextStyle(
                        color: metaTimeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 8),
          if (isUser)
            bubble
          else
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: bubble,
            ),
        ],
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

  String _formatRecordingElapsed(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.label,
    required this.backgroundColor,
  });

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble> {
  Timer? _timer;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 340), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeIndex = (_activeIndex + 1) % 3;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < 3; index++) ...<Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: index == _activeIndex
                  ? const Color(0xFFEEF2FA)
                  : const Color(0xFF434A55),
              shape: BoxShape.circle,
            ),
          ),
          if (index < 2) const SizedBox(width: 8),
        ],
        const SizedBox(width: 12),
        const Text(
          'Pensando...',
          style: TextStyle(
            color: Color(0xFFAAB3C2),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TypewriterText extends StatefulWidget {
  const _TypewriterText({
    required this.text,
    required this.style,
    this.onCompleted,
    this.onProgress,
  });

  final String text;
  final TextStyle style;
  final VoidCallback? onCompleted;
  final VoidCallback? onProgress;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  Timer? _timer;
  int _visibleCharacters = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant _TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _timer?.cancel();
    _visibleCharacters = 0;
    _completed = false;

    if (widget.text.isEmpty) {
      return;
    }

    final totalCharacters = widget.text.length;
    final intervalMs = totalCharacters > 260
        ? 8
        : totalCharacters > 140
            ? 11
            : 16;

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_visibleCharacters >= totalCharacters) {
        timer.cancel();
        if (!_completed) {
          _completed = true;
          widget.onCompleted?.call();
        }
        return;
      }

      setState(() {
        _visibleCharacters = (_visibleCharacters + 2).clamp(0, totalCharacters);
      });
      widget.onProgress?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleText = widget.text.substring(
      0,
      _visibleCharacters.clamp(0, widget.text.length),
    );
    return Text(
      visibleText,
      style: widget.style,
    );
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
