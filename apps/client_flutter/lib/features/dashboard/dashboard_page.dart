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
  final _homeSearchController = TextEditingController();
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
  int _currentTabIndex = 0;
  String _recordingFilter = 'all';
  String _searchQuery = '';
  _WorkspaceTab _workspaceTab = _WorkspaceTab.summary;
  int _workspaceTabDirection = 1;
  bool _workspacePlayerExpanded = false;

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
    _homeSearchController.dispose();
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

  bool _liveRecordingAlreadyHasAudio(RecordingModel? recording) {
    if (recording == null || recording.sourceType != 'live_recording') {
      return false;
    }

    if (_isLiveRecording ||
        _pendingRecordedAudio != null ||
        _isUploadingRecordedAudio) {
      return false;
    }

    if (recording.status != 'draft') {
      return true;
    }
    if ((recording.durationMs ?? 0) > 0 || recording.processedAt != null) {
      return true;
    }
    if (_recordingsController.transcript != null ||
        _recordingsController.transcriptSegments.isNotEmpty ||
        _recordingsController.summary != null ||
        _recordingsController.mindmap != null ||
        _recordingsController.latestJob != null) {
      return true;
    }

    return false;
  }

  Future<void> _startLiveRecording() async {
    if (!_isLiveRecordingSupported) {
      _showMessage(
        'Gravacao ao vivo disponivel apenas em navegadores com suporte a microfone.',
      );
      return;
    }
    final selected = _recordingsController.selected;
    if (_liveRecordingAlreadyHasAudio(selected)) {
      _showMessage(
        'Esta gravacao ja possui audio. Crie uma nova gravacao para gravar novamente.',
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
      if (mounted) {
        setState(() {
          _workspaceTab = _WorkspaceTab.summary;
          _workspaceTabDirection = 1;
          _workspacePlayerExpanded = false;
        });
      }
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
      if (!_workspacePlayerExpanded && mounted) {
        setState(() {
          _workspacePlayerExpanded = true;
        });
      }
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

  Future<void> _loadWorkspaceAudio(RecordingModel selected) async {
    final token = widget.authController.accessToken;
    if (token == null) {
      return;
    }

    try {
      await _audioPlayerController.loadForRecording(
        accessToken: token,
        recordingId: selected.id,
      );
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage(_humanizeLiveRecordingError(error));
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
                      if (existingKeyHint != null &&
                          existingKeyHint.isNotEmpty) ...<Widget>[
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
        _showMessage(
            'Configuracao de IA do usuario removida. O sistema voltou ao padrao.');
        return;
      }

      if (result.model.trim().isEmpty) {
        _showMessage('Informe o modelo.');
        return;
      }
      if (result.providerType == 'openai_compatible' &&
          result.baseUrl.trim().isEmpty) {
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

  Future<void> _openCreateRecordingSheet() async {
    if (_isLiveRecordingLocked) {
      _showMessage(
        'Finalize, envie ou descarte a gravacao atual antes de criar outra.',
      );
      return;
    }

    final choice = await showModalBottomSheet<_QuickCreateChoice?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _QuickCreateSheet(),
    );

    if (choice == null) {
      return;
    }

    final recording = await _createRecordingForMode(choice);
    if (recording == null || !mounted) {
      return;
    }

    if (choice.mode == _QuickCreateMode.liveRecording) {
      await _openRecordingWorkspace(
        recording,
        autoStartLiveRecording: true,
      );
      return;
    }

    await _uploadAudio();
    if (!mounted) {
      return;
    }
    await _openRecordingWorkspace(recording);
  }

  Future<RecordingModel?> _createRecordingForMode(
      _QuickCreateChoice choice) async {
    final token = widget.authController.accessToken;
    if (token == null) {
      return null;
    }

    final title = choice.title.trim().isEmpty
        ? _defaultRecordingTitle(choice.mode)
        : choice.title.trim();

    try {
      await _recordingsController.createRecording(
        accessToken: token,
        title: title,
        sourceType: choice.mode == _QuickCreateMode.liveRecording
            ? 'live_recording'
            : 'upload',
      );
      _audioPlayerController.reset();
      final selected = _recordingsController.selected;
      if (selected != null) {
        await _chatController.loadForRecording(
          accessToken: token,
          recordingId: selected.id,
        );
      }
      return selected;
    } on ApiException catch (error) {
      _showMessage(error.message);
      return null;
    }
  }

  String _defaultRecordingTitle(_QuickCreateMode mode) {
    final now = DateTime.now();
    final suffix =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return mode == _QuickCreateMode.liveRecording
        ? 'Gravacao ao vivo $suffix'
        : 'Upload de audio $suffix';
  }

  Future<void> _openRecordingWorkspace(
    RecordingModel recording, {
    bool autoStartLiveRecording = false,
  }) async {
    await _selectRecording(recording);
    if (!mounted) {
      return;
    }

    if (autoStartLiveRecording) {
      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (!mounted || _isLiveRecording) {
          return;
        }
        await _startLiveRecording();
      });
    }

    if (_useDesktopDashboardLayout(context)) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF2F4F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                      <Listenable>[
                        _recordingsController,
                        _chatController,
                        _audioPlayerController,
                      ],
                    ),
                    builder: (context, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child:
                            _buildDetailPanel(_recordingsController.selected),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRecordingActions(RecordingModel recording) async {
    final action = await showModalBottomSheet<_RecordingAction?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF13171D),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF262B33)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF303743),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildActionTile(
                    icon: Icons.open_in_full_rounded,
                    label: 'Abrir workspace',
                    onTap: () =>
                        Navigator.of(context).pop(_RecordingAction.open),
                  ),
                  _buildActionTile(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Processar novamente',
                    onTap: () =>
                        Navigator.of(context).pop(_RecordingAction.process),
                  ),
                  _buildActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Editar detalhes',
                    onTap: () =>
                        Navigator.of(context).pop(_RecordingAction.edit),
                  ),
                  _buildActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Excluir',
                    destructive: true,
                    onTap: () =>
                        Navigator.of(context).pop(_RecordingAction.delete),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    await _selectRecording(recording);
    switch (action) {
      case _RecordingAction.open:
        await _openRecordingWorkspace(recording);
        break;
      case _RecordingAction.process:
        await _processRecording();
        break;
      case _RecordingAction.edit:
        await _editSelectedRecording();
        break;
      case _RecordingAction.delete:
        await _deleteSelectedRecording();
        break;
    }
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? const Color(0xFFFF6B6B) : Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Iterable<RecordingModel> get _visibleRecordings {
    final query = _searchQuery.trim().toLowerCase();
    return _recordingsController.recordings.where((recording) {
      final matchesFilter = switch (_recordingFilter) {
        'ready' => recording.status == 'ready',
        'processing' => recording.status == 'processing',
        'failed' => recording.status == 'failed',
        _ => true,
      };
      if (!matchesFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack = <String>[
        recording.title,
        recording.description ?? '',
        recording.language ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    });
  }

  List<_RecordingGroup> get _groupedRecordings {
    final map = <DateTime, List<RecordingModel>>{};
    for (final recording in _visibleRecordings) {
      final localDate = recording.createdAt.toLocal();
      final key = DateTime(localDate.year, localDate.month, localDate.day);
      map.putIfAbsent(key, () => <RecordingModel>[]).add(recording);
    }
    final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return days
        .map(
          (day) => _RecordingGroup(
            day: day,
            items: map[day]!
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          ),
        )
        .toList();
  }

  String _recordingEmoji(RecordingModel recording) {
    final text =
        '${recording.title} ${recording.description ?? ''}'.toLowerCase();
    if (text.contains('reuni') || text.contains('meeting')) {
      return '🤝';
    }
    if (text.contains('bio') ||
        text.contains('quim') ||
        text.contains('fisic') ||
        text.contains('laborat')) {
      return '🧪';
    }
    if (text.contains('math') ||
        text.contains('algebra') ||
        text.contains('calculo') ||
        text.contains('estat')) {
      return '📐';
    }
    if (text.contains('hist') || text.contains('geo')) {
      return '🗺️';
    }
    if (text.contains('python') ||
        text.contains('flutter') ||
        text.contains('codigo') ||
        text.contains('program')) {
      return '💻';
    }
    if (text.contains('direito') || text.contains('legal')) {
      return '⚖️';
    }
    if (text.contains('med') || text.contains('saud')) {
      return '🩺';
    }
    if (text.contains('ingles') ||
        text.contains('espanhol') ||
        text.contains('idioma') ||
        text.contains('lingua')) {
      return '🗣️';
    }
    if (text.contains('mark') ||
        text.contains('venda') ||
        text.contains('negoc')) {
      return '📈';
    }
    return '🎙️';
  }

  String _formatDayHeader(DateTime day) {
    const weekdays = <String>[
      'segunda-feira',
      'terca-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sabado',
      'domingo',
    ];
    const months = <String>[
      'jan.',
      'fev.',
      'mar.',
      'abr.',
      'mai.',
      'jun.',
      'jul.',
      'ago.',
      'set.',
      'out.',
      'nov.',
      'dez.',
    ];
    return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
  }

  String _formatRecordingMeta(RecordingModel recording) {
    final local = recording.createdAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final duration = recording.durationMs == null
        ? null
        : _formatDurationMs(recording.durationMs!);
    return duration == null ? '$hh:$mm' : '$hh:$mm  ·  $duration';
  }

  String _formatDurationMs(int value) {
    final totalMinutes = value ~/ 60000;
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      return '${hours}h${minutes.toString().padLeft(2, '0')}';
    }
    return '${totalMinutes}min';
  }

  String _profileAiSummary() {
    final settings = widget.authController.aiSettings;
    if (settings == null) {
      return 'Usando configuracao padrao do sistema.';
    }
    final provider = settings.isOpenAi ? 'OpenAI' : 'OpenAI-compatible';
    return '$provider · ${settings.model}';
  }

  String _userInitials(String? name, String? email) {
    final source = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (email ?? '').trim();
    if (source.isEmpty) {
      return 'AI';
    }
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        <Listenable>[
          _recordingsController,
          _chatController,
          _audioPlayerController,
          widget.authController,
        ],
      ),
      builder: (context, _) {
        final isDesktopLayout = _useDesktopDashboardLayout(context);
        return Scaffold(
          backgroundColor: const Color(0xFF090B10),
          extendBody: !isDesktopLayout,
          body: SafeArea(
            child: _buildDashboardShell(isDesktopLayout: isDesktopLayout),
          ),
          floatingActionButtonLocation: isDesktopLayout
              ? FloatingActionButtonLocation.endFloat
              : FloatingActionButtonLocation.centerDocked,
          floatingActionButton:
              isDesktopLayout ? null : _buildCentralCreateButton(),
          bottomNavigationBar:
              isDesktopLayout ? null : _buildBottomNavigationBar(),
        );
      },
    );
  }

  bool _useDesktopDashboardLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1180;

  Widget _buildDashboardShell({required bool isDesktopLayout}) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  const Color(0xFF0A0C11),
                  const Color(0xFF0B0E14),
                  const Color(0xFF11141D).withValues(alpha: 0.92),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  const Color(0xFF5B7CFF).withValues(alpha: 0.24),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 120,
          left: -100,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  const Color(0xFFFF7A59).withValues(alpha: 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: isDesktopLayout
              ? _buildDesktopDashboardShell()
              : _buildMobileDashboardShell(),
        ),
      ],
    );
  }

  Widget _buildMobileDashboardShell() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _currentTabIndex == 0 ? _buildHomeTab() : _buildProfileTab(),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDashboardShell() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: SizedBox(
            height: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 112,
                  child: _buildDesktopNavigationRail(),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 440,
                  child: _buildDesktopMainPanel(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _currentTabIndex == 0
                        ? _buildDesktopWorkspacePanel()
                        : _buildDesktopProfileAside(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavigationRail() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11151C),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFF242A33)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFF5B7CFF),
                  Color(0xFF8B5CFF),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: const Text(
              'AI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _buildDesktopRailButton(
            index: 0,
            icon: Icons.home_rounded,
            label: 'Home',
          ),
          const SizedBox(height: 12),
          _buildDesktopRailButton(
            index: 1,
            icon: Icons.person_rounded,
            label: 'Usuario',
          ),
          const Spacer(),
          InkWell(
            onTap: _openCreateRecordingSheet,
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFF5B7CFF),
                    Color(0xFF8B5CFF),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x555B7CFF),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                children: <Widget>[
                  Icon(Icons.add_rounded, color: Colors.white, size: 30),
                  SizedBox(height: 6),
                  Text(
                    'Criar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopRailButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = _currentTabIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1A2030) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? const Color(0xFF364152) : Colors.transparent,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              size: 28,
              color: active ? Colors.white : const Color(0xFF667085),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopMainPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10151D),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF242A33)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _currentTabIndex == 0 ? _buildHomeTab() : _buildProfileTab(),
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspacePanel() {
    final selected = _recordingsController.selected;
    if (selected == null) {
      return _buildDesktopEmptyWorkspaceState();
    }

    return Container(
      key: ValueKey('workspace-${selected.id}'),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1219),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: const Color(0xFF222936).withValues(alpha: 0.42),
          width: 0.8,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _buildDetailPanel(selected),
        ),
      ),
    );
  }

  Widget _buildDesktopEmptyWorkspaceState() {
    return Container(
      key: const ValueKey('workspace-empty'),
      decoration: BoxDecoration(
        color: const Color(0xFF10151D),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF242A33)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFF5B7CFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.library_music_rounded,
                color: Color(0xFF89A2FF),
                size: 34,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Workspace da gravacao',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Na web, a gravacao selecionada fica fixa aqui. Abra um item da lista para ver player, transcricao, resumo, mapa mental e chat sem trocar de tela.',
              style: TextStyle(
                color: Color(0xFFA8B1BE),
                height: 1.55,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: const <Widget>[
                _InfoChip(
                  label: 'Player sincronizado',
                  icon: Icons.play_circle_outline_rounded,
                  color: Color(0xFF344054),
                ),
                _InfoChip(
                  label: 'Chat por gravacao',
                  icon: Icons.chat_bubble_outline_rounded,
                  color: Color(0xFF344054),
                ),
                _InfoChip(
                  label: 'Mapa mental interativo',
                  icon: Icons.account_tree_outlined,
                  color: Color(0xFF344054),
                ),
              ],
            ),
            const Spacer(),
            InkWell(
              onTap: _openCreateRecordingSheet,
              borderRadius: BorderRadius.circular(28),
              child: Ink(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      const Color(0xFF18202B),
                      const Color(0xFF121720),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF252B34)),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Criar uma nova gravacao ou enviar um audio pronto',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Color(0xFF98A2B3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopProfileAside() {
    final user = widget.authController.currentUser;
    final total = _recordingsController.recordings.length;
    final ready = _recordingsController.recordings
        .where((item) => item.status == 'ready')
        .length;

    return Container(
      key: const ValueKey('profile-aside'),
      decoration: BoxDecoration(
        color: const Color(0xFF10151D),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF242A33)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 74,
                  height: 74,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[
                        Color(0xFF5B7CFF),
                        Color(0xFF8A5BFF),
                      ],
                    ),
                  ),
                  child: Text(
                    _userInitials(user?.name, user?.email),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user?.name?.trim().isNotEmpty == true
                            ? user!.name!
                            : 'Usuario',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          color: Color(0xFFA8B1BE),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _InfoChip(
                  label: '$total gravacoes',
                  icon: Icons.folder_copy_outlined,
                  color: const Color(0xFF344054),
                ),
                _InfoChip(
                  label: '$ready prontas',
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF23B26D),
                ),
                _InfoChip(
                  label: _profileAiSummary(),
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF344054),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF151B24),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF252B34)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Versao web adaptada',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'A lista principal fica em uma coluna dedicada e o detalhe da gravacao aparece ao lado. O objetivo aqui e reduzir cliques sem abandonar a linguagem visual do mobile.',
                    style: TextStyle(
                      color: Color(0xFFA8B1BE),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFF1D2332),
                    Color(0xFF151B27),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF2C3441)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Fluxo atual',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Home para operar as gravacoes.\nUsuario para IA, conta e preferencias.\nCriar para upload ou gravacao ao vivo.',
                    style: TextStyle(
                      color: Color(0xFFD0D5DD),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final groups = _groupedRecordings;
    final isLoading = _recordingsController.isListLoading &&
        _recordingsController.recordings.isEmpty;

    return Column(
      key: const ValueKey('home-tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AnotaAi',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.6,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gravacoes agrupadas por dia, com acesso rapido ao workspace.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFA8B1BE),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: _recordingsController.isListLoading
                  ? null
                  : () async {
                      final token = widget.authController.accessToken;
                      if (token == null) {
                        return;
                      }
                      try {
                        await _recordingsController.refreshRecordings(
                          accessToken: token,
                        );
                      } on ApiException catch (error) {
                        _showMessage(error.message);
                      }
                    },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF161A21),
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
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final ultraCompact = constraints.maxWidth < 420;
            final compact = constraints.maxWidth < 560;
            final spacing = ultraCompact ? 6.0 : 10.0;
            final chips = <Widget>[
              _buildFilterChip(
                label: 'Todos',
                value: 'all',
                compact: compact,
              ),
              _buildFilterChip(
                label: ultraCompact ? 'Pront.' : 'Prontas',
                value: 'ready',
                compact: compact,
              ),
              _buildFilterChip(
                label: compact ? 'Proc.' : 'Processando',
                value: 'processing',
                compact: compact,
              ),
              _buildFilterChip(
                label: ultraCompact ? 'Falh.' : 'Falhas',
                value: 'failed',
                compact: compact,
              ),
            ];

            return Row(
              children: <Widget>[
                for (var index = 0; index < chips.length; index++) ...<Widget>[
                  if (index > 0) SizedBox(width: spacing),
                  Expanded(child: chips[index]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF141922),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF232935)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.search_rounded, color: Color(0xFF8892A0)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _homeSearchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Pesquisar gravacoes',
                    hintStyle: TextStyle(color: Color(0xFF667085)),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              IconButton(
                tooltip: 'Limpar busca',
                onPressed: _searchQuery.trim().isEmpty
                    ? null
                    : () {
                        _homeSearchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF8892A0),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_isLiveRecording || _pendingRecordedAudio != null) ...<Widget>[
          _buildCompactLiveBanner(),
          const SizedBox(height: 18),
        ],
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : groups.isEmpty
                  ? _buildEmptyHomeState()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 22),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _formatDayHeader(group.day),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            ...group.items.map(_buildRecordingListCard),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCompactLiveBanner() {
    final label = _pendingRecordedAudio != null
        ? 'Audio pronto para enviar'
        : _isLiveRecordingPaused
            ? 'Gravacao pausada'
            : 'Gravacao em andamento';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFF181D27),
            const Color(0xFF161B24),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2A313C)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF5B7CFF).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.mic_rounded, color: Color(0xFF7E95FF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pendingRecordedAudio != null
                      ? 'Voce pode enviar novamente ou descartar no workspace.'
                      : 'Tempo atual ${_formatRecordingElapsed(_liveRecordingElapsed)}',
                  style: const TextStyle(
                    color: Color(0xFFAAB3C2),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              final selected = _recordingsController.selected;
              if (selected != null) {
                _openRecordingWorkspace(selected);
              }
            },
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHomeState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF12161C),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF252B34)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF5B7CFF).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 34,
                color: Color(0xFF8EA1FF),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma gravacao encontrada',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use o botao central para gravar algo novo ou enviar um audio ja existente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFA8B1BE),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    bool compact = false,
  }) {
    final active = _recordingFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _recordingFilter = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 18,
          vertical: compact ? 11 : 12,
        ),
        decoration: BoxDecoration(
          color: active ? null : const Color(0xFF151922),
          gradient: active
              ? const LinearGradient(
                  colors: <Color>[
                    Color(0xFF8A79FF),
                    Color(0xFF5B7CFF),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFF93A4FF).withValues(alpha: 0.8)
                : const Color(0xFF252B34),
          ),
          boxShadow: active
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x335B7CFF),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 14 : 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingListCard(RecordingModel recording) {
    final isSelected = _recordingsController.selected?.id == recording.id;
    final statusColor = switch (recording.status) {
      'ready' => const Color(0xFF23B26D),
      'processing' => const Color(0xFFF5B944),
      'failed' => const Color(0xFFF97066),
      _ => const Color(0xFF98A2B3),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _openRecordingWorkspace(recording),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF1B2230)
                  : const Color(0xFF141922),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF4A65F6)
                    : const Color(0xFF252B34),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 62,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        const Color(0xFF202635),
                        const Color(0xFF1A1E28),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _recordingEmoji(recording),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        recording.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatRecordingMeta(recording),
                        style: const TextStyle(
                          color: Color(0xFF8A93A2),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            recording.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showRecordingActions(recording),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = widget.authController.currentUser;
    final total = _recordingsController.recordings.length;
    final ready = _recordingsController.recordings
        .where((item) => item.status == 'ready')
        .length;
    final processing = _recordingsController.recordings
        .where((item) => item.status == 'processing')
        .length;

    return SingleChildScrollView(
      key: const ValueKey('profile-tab'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Perfil',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Informacoes da conta, configuracao da IA e atalhos da sessao.',
            style: TextStyle(
              color: Color(0xFFA8B1BE),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF141922),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF252B34)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(0xFF5B7CFF),
                            Color(0xFF8A5BFF),
                          ],
                        ),
                      ),
                      child: Text(
                        _userInitials(user?.name, user?.email),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            user?.name?.trim().isNotEmpty == true
                                ? user!.name!
                                : 'Sem nome definido',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              color: Color(0xFFA8B1BE),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _InfoChip(
                      label: '$total gravacoes',
                      icon: Icons.folder_copy_outlined,
                      color: const Color(0xFF344054),
                    ),
                    _InfoChip(
                      label: '$ready prontas',
                      icon: Icons.check_circle_outline_rounded,
                      color: const Color(0xFF23B26D),
                    ),
                    _InfoChip(
                      label: '$processing processando',
                      icon: Icons.sync_rounded,
                      color: const Color(0xFFF5B944),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildProfileSection(
            title: 'IA do usuario',
            subtitle: _profileAiSummary(),
            child: Column(
              children: <Widget>[
                _buildProfileActionButton(
                  icon: Icons.tune_rounded,
                  title: 'Configurar IA',
                  subtitle:
                      'OpenAI oficial ou provider OpenAI-compatible com chave propria.',
                  onTap: _editAiSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildProfileSection(
            title: 'Conta e opcoes',
            subtitle: 'Ajustes pessoais e comandos administrativos.',
            child: Column(
              children: <Widget>[
                _buildProfileActionButton(
                  icon: Icons.badge_outlined,
                  title: 'Editar nome',
                  subtitle: 'Atualiza como seu nome aparece na dashboard.',
                  onTap: _editProfileName,
                ),
                const SizedBox(height: 10),
                _buildProfileActionButton(
                  icon: Icons.refresh_rounded,
                  title: 'Atualizar gravacoes',
                  subtitle: 'Busca a lista mais recente da API.',
                  onTap: () async {
                    final token = widget.authController.accessToken;
                    if (token == null) {
                      return;
                    }
                    try {
                      await _recordingsController.refreshRecordings(
                        accessToken: token,
                      );
                    } on ApiException catch (error) {
                      _showMessage(error.message);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileActionButton(
                  icon: Icons.logout_rounded,
                  title: 'Sair',
                  subtitle: 'Encerra a sessao atual neste navegador.',
                  onTap: _logout,
                  destructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141922),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFA8B1BE),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildProfileActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final titleColor = destructive ? const Color(0xFFFF8B82) : Colors.white;
    final iconColor =
        destructive ? const Color(0xFFFF8B82) : const Color(0xFF89A2FF);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF181D25),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF292F39)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA8B1BE),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF7C8694),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCentralCreateButton() {
    return SizedBox(
      width: 84,
      height: 84,
      child: FloatingActionButton(
        heroTag: 'dashboard-create',
        elevation: 10,
        backgroundColor: Colors.transparent,
        onPressed: _openCreateRecordingSheet,
        shape: const CircleBorder(),
        child: Ink(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: <Color>[
                Color(0xFF5B7CFF),
                Color(0xFF8B5CFF),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Icon(Icons.add_rounded, size: 40, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox(
          height: 82,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _buildBottomNavIsland(
                  child: _buildNavButton(
                    index: 0,
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                  ),
                ),
              ),
              const SizedBox(width: 106),
              Expanded(
                child: _buildBottomNavIsland(
                  child: _buildNavButton(
                    index: 1,
                    icon: Icons.person_rounded,
                    label: 'Usuario',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavIsland({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151922).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF242A33)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildNavButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = _currentTabIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 30,
              color: active ? Colors.white : const Color(0xFF6E7685),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF6E7685),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel(RecordingModel? selected) {
    if (selected == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF10141B),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: const Color(0xFF323A46).withValues(alpha: 0.55),
            width: 0.8,
          ),
        ),
        child: const Center(
          child: Text(
            'Selecione uma gravacao para ver detalhes.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10141B),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF323A46).withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(isWide ? 20 : 14),
            child: _recordingsController.isDetailLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildWorkspaceHeader(
                        selected,
                        isWide: isWide,
                        panelWidth: constraints.maxWidth,
                      ),
                      SizedBox(height: isWide ? 14 : 12),
                      _buildWorkspaceTabBar(),
                      const SizedBox(height: 12),
                      _buildWorkspacePlayerCard(selected),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ClipRect(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              final currentKey = ValueKey<String>(
                                'workspace-tab-${_workspaceTab.name}-${selected.id}',
                              );
                              final isIncoming = child.key == currentKey;
                              final beginX = isIncoming
                                  ? (_workspaceTabDirection > 0 ? 0.14 : -0.14)
                                  : (_workspaceTabDirection > 0 ? -0.10 : 0.10);
                              final fade = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              );
                              final offset = Tween<Offset>(
                                begin: Offset(beginX, 0),
                                end: Offset.zero,
                              ).animate(fade);

                              return FadeTransition(
                                opacity: fade,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildWorkspaceTabContent(
                              selected,
                              isWide: isWide,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceHeader(
    RecordingModel selected, {
    required bool isWide,
    required double panelWidth,
  }) {
    final metaCards = <Widget>[
      _buildWorkspaceMetaPill(
        icon: Icons.schedule_rounded,
        label: _formatDate(selected.createdAt),
      ),
      _buildWorkspaceMetaPill(
        icon: Icons.radio_button_checked_rounded,
        label: selected.status,
        accent: switch (selected.status) {
          'ready' => const Color(0xFF23B26D),
          'processing' => const Color(0xFFF5B944),
          'failed' => const Color(0xFFF97066),
          _ => const Color(0xFF98A2B3),
        },
      ),
      _buildWorkspaceMetaPill(
        icon: Icons.source_outlined,
        label: selected.sourceType == 'live_recording'
            ? 'Gravacao ao vivo'
            : 'Upload',
      ),
      if (selected.language != null && selected.language!.trim().isNotEmpty)
        _buildWorkspaceMetaPill(
          icon: Icons.language_rounded,
          label: selected.language!,
        ),
    ];
    final compactActions = panelWidth < 980;
    final veryCompactActions = panelWidth < 620;
    final actionBar = _buildWorkspaceActionBar(
      compact: compactActions,
      veryCompact: veryCompactActions,
    );

    if (isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildWorkspaceIdentity(
            selected,
            isWide: true,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      ...metaCards.map(
                        (card) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: card,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              actionBar,
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildWorkspaceIdentity(selected, isWide: false),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    ...metaCards.map(
                      (card) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: card,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            actionBar,
          ],
        ),
      ],
    );
  }

  Widget _buildWorkspaceIdentity(
    RecordingModel selected, {
    required bool isWide,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: isWide ? 62 : 54,
          height: isWide ? 62 : 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF171C24),
            borderRadius: BorderRadius.circular(isWide ? 20 : 18),
            border: Border.all(
              color: const Color(0xFF3A4250).withValues(alpha: 0.58),
              width: 0.8,
            ),
          ),
          child: Text(
            _recordingEmoji(selected),
            style: TextStyle(fontSize: isWide ? 34 : 28),
          ),
        ),
        SizedBox(width: isWide ? 14 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                selected.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isWide ? 28 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: isWide ? -0.9 : -0.5,
                  height: 1.05,
                ),
              ),
              if (selected.description != null &&
                  selected.description!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  selected.description!,
                  maxLines: isWide ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFA8B1BE),
                    fontSize: isWide ? 14 : 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceMetaPill({
    required IconData icon,
    required String label,
    Color accent = const Color(0xFF8E98A8),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171C24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF3A4250).withValues(alpha: 0.52),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceActionBar({
    required bool compact,
    required bool veryCompact,
  }) {
    final items = <Widget>[
      if (!veryCompact)
        _buildWorkspaceActionIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Editar gravacao',
          onTap: _isLiveRecordingLocked ? null : _editSelectedRecording,
        ),
      if (!veryCompact)
        _buildWorkspaceActionIconButton(
          icon: Icons.upload_file_rounded,
          tooltip: 'Enviar audio',
          onTap: _isLiveRecordingLocked ? null : _uploadAudio,
        ),
      _buildWorkspaceActionIconButton(
        icon: Icons.play_arrow_rounded,
        tooltip: 'Processar gravacao',
        emphasized: true,
        onTap: _isLiveRecordingLocked ? null : _processRecording,
      ),
      if (!compact && !veryCompact)
        _buildWorkspaceActionIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Atualizar dados',
          onTap: _isLiveRecordingLocked ? null : _refreshDetails,
        ),
      _buildWorkspaceOverflowButton(
        veryCompact: veryCompact,
        includeRefresh: compact || veryCompact,
      ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < items.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: 8),
          items[index],
        ],
      ],
    );
  }

  Widget _buildWorkspaceOverflowButton({
    required bool veryCompact,
    required bool includeRefresh,
  }) {
    return PopupMenuButton<_WorkspaceOverflowAction>(
      tooltip: 'Mais acoes',
      enabled: !_isLiveRecordingLocked,
      color: const Color(0xFF171C24),
      surfaceTintColor: Colors.transparent,
      onSelected: (action) {
        switch (action) {
          case _WorkspaceOverflowAction.edit:
            _editSelectedRecording();
          case _WorkspaceOverflowAction.upload:
            _uploadAudio();
          case _WorkspaceOverflowAction.refresh:
            _refreshDetails();
          case _WorkspaceOverflowAction.delete:
            _deleteSelectedRecording();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<_WorkspaceOverflowAction>>[
        if (veryCompact)
          const PopupMenuItem<_WorkspaceOverflowAction>(
            value: _WorkspaceOverflowAction.edit,
            child: Row(
              children: <Widget>[
                Icon(Icons.edit_outlined, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Editar',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        if (veryCompact)
          const PopupMenuItem<_WorkspaceOverflowAction>(
            value: _WorkspaceOverflowAction.upload,
            child: Row(
              children: <Widget>[
                Icon(Icons.upload_file_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Enviar audio',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        if (includeRefresh)
          const PopupMenuItem<_WorkspaceOverflowAction>(
            value: _WorkspaceOverflowAction.refresh,
            child: Row(
              children: <Widget>[
                Icon(Icons.refresh_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Atualizar',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        const PopupMenuItem<_WorkspaceOverflowAction>(
          value: _WorkspaceOverflowAction.delete,
          child: Row(
            children: <Widget>[
              Icon(Icons.delete_outline_rounded, color: Color(0xFFFF9A91)),
              SizedBox(width: 10),
              Text(
                'Excluir',
                style: TextStyle(color: Color(0xFFFF9A91)),
              ),
            ],
          ),
        ),
      ],
      child: Opacity(
        opacity: _isLiveRecordingLocked ? 0.42 : 1,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF171C24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF282F39).withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceActionIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool emphasized = false,
    bool destructive = false,
  }) {
    final background = destructive
        ? const Color(0xFF2A171A)
        : emphasized
            ? const Color(0xFF5B7CFF)
            : const Color(0xFF171C24);
    final border = destructive
        ? const Color(0xFF4A2329)
        : emphasized
            ? const Color(0xFF6C89FF)
            : const Color(0xFF282F39);
    final foreground = destructive ? const Color(0xFFFF9A91) : Colors.white;

    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.42 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: border.withValues(alpha: emphasized ? 0.82 : 0.55),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 19, color: foreground),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceTabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _WorkspaceTab.values
            .map((tab) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildWorkspaceTabButton(tab),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildWorkspaceTabButton(_WorkspaceTab tab) {
    final active = _workspaceTab == tab;
    final currentIndex = _WorkspaceTab.values.indexOf(_workspaceTab);
    final targetIndex = _WorkspaceTab.values.indexOf(tab);
    final (icon, label) = switch (tab) {
      _WorkspaceTab.summary => (Icons.summarize_outlined, 'Resumo'),
      _WorkspaceTab.transcript => (Icons.notes_rounded, 'Transcricao'),
      _WorkspaceTab.mindmap => (Icons.account_tree_outlined, 'Mapa mental'),
      _WorkspaceTab.chat => (Icons.smart_toy_outlined, 'Chat'),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        if (tab == _workspaceTab) {
          return;
        }
        setState(() {
          _workspaceTabDirection = targetIndex >= currentIndex ? 1 : -1;
          _workspaceTab = tab;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: <Color>[
                    Color(0xFF9C7CFF),
                    Color(0xFF5B7CFF),
                  ],
                )
              : null,
          color: active ? null : const Color(0xFF151922),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? const Color(0xFF7E92FF).withValues(alpha: 0.82)
                : const Color(0xFF3A4250).withValues(alpha: 0.5),
            width: active ? 0.9 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspacePlayerCard(RecordingModel selected) {
    return AnimatedBuilder(
      animation: _audioPlayerController,
      builder: (context, _) {
        final isLoadedForSelected =
            _audioPlayerController.loadedRecordingId == selected.id &&
                _audioPlayerController.isLoaded;
        final isPlaying =
            isLoadedForSelected && _audioPlayerController.isPlaying;
        final isFetching = _audioPlayerController.isFetchingAudio;
        final timeLabel = isLoadedForSelected
            ? '${_formatRecordingElapsed(_audioPlayerController.position)} / ${_formatRecordingElapsed(_audioPlayerController.duration)}'
            : 'Abra apenas quando precisar ouvir';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141922),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF323A46).withValues(alpha: 0.48),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  InkWell(
                    onTap: isFetching
                        ? null
                        : () async {
                            if (isLoadedForSelected) {
                              await _audioPlayerController.togglePlayback();
                              return;
                            }
                            await _loadWorkspaceAudio(selected);
                          },
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2231),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: isFetching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF8AA0FF),
                                ),
                              )
                            : Icon(
                                isLoadedForSelected
                                    ? (isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded)
                                    : Icons.headphones_rounded,
                                color: const Color(0xFF8AA0FF),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Audio da gravacao',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isFetching ? 'Carregando audio...' : timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAB3C2),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isLoadedForSelected
                        ? 'Recarregar audio'
                        : 'Carregar audio',
                    onPressed:
                        isFetching ? null : () => _loadWorkspaceAudio(selected),
                    icon: Icon(
                      isLoadedForSelected
                          ? Icons.refresh_rounded
                          : Icons.download_rounded,
                      color: const Color(0xFFAAB3C2),
                    ),
                  ),
                  IconButton(
                    tooltip: _workspacePlayerExpanded
                        ? 'Recolher player'
                        : 'Expandir player',
                    onPressed: () {
                      setState(() {
                        _workspacePlayerExpanded = !_workspacePlayerExpanded;
                      });
                    },
                    icon: Icon(
                      _workspacePlayerExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFFAAB3C2),
                    ),
                  ),
                ],
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: _workspacePlayerExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RecordingAudioPlayer(
                            key: ValueKey('player-${selected.id}'),
                            controller: _audioPlayerController,
                            accessToken:
                                widget.authController.accessToken ?? '',
                            recordingId: selected.id,
                            compact: true,
                            showHeader: false,
                            framed: false,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceTabContent(
    RecordingModel selected, {
    required bool isWide,
  }) {
    final content = switch (_workspaceTab) {
      _WorkspaceTab.summary => _buildWorkspaceSummaryTab(selected),
      _WorkspaceTab.transcript => _buildWorkspaceTranscriptTab(),
      _WorkspaceTab.mindmap => _buildWorkspaceMindmapTab(),
      _WorkspaceTab.chat => _buildWorkspaceChatTab(selected),
    };

    return Container(
      key: ValueKey('workspace-tab-${_workspaceTab.name}-${selected.id}'),
      decoration: BoxDecoration(
        color: const Color(0xFF0F131A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF323A46).withValues(alpha: 0.48),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 18 : 14),
        child: content,
      ),
    );
  }

  Widget _buildWorkspaceSummaryTab(RecordingModel selected) {
    final summaryText = _recordingsController.summary?.contentMd ??
        'Ainda sem resumo. Rode o processamento para gerar.';
    final showLiveControls = _isLiveRecording ||
        _isLiveRecordingBusy ||
        _pendingRecordedAudio != null ||
        _isUploadingRecordedAudio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Resumo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141922),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF3A4250).withValues(alpha: 0.48),
                width: 0.8,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppMarkdown(
                    data: summaryText,
                    dark: true,
                  ),
                  if (showLiveControls) ...<Widget>[
                    const SizedBox(height: 16),
                    _buildLiveRecordingSection(selected),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceTranscriptTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Transcricao com timestamps',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _buildTranscriptSection(fillAvailable: true),
        ),
      ],
    );
  }

  Widget _buildWorkspaceMindmapTab() {
    return SingleChildScrollView(
      child: _buildWorkspaceInfoBlock(
        title: 'Mapa mental',
        child: MindmapViewer(
          key: ValueKey(_recordingsController.mindmap?.id),
          artifact: _recordingsController.mindmap,
          transcript: _recordingsController.transcript,
          transcriptSegments: _recordingsController.transcriptSegments,
          emptyMessage:
              'Ainda sem mapa mental. Rode o processamento para gerar.',
        ),
      ),
    );
  }

  Widget _buildWorkspaceChatTab(RecordingModel selected) {
    return _buildChatSection(selected, fillAvailable: true);
  }

  Widget _buildWorkspaceInfoBlock({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF3A4250).withValues(alpha: 0.48),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildLiveRecordingSection(RecordingModel selected) {
    final alreadyRecorded = _liveRecordingAlreadyHasAudio(selected);
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
        : alreadyRecorded
            ? 'Esta gravacao ja tem audio enviado/processado. Para uma nova captura, crie outra gravacao.'
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
                          alreadyRecorded ||
                          _isLiveRecording ||
                          _isLiveRecordingBusy ||
                          _isUploadingRecordedAudio ||
                          _pendingRecordedAudio != null
                      ? null
                      : _startLiveRecording,
                  icon: const Icon(Icons.mic),
                  label: const Text('Iniciar gravacao'),
                  style: FilledButton.styleFrom(
                    backgroundColor: alreadyRecorded
                        ? const Color(0xFF7A5A00)
                        : const Color(0xFFB42318),
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
                  onPressed:
                      (_isLiveRecording || _pendingRecordedAudio != null) &&
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

  Widget _buildTranscriptSection({
    bool fillAvailable = false,
  }) {
    final transcript = _recordingsController.transcript;
    final segments = _recordingsController.transcriptSegments;

    if (transcript == null && segments.isEmpty) {
      return const Text(
        'Ainda sem transcricao. Rode o processamento para gerar.',
      );
    }

    if (segments.isEmpty) {
      return SingleChildScrollView(
        child: SelectableText(transcript?.fullText ?? ''),
      );
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
            if (fillAvailable)
              Expanded(
                child: _buildTranscriptSegmentsList(
                  segments: segments,
                  currentPositionMs: currentPositionMs,
                  canSync: canSync,
                ),
              )
            else
              _buildTranscriptSegmentsList(
                segments: segments,
                currentPositionMs: currentPositionMs,
                canSync: canSync,
                maxHeight: 420,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTranscriptSegmentsList({
    required List<TranscriptSegmentModel> segments,
    required int currentPositionMs,
    required bool canSync,
    double? maxHeight,
  }) {
    final list = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: ListView.separated(
        controller: _transcriptScrollController,
        padding: const EdgeInsets.all(12),
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
    );

    if (maxHeight == null) {
      return list;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: list,
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

  Widget _buildChatSection(
    RecordingModel selected, {
    bool fillAvailable = false,
  }) {
    final chatContainer = Container(
      width: double.infinity,
      height: fillAvailable ? null : 380,
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
                    return _buildChatBubble(_chatController.messages[index]);
                  },
                ),
    );

    final chatComposer = Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );

    if (fillAvailable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Chat da Gravacao',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar chat',
                onPressed: _chatController.isLoading ? null : _refreshChat,
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: chatContainer),
          if (_chatController.errorMessage != null &&
              _chatController.errorMessage!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _chatController.errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 12),
          chatComposer,
          const SizedBox(height: 8),
          Text(
            'Sessao: ${_chatController.session?.title ?? 'Chat principal'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6A717C),
                ),
          ),
        ],
      );
    }

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
          chatContainer,
          if (_chatController.errorMessage != null &&
              _chatController.errorMessage!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _chatController.errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 12),
          chatComposer,
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

  // ignore: unused_element
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

    return SelectableText(
      subtitle.toString(),
      style: const TextStyle(
        color: Color(0xFFE4E7EC),
        height: 1.55,
      ),
    );
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

enum _QuickCreateMode { liveRecording, uploadFile }

enum _RecordingAction { open, process, edit, delete }

enum _WorkspaceOverflowAction { edit, upload, refresh, delete }

enum _WorkspaceTab { summary, transcript, mindmap, chat }

class _QuickCreateChoice {
  const _QuickCreateChoice({
    required this.mode,
    required this.title,
  });

  final _QuickCreateMode mode;
  final String title;
}

class _RecordingGroup {
  const _RecordingGroup({
    required this.day,
    required this.items,
  });

  final DateTime day;
  final List<RecordingModel> items;
}

class _QuickCreateSheet extends StatefulWidget {
  const _QuickCreateSheet();

  @override
  State<_QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<_QuickCreateSheet> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _finish(_QuickCreateMode mode) {
    Navigator.of(context).pop(
      _QuickCreateChoice(
        mode: mode,
        title: _titleController.text.trim(),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF181D25),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF2A303B)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA4ADBA),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF7C8694),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        top: 24,
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF12161C),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF262B33)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 32,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF303743),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nova gravacao',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Escolha como voce quer capturar o conteudo. Se nao informar titulo, o app gera um automaticamente.',
              style: TextStyle(
                color: Color(0xFFA4ADBA),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Titulo da gravacao',
                labelStyle: const TextStyle(color: Color(0xFF8D98A7)),
                hintText: 'Ex.: Aula de microbiologia',
                hintStyle: const TextStyle(color: Color(0xFF5E6774)),
                filled: true,
                fillColor: const Color(0xFF171C23),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF2A313C)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF2A313C)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF5B7CFF)),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildOptionTile(
              icon: Icons.mic_rounded,
              iconColor: const Color(0xFFFF7758),
              title: 'Gravar direto',
              subtitle:
                  'Abre a gravacao ao vivo, com pausar, continuar e envio automatico no final.',
              onTap: () => _finish(_QuickCreateMode.liveRecording),
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.audio_file_rounded,
              iconColor: const Color(0xFF5B7CFF),
              title: 'Usar arquivo pronto',
              subtitle:
                  'Seleciona um audio ja gravado, envia para a VPS e processa automaticamente.',
              onTap: () => _finish(_QuickCreateMode.uploadFile),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );
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
