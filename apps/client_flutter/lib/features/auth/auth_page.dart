import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _registerMode = false;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Preencha e-mail e senha.');
      return;
    }

    try {
      if (_registerMode) {
        await widget.authController.register(
          email: email,
          password: password,
          name: name.isEmpty ? null : name,
        );
      } else {
        await widget.authController.login(email: email, password: password);
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Falha inesperada ao autenticar.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: Stack(
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
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 920;
                      if (!wide) {
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: _buildAuthPanel(),
                          ),
                        );
                      }

                      return Row(
                        children: <Widget>[
                          Expanded(child: _buildBrandPanel()),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 440,
                            child: _buildAuthPanel(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF10151D).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF252B34)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const <Widget>[
          Text(
            'AnotaAi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.8,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Transforme gravacoes em transcricao, resumo, mapa mental e chat em um unico workspace.',
            style: TextStyle(
              color: Color(0xFFA8B1BE),
              fontSize: 18,
              height: 1.6,
            ),
          ),
          SizedBox(height: 30),
          _AuthFeatureRow(
            icon: Icons.graphic_eq_rounded,
            title: 'Transcricao com timestamps',
            subtitle: 'Upload ou gravacao ao vivo no mesmo fluxo',
          ),
          SizedBox(height: 16),
          _AuthFeatureRow(
            icon: Icons.auto_awesome_rounded,
            title: 'Resumo e mapa mental',
            subtitle: 'Conteudo sintetizado para revisao rapida',
          ),
          SizedBox(height: 16),
          _AuthFeatureRow(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chat por gravacao',
            subtitle: 'Pergunte apenas sobre o contexto daquele audio',
          ),
        ],
      ),
    );
  }

  Widget _buildAuthPanel() {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final loading = widget.authController.isLoading;
        final modeLabel = _registerMode ? 'Criar conta' : 'Entrar';
        final apiBase = const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://localhost:8000/v1',
        );

        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF10151D).withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF252B34)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131A24),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF252B34)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _buildModeButton(
                          label: 'Entrar',
                          active: !_registerMode,
                          enabled: !loading,
                          onTap: () {
                            setState(() {
                              _registerMode = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildModeButton(
                          label: 'Criar conta',
                          active: _registerMode,
                          enabled: !loading,
                          onTap: () {
                            setState(() {
                              _registerMode = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _registerMode
                      ? 'Criar conta no AnotaAi'
                      : 'Bem-vindo de volta',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _registerMode
                      ? 'Use seu e-mail para iniciar seu workspace.'
                      : 'Entre para acessar suas gravacoes e chats.',
                  style: const TextStyle(
                    color: Color(0xFFA8B1BE),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A23),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF252B34)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.settings_ethernet_rounded,
                        color: Color(0xFF8EA1FF),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'API: $apiBase',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB3BBC7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_registerMode) ...<Widget>[
                  _buildInput(
                    controller: _nameController,
                    enabled: !loading,
                    label: 'Nome (opcional)',
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildInput(
                  controller: _emailController,
                  enabled: !loading,
                  label: 'E-mail',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _buildInput(
                  controller: _passwordController,
                  enabled: !loading,
                  label: 'Senha',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => loading ? null : _submit(),
                  suffixIcon: IconButton(
                    tooltip:
                        _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: loading
                        ? null
                        : () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF98A2B3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _submit,
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_registerMode
                            ? Icons.person_add_alt_1_rounded
                            : Icons.login_rounded),
                    label: Text(loading ? 'Processando...' : modeLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7CFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 17,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            setState(() {
                              _registerMode = !_registerMode;
                            });
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF9AA7FF),
                    ),
                    child: Text(
                      _registerMode
                          ? 'Ja tem conta? Entrar'
                          : 'Ainda nao tem conta? Criar conta',
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

  Widget _buildModeButton({
    required String label,
    required bool active,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: <Color>[
                    Color(0xFF8A79FF),
                    Color(0xFF5B7CFF),
                  ],
                )
              : null,
          color: active ? null : const Color(0xFF141A23),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFF93A4FF).withValues(alpha: 0.8)
                : const Color(0xFF252B34),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required bool enabled,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Color(0xFFF3F6FB)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8E97A6)),
        prefixIcon: Icon(icon, color: const Color(0xFF8EA1FF)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF141922),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2A313D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2A313D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF4A65F6)),
        ),
      ),
    );
  }
}

class _AuthFeatureRow extends StatelessWidget {
  const _AuthFeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF141A23),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF252B34)),
          ),
          child: Icon(icon, color: const Color(0xFF8EA1FF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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
      ],
    );
  }
}
