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

  Exception _friendlyAuthException(
    Object error, {
    required bool signUp,
  }) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final normalized = raw.toLowerCase();

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
