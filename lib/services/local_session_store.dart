import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:avaixa/models/session_models.dart';

class LocalSessionStore {
  static const String _reportsKey = 'avaixa.saved_reports.v1';
  static const String _logsKey = 'avaixa.saved_logs.v1';

  Future<PersistedSessionData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedReports = prefs.getString(_reportsKey);
    final savedLogs = prefs.getString(_logsKey);

    final reports = savedReports == null
        ? <SessionReport>[]
        : decodeJsonList(savedReports).map(SessionReport.fromJson).toList();
    final logs = savedLogs == null
        ? <SessionLog>[]
        : decodeJsonList(savedLogs).map(SessionLog.fromJson).toList();

    return PersistedSessionData(logs: logs, reports: reports);
  }

  Future<void> saveReports(List<SessionReport> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reportsKey,
      jsonEncode(reports.map((report) => report.toJson()).toList()),
    );
  }

  Future<void> saveLogs(List<SessionLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _logsKey,
      jsonEncode(logs.map((log) => log.toJson()).toList()),
    );
  }
}
