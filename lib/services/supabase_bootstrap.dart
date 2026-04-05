import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBootstrap {
  static const String _url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;

    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
    );
  }

  static SupabaseClient? get client =>
      isConfigured ? Supabase.instance.client : null;
}
