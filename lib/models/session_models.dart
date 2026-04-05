import 'dart:convert';

enum CoachingMode {
  interview,
  presentation,
  speech,
  informal,
  formal,
  tutorials
}

enum SessionOutcome { offer, advanced, rejected, unknown }

enum DetailFilter { overview, gestures, outcomes, all }

class FillerTimestamp {
  const FillerTimestamp({
    required this.word,
    required this.seconds,
    required this.transcriptIndex,
  });

  final String word;
  final double seconds;
  final int transcriptIndex;

  Map<String, dynamic> toJson() => {
        'word': word,
        'seconds': seconds,
        'transcriptIndex': transcriptIndex,
      };

  factory FillerTimestamp.fromJson(Map<String, dynamic> json) {
    return FillerTimestamp(
      word: json['word']?.toString() ?? '',
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      transcriptIndex: (json['transcriptIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

class SessionLog {
  const SessionLog({
    required this.mode,
    required this.score,
    required this.outcome,
    required this.timestamp,
  });

  final CoachingMode mode;
  final double score;
  final SessionOutcome outcome;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'score': score,
        'outcome': outcome.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SessionLog.fromJson(Map<String, dynamic> json) {
    return SessionLog(
      mode: _modeFromName(json['mode']?.toString()),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      outcome: _outcomeFromName(json['outcome']?.toString()),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SessionRecording {
  const SessionRecording({
    required this.url,
    required this.mode,
    required this.score,
    required this.createdAt,
    required this.transcript,
    required this.wordTimestampsSec,
    required this.fillerTimeline,
  });

  final String url;
  final CoachingMode mode;
  final double score;
  final DateTime createdAt;
  final String transcript;
  final List<double> wordTimestampsSec;
  final List<FillerTimestamp> fillerTimeline;
}

class SessionReport {
  const SessionReport({
    required this.mode,
    required this.createdAt,
    required this.overallScore,
    required this.contentScore,
    required this.paceLabel,
    required this.confidenceLabel,
    required this.wordCount,
    required this.wpm,
    required this.fillerCount,
    required this.fillerRate,
    required this.confidenceScore,
    required this.facePresence,
    required this.eyeContact,
    required this.headStability,
    required this.gestureRating,
    required this.gestureMoments,
    required this.visualMessage,
    required this.voiceFeedback,
    required this.contentFeedback,
    required this.fillerTimeline,
  });

  final CoachingMode mode;
  final DateTime createdAt;
  final double overallScore;
  final double contentScore;
  final String paceLabel;
  final String confidenceLabel;
  final int wordCount;
  final double wpm;
  final int fillerCount;
  final double fillerRate;
  final double confidenceScore;
  final double facePresence;
  final double eyeContact;
  final double headStability;
  final String gestureRating;
  final int gestureMoments;
  final String visualMessage;
  final List<String> voiceFeedback;
  final List<String> contentFeedback;
  final List<FillerTimestamp> fillerTimeline;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'createdAt': createdAt.toIso8601String(),
        'overallScore': overallScore,
        'contentScore': contentScore,
        'paceLabel': paceLabel,
        'confidenceLabel': confidenceLabel,
        'wordCount': wordCount,
        'wpm': wpm,
        'fillerCount': fillerCount,
        'fillerRate': fillerRate,
        'confidenceScore': confidenceScore,
        'facePresence': facePresence,
        'eyeContact': eyeContact,
        'headStability': headStability,
        'gestureRating': gestureRating,
        'gestureMoments': gestureMoments,
        'visualMessage': visualMessage,
        'voiceFeedback': voiceFeedback,
        'contentFeedback': contentFeedback,
        'fillerTimeline': fillerTimeline.map((item) => item.toJson()).toList(),
      };

  factory SessionReport.fromJson(Map<String, dynamic> json) {
    final fillerTimeline = (json['fillerTimeline'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
            (item) => FillerTimestamp.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    return SessionReport(
      mode: _modeFromName(json['mode']?.toString()),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0,
      contentScore: (json['contentScore'] as num?)?.toDouble() ?? 0,
      paceLabel: json['paceLabel']?.toString() ?? '',
      confidenceLabel: json['confidenceLabel']?.toString() ?? '',
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      wpm: (json['wpm'] as num?)?.toDouble() ?? 0,
      fillerCount: (json['fillerCount'] as num?)?.toInt() ?? 0,
      fillerRate: (json['fillerRate'] as num?)?.toDouble() ?? 0,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
      facePresence: (json['facePresence'] as num?)?.toDouble() ?? 0,
      eyeContact: (json['eyeContact'] as num?)?.toDouble() ?? 0,
      headStability: (json['headStability'] as num?)?.toDouble() ?? 0,
      gestureRating: json['gestureRating']?.toString() ?? '',
      gestureMoments: (json['gestureMoments'] as num?)?.toInt() ?? 0,
      visualMessage: json['visualMessage']?.toString() ?? '',
      voiceFeedback:
          (json['voiceFeedback'] as List<dynamic>? ?? []).cast<String>(),
      contentFeedback:
          (json['contentFeedback'] as List<dynamic>? ?? []).cast<String>(),
      fillerTimeline: fillerTimeline,
    );
  }
}

class PersistedSessionData {
  const PersistedSessionData({
    required this.logs,
    required this.reports,
  });

  final List<SessionLog> logs;
  final List<SessionReport> reports;
}

List<Map<String, dynamic>> decodeJsonList(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

CoachingMode _modeFromName(String? value) {
  return CoachingMode.values.firstWhere(
    (item) => item.name == value,
    orElse: () => CoachingMode.presentation,
  );
}

SessionOutcome _outcomeFromName(String? value) {
  return SessionOutcome.values.firstWhere(
    (item) => item.name == value,
    orElse: () => SessionOutcome.unknown,
  );
}
