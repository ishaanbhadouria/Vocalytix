import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'services/supabase_bootstrap.dart';
import 'screens/practice_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.initialize();
  runApp(const AvaixaApp());
}

class AvaixaApp extends StatelessWidget {
  const AvaixaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Avaixa',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF62A8FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111A33),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151F3E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF182447),
          selectedColor: const Color(0xFF2E78D1),
          secondarySelectedColor: const Color(0xFF2E78D1),
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const AvaixaAppShell(),
    );
  }
}

class AvaixaAppShell extends StatefulWidget {
  const AvaixaAppShell({super.key});

  @override
  State<AvaixaAppShell> createState() => _AvaixaAppShellState();
}

class _AvaixaAppShellState extends State<AvaixaAppShell> {
  bool _localPreviewUnlocked = false;
  bool _confirmationAcknowledged = false;

  bool get _hasConfirmationCallback {
    if (_confirmationAcknowledged) return false;

    final queryParams = Uri.base.queryParameters;
    if (queryParams['auth_callback'] == 'confirmed') return true;

    final fragment = Uri.base.fragment;
    if (fragment.isEmpty || !fragment.contains('=')) return false;

    try {
      final fragmentParams = Uri.splitQueryString(fragment);
      return fragmentParams['type'] == 'signup' ||
          fragmentParams['type'] == 'email';
    } catch (_) {
      return false;
    }
  }

  Exception _friendlyAuthException(
    Object error, {
    required bool signUp,
  }) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final normalized = raw.toLowerCase();

    if (!signUp &&
        (normalized.contains('email not confirmed') ||
            normalized.contains('email_not_confirmed'))) {
      return Exception(
        "Confirm your email before signing in. Check your inbox for Avaixa's confirmation message.",
      );
    }

    if (!signUp &&
        (normalized.contains('invalid login credentials') ||
            normalized.contains('invalid_credentials') ||
            normalized.contains('user not found') ||
            normalized.contains('email not found') ||
            normalized.contains('invalid email or password'))) {
      return Exception(
        "This account does not exist or the username/password is incorrect.",
      );
    }

    if (signUp &&
        (normalized.contains('user already registered') ||
            normalized.contains('already registered') ||
            normalized.contains('already been registered'))) {
      return Exception(
        "An account with this email already exists. Try signing in instead.",
      );
    }

    if (normalized.contains('<!doctype') ||
        normalized.contains('not valid json') ||
        normalized.contains("unexpected token '<'") ||
        normalized.contains('failed to decode error response')) {
      return Exception(
        "Create account isn't working yet because Avaixa can't reach the Supabase auth API correctly. Double-check the deployed SUPABASE_URL and make sure the app finished redeploying.",
      );
    }

    if (signUp) {
      return Exception("We couldn't create the account. Please try again.");
    }

    return Exception(
      "This account does not exist or the username/password is incorrect.",
    );
  }

  Future<void> _signIn({
    required String email,
    required String password,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw Exception(
        "Supabase auth is not configured in this environment yet.",
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        throw Exception("We couldn't sign you in. Please try again.");
      }
    } catch (error) {
      throw _friendlyAuthException(error, signUp: false);
    }
  }

  Future<void> _signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw Exception(
        "Supabase auth is not configured in this environment yet.",
      );
    }

    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: SupabaseBootstrap.emailRedirectTo,
        data: {
          "full_name": fullName,
        },
      );

      if (response.user == null) {
        throw Exception("We couldn't create the account. Please try again.");
      }
    } catch (error) {
      throw _friendlyAuthException(error, signUp: true);
    }
  }

  String _viewerLabelForUser(User user) {
    final fullName = user.userMetadata?["full_name"]?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email;

    return "Signed in";
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseBootstrap.isConfigured) {
      if (_localPreviewUnlocked) {
        return PracticeScreen(
          onExitToAuth: () async {
            setState(() {
              _localPreviewUnlocked = false;
            });
          },
          viewerLabel: "Local Preview",
        );
      }

      return AuthScreen(
        isSupabaseConfigured: false,
        onSignIn: _signIn,
        onSignUp: _signUp,
        onContinueLocalPreview: () {
          setState(() {
            _localPreviewUnlocked = true;
          });
        },
      );
    }

    final client = SupabaseBootstrap.client!;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        final user = session?.user;

        if (_hasConfirmationCallback && user != null) {
          return _ConfirmationCompleteScreen(
            onContinue: () async {
              setState(() {
                _confirmationAcknowledged = true;
              });
              await client.auth.signOut();
            },
          );
        }

        if (user == null) {
          return AuthScreen(
            isSupabaseConfigured: true,
            onSignIn: _signIn,
            onSignUp: _signUp,
          );
        }

        return PracticeScreen(
          viewerLabel: _viewerLabelForUser(user),
          onExitToAuth: () async {
            await client.auth.signOut();
          },
        );
      },
    );
  }
}

class _ConfirmationCompleteScreen extends StatefulWidget {
  const _ConfirmationCompleteScreen({
    required this.onContinue,
  });

  final Future<void> Function() onContinue;

  @override
  State<_ConfirmationCompleteScreen> createState() =>
      _ConfirmationCompleteScreenState();
}

class _ConfirmationCompleteScreenState
    extends State<_ConfirmationCompleteScreen> {
  bool _continuing = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 3), _continueToLogin);
  }

  Future<void> _continueToLogin() async {
    if (_continuing || !mounted) return;
    setState(() {
      _continuing = true;
    });
    await widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF08101F), Color(0xFF122249), Color(0xFF101A36)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: const Color(0xFF111A33).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66050A16),
                      blurRadius: 42,
                      offset: Offset(0, 28),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mark_email_read_rounded,
                      size: 58,
                      color: Color(0xFF7CC4FF),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Thank you!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Your account has been confirmed. Enjoy using Avaixa :)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 17,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _continuing ? null : _continueToLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF62A8FF),
                          foregroundColor: const Color(0xFF081120),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _continuing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text("Continue to sign in"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "We'll take you back to login automatically in a moment.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
