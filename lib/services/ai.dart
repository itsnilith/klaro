import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/state.dart';

/// One streaming turn: deltas arrive as they are produced.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ChatTurn {
  ChatTurn({required this.role, required this.content});
  final String role;
  final String content;
}

class AiClient {
  AiClient();

  /// Streams an OpenAI-compatible chat completion.
  Future<void> streamChat({
    required AiProvider provider,
    required List<ChatTurn> messages,
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(Object error) onError,
    bool Function()? cancelled,
    double? temperature,
    bool applyGlobalInstructions = true,
  }) async {
    final client = http.Client();
    try {
      final globalInst = AppState.i.aiGlobalInstructions.trim();
      final effectiveMessages = <ChatTurn>[];
      if (applyGlobalInstructions && globalInst.isNotEmpty) {
        if (messages.isNotEmpty && messages.first.role == 'system') {
          effectiveMessages.add(ChatTurn(
            role: 'system',
            content: '$globalInst\n\n${messages.first.content}',
          ));
          effectiveMessages.addAll(messages.skip(1));
        } else {
          effectiveMessages.add(ChatTurn(role: 'system', content: globalInst));
          effectiveMessages.addAll(messages);
        }
      } else {
        effectiveMessages.addAll(messages);
      }
      final uri = provider.kind == 'ollama'
          ? Uri.parse('${_trim(provider.baseUrl)}/api/chat')
          : Uri.parse('${_trim(provider.baseUrl)}/chat/completions');
      final body = provider.kind == 'ollama'
          ? {
              'model': provider.model,
              'messages': effectiveMessages.map((m) => {'role': m.role, 'content': m.content}).toList(),
              'stream': true,
              'options': {'temperature': temperature ?? provider.temperature},
            }
          : {
              'model': provider.model,
              'messages': effectiveMessages.map((m) => {'role': m.role, 'content': m.content}).toList(),
              'stream': true,
              'temperature': temperature ?? provider.temperature,
            };
      final req = http.Request('POST', uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          if (provider.apiKey.isNotEmpty) 'Authorization': 'Bearer ${provider.apiKey}',
        })
        ..body = jsonEncode(body);
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) {
        final text = await res.stream.bytesToString();
        throw AiException('Provider returned ${res.statusCode}: ${_short(text)}');
      }
      final buffer = StringBuffer();
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        if (cancelled?.call() ?? false) break;
        buffer.write(chunk);
        var idx = buffer.toString().indexOf('\n');
        var pending = buffer.toString();
        while (idx >= 0) {
          final line = pending.substring(0, idx).trim();
          pending = pending.substring(idx + 1);
          if (line.isEmpty) {
            idx = pending.indexOf('\n');
            continue;
          }
          if (provider.kind == 'ollama') {
            try {
              final obj = jsonDecode(line);
              final piece = obj['message']?['content'] as String? ?? '';
              if (piece.isNotEmpty) onDelta(piece);
              if (obj['done'] == true) {
                onDone();
                return;
              }
            } catch (_) {}
          } else {
            final data = line.startsWith('data:') ? line.substring(5).trim() : line;
            if (data == '[DONE]') {
              onDone();
              return;
            }
            try {
              final obj = jsonDecode(data);
              final piece = obj['choices']?[0]?['delta']?['content'] as String? ?? '';
              if (piece.isNotEmpty) onDelta(piece);
            } catch (_) {}
          }
          idx = pending.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(pending);
      }
      onDone();
    } on TimeoutException {
      onError(AiException('The provider did not respond in time.'));
    } catch (e) {
      onError(e is AiException ? e : AiException(e.toString()));
    } finally {
      client.close();
    }
  }

  Future<List<String>> listModels(AiProvider provider) async {
    final client = http.Client();
    try {
      final uri = provider.kind == 'ollama'
          ? Uri.parse('${_trim(provider.baseUrl)}/api/tags')
          : Uri.parse('${_trim(provider.baseUrl)}/models');
      final res = await client.get(uri, headers: {
        if (provider.apiKey.isNotEmpty) 'Authorization': 'Bearer ${provider.apiKey}',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400) {
        throw AiException('The provider answered ${res.statusCode}.');
      }
      final obj = jsonDecode(res.body);
      if (provider.kind == 'ollama') {
        return (obj['models'] as List? ?? [])
            .map((m) => m['name'] as String)
            .toList();
      }
      return (obj['data'] as List? ?? [])
          .map((m) => m['id'] as String)
          .toList();
    } finally {
      client.close();
    }
  }

  Future<List<double>?> embed(AiProvider provider, String text) async {
    if (provider.embeddingModel == null || provider.embeddingModel!.isEmpty) return null;
    final client = http.Client();
    try {
      final uri = provider.kind == 'ollama'
          ? Uri.parse('${_trim(provider.baseUrl)}/api/embed')
          : Uri.parse('${_trim(provider.baseUrl)}/embeddings');
      final body = provider.kind == 'ollama'
          ? {'model': provider.embeddingModel, 'input': text}
          : {'model': provider.embeddingModel, 'input': text};
      final res = await client
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                if (provider.apiKey.isNotEmpty) 'Authorization': 'Bearer ${provider.apiKey}',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode >= 400) return null;
      final obj = jsonDecode(res.body);
      if (provider.kind == 'ollama') {
        final list = obj['embeddings'] as List?;
        if (list == null || list.isEmpty) return null;
        return (list.first as List).map((e) => (e as num).toDouble()).toList();
      }
      final list = obj['data'] as List?;
      if (list == null || list.isEmpty) return null;
      return ((list.first as Map)['embedding'] as List).map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Pulls a model through the Ollama API, reporting progress from 0 to 1.
  Future<void> pullOllamaModel({
    required String baseUrl,
    required String model,
    required void Function(double? progress, String status) onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('${_trim(baseUrl)}/api/pull'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'model': model, 'stream': true});
      final res = await client.send(req);
      if (res.statusCode >= 400) {
        throw AiException('Ollama answered ${res.statusCode}.');
      }
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        for (final line in const LineSplitter().convert(chunk)) {
          if (line.trim().isEmpty) continue;
          try {
            final obj = jsonDecode(line);
            final total = obj['total'] as num?;
            final completed = obj['completed'] as num?;
            final status = obj['status'] as String? ?? '';
            onProgress(
              (total != null && completed != null && total > 0) ? completed / total : null,
              status,
            );
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<bool> ping(AiProvider provider) async {
    final client = http.Client();
    try {
      final uri = provider.kind == 'ollama'
          ? Uri.parse('${_trim(provider.baseUrl)}/api/tags')
          : Uri.parse('${_trim(provider.baseUrl)}/models');
      final res = await client.get(uri, headers: {
        if (provider.apiKey.isNotEmpty) 'Authorization': 'Bearer ${provider.apiKey}',
      }).timeout(const Duration(seconds: 6));
      return res.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static String _trim(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  static String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

/// Suggests a provider configuration from hardware and local services.
class AiSetup {
  static Future<Map<String, Object?>> detect() async {
    final totalRamGb = _totalRamGb();
    final hasOllama = await _portOpen('127.0.0.1', 11434);
    final models = <String>[];
    if (hasOllama) {
      try {
        final client = http.Client();
        final res = await client
            .get(Uri.parse('http://127.0.0.1:11434/api/tags'))
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final obj = jsonDecode(res.body);
          for (final m in (obj['models'] as List? ?? [])) {
            models.add(m['name'] as String);
          }
        }
        client.close();
      } catch (_) {}
    }
    final recommendation = (totalRamGb ?? 8) >= 30
        ? 'qwen3:14b'
        : (totalRamGb ?? 8) >= 15
            ? 'qwen3:8b'
            : (totalRamGb ?? 8) >= 7
                ? 'qwen3:4b'
                : 'qwen3:1.7b';
    return {
      'ram_gb': totalRamGb,
      'ollama': hasOllama,
      'models': models,
      'recommended': recommendation,
    };
  }

  static double? _totalRamGb() {
    if (!Platform.isWindows) return null;
    try {
      final r = Process.runSync('wmic', ['ComputerSystem', 'get', 'TotalPhysicalMemory', '/value']);
      final m = RegExp(r'TotalPhysicalMemory=(\d+)').firstMatch(r.stdout.toString());
      if (m != null) return int.parse(m.group(1)!) / (1024 * 1024 * 1024);
    } catch (_) {}
    return null;
  }

  static Future<bool> _portOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 700));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}