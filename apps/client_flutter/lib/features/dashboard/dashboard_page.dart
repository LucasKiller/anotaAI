import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/job_model.dart';
import '../../shared/models/recording_model.dart';
import '../../shared/widgets/content_section.dart';
import '../recordings/recordings_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _newRecordingController = TextEditingController();
  late final RecordingsController _recordingsController;

  @override
  void initState() {
    super.initState();
    _recordingsController = RecordingsController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  @override
  void dispose() {
    _newRecordingController.dispose();
    _recordingsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final token = widget.authController.accessToken;
    if (token == null) {
      return;
    }

    try {
      await _recordingsController.bootstrap(accessToken: token);
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
      await _recordingsController.createRecording(accessToken: token, title: title);
      _newRecordingController.clear();
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
      await _recordingsController.selectRecording(accessToken: token, recordingId: recording.id);
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
      await _recordingsController.startProcessing(accessToken: token, recordingId: selected.id);
      _showMessage('Pipeline de processamento iniciado.');
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
      );
      _showMessage('Audio enviado com sucesso.');
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
      await _recordingsController.reloadDetails(accessToken: token, recordingId: selected.id);
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _logout() async {
    await widget.authController.logout();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _recordingsController,
      builder: (context, _) {
        final selected = _recordingsController.selected;
        final width = MediaQuery.of(context).size.width;
        final narrow = width < 980;

        return Scaffold(
          appBar: AppBar(
            title: const Text('AnotaAi Dashboard'),
            actions: <Widget>[
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(widget.authController.currentUser?.email ?? ''),
                ),
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
                onPressed: _recordingsController.isListLoading ? null : _createRecording,
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
                            await _recordingsController.refreshRecordings(accessToken: token);
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
                      ? const Center(child: Text('Nenhuma gravacao criada ainda.'))
                      : ListView.builder(
                          itemCount: recordings.length,
                          itemBuilder: (context, index) {
                            final recording = recordings[index];
                            final selected = _recordingsController.selected?.id == recording.id;
                            return Card(
                              color: selected ? const Color(0xFFE2F2EE) : null,
                              child: ListTile(
                                selected: selected,
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
                              Text(selected.title, style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  Chip(label: Text('Status: ${selected.status}')),
                                  Chip(label: Text('Fonte: ${selected.sourceType}')),
                                  if (selected.language != null) Chip(label: Text('Idioma: ${selected.language}')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Criado em ${_formatDate(selected.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: <Widget>[
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
                        )
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

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }
}
