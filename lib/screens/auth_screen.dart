import 'package:flutter/material.dart';

import '../widgets/avaixa_brand.dart';

enum AuthScreenMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.isSupabaseConfigured,
    required this.onSignIn,
    required this.onSignUp,
    this.onContinueLocalPreview,
  });

  final bool isSupabaseConfigured;
  final Future<void> Function({
    required String email,
    required String password,
  }) onSignIn;
  final Future<void> Function({
    required String email,
    required String password,
    required String fullName,
  }) onSignUp;
  final VoidCallback? onContinueLocalPreview;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  AuthScreenMode _mode = AuthScreenMode.signIn;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorText;
  String? _infoText;

  bool get _isSignUp => _mode == AuthScreenMode.signUp;

  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasNumber = RegExp(r'[0-9]');
  static final RegExp _hasSymbol = RegExp(r'[^A-Za-z0-9]');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errorText = null;
      _infoText = null;
    });

    try {
      if (_isSignUp) {
        await widget.onSignUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _fullNameController.text.trim(),
        );

        if (!mounted) return;
        setState(() {
          _mode = AuthScreenMode.signIn;
          _passwordController.clear();
          _confirmPasswordController.clear();
          _obscurePassword = true;
          _obscureConfirmPassword = true;
          _infoText =
              "Confirmation email sent. Check your inbox, confirm your email, and then sign in.";
        });
      } else {
        await widget.onSignIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } catch (error) {
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '');
        _infoText = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _setMode(AuthScreenMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _errorText = null;
      _infoText = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _obscurePassword = true;
      _obscureConfirmPassword = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final headline = _isSignUp
        ? "Build your personal speaking coach."
        : "Welcome back to your speaking lab.";
    final subtitle = _isSignUp
        ? "Create an account so Avaixa can learn your patterns, track progress, and keep feedback personal."
        : "Sign in to pick up your reps, replays, and AI coaching exactly where you left off.";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF090D1B), Color(0xFF121C3D), Color(0xFF1A1630)],
            stops: [0.05, 0.52, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 920;
                    final hero = _buildHero(headline, subtitle);
                    final authCard = _buildAuthCard();

                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          hero,
                          const SizedBox(height: 20),
                          authCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 11, child: hero),
                        const SizedBox(width: 28),
                        Expanded(flex: 9, child: authCard),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(String headline, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AvaixaBrandButton(compact: false),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Text(
            "Personalized AI speech coaching",
            style: TextStyle(
              color: Color(0xFFBFD9FF),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          headline,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 17,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            _isSignUp
                ? "Create an account so your replays, AI coaching, and speaking history stay tied to you."
                : "Sign in to jump back into your saved replays, coaching memory, and active progress.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF101834).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66050A16),
            blurRadius: 42,
            offset: Offset(0, 28),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AuthModeChip(
                  label: "Sign In",
                  active: !_isSignUp,
                  onTap: () => _setMode(AuthScreenMode.signIn),
                ),
                const SizedBox(width: 10),
                _AuthModeChip(
                  label: "Create Account",
                  active: _isSignUp,
                  onTap: () => _setMode(AuthScreenMode.signUp),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _isSignUp ? "Create your Avaixa account" : "Sign in to Avaixa",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.isSupabaseConfigured
                  ? (_isSignUp
                      ? "Use your email and a password to start saving personalized coaching."
                      : "Use the account you’ll keep your coaching history under.")
                  : "Supabase auth isn’t configured in this environment yet, so the cloud login is paused. You can still open the full product in local preview mode below.",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            if (_isSignUp) ...[
              _fieldLabel("Full name"),
              const SizedBox(height: 8),
              _AuthTextField(
                controller: _fullNameController,
                hintText: "Avaixa should call you...",
                enabled: widget.isSupabaseConfigured && !_submitting,
                validator: (value) {
                  if (!_isSignUp) return null;
                  if (value == null || value.trim().length < 2) {
                    return "Enter your name so we can personalize the account.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            _fieldLabel("Email"),
            const SizedBox(height: 8),
            _AuthTextField(
              controller: _emailController,
              hintText: "you@example.com",
              keyboardType: TextInputType.emailAddress,
              enabled: widget.isSupabaseConfigured && !_submitting,
              validator: (value) {
                final text = value?.trim() ?? "";
                if (text.isEmpty) {
                  return "Enter the email tied to your account.";
                }
                if (!text.contains("@") || !text.contains(".")) {
                  return "Use a valid email address.";
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _fieldLabel("Password"),
            const SizedBox(height: 8),
            _AuthTextField(
              controller: _passwordController,
              hintText: _isSignUp ? "Create a password" : "Enter your password",
              obscureText: _obscurePassword,
              enabled: widget.isSupabaseConfigured && !_submitting,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
              validator: (value) {
                final text = value ?? "";
                if (text.isEmpty) return "Enter your password.";
                if (_isSignUp) {
                  if (text.length < 8 ||
                      !_hasUppercase.hasMatch(text) ||
                      !_hasLowercase.hasMatch(text) ||
                      !_hasNumber.hasMatch(text) ||
                      !_hasSymbol.hasMatch(text)) {
                    return "Password does not meet the required requirements.";
                  }
                }
                return null;
              },
            ),
            if (_isSignUp) ...[
              const SizedBox(height: 10),
              Text(
                "Strong password hint: use 8+ characters with uppercase, lowercase, a number, and a symbol.",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel("Confirm password"),
              const SizedBox(height: 8),
              _AuthTextField(
                controller: _confirmPasswordController,
                hintText: "Re-enter your password",
                obscureText: _obscureConfirmPassword,
                enabled: widget.isSupabaseConfigured && !_submitting,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                validator: (value) {
                  if (!_isSignUp) return null;
                  final text = value ?? "";
                  if (text.isEmpty) {
                    return "Confirm your password.";
                  }
                  if (text != _passwordController.text) {
                    return "Passwords do not match yet.";
                  }
                  return null;
                },
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF441D24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x88FF7A8C)),
                ),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFFFCBD2)),
                ),
              ),
            ],
            if (_infoText != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF173253),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x8862A8FF)),
                ),
                child: Text(
                  _infoText!,
                  style: const TextStyle(color: Color(0xFFD3E7FF)),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isSupabaseConfigured && !_submitting
                    ? _submit
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF62A8FF),
                  foregroundColor: const Color(0xFF081120),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(_isSignUp ? "Create Account" : "Sign In"),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.onContinueLocalPreview != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _submitting ? null : widget.onContinueLocalPreview,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Text("Open Local Preview"),
                ),
              ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => _setMode(
                          _isSignUp
                              ? AuthScreenMode.signIn
                              : AuthScreenMode.signUp,
                        ),
                child: Text(
                  _isSignUp
                      ? "Already have an account? Sign in"
                      : "New here? Create an account",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AuthModeChip extends StatelessWidget {
  const _AuthModeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF62A8FF)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? const Color(0xFFB4D8FF)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF081120) : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.hintText,
    this.validator,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String?)? validator;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.36)),
        filled: true,
        fillColor: const Color(0xFF0E1530),
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFF62A8FF), width: 1.2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFFF7A8C), width: 1.2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFFF7A8C), width: 1.2),
        ),
      ),
    );
  }
}
