import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const _keyGoogleCloud = 'gemini_api_key';
  static const _keyGroq = 'groq_api_key';
  static const _keyOpenAi = 'openai_api_key';

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGoogleCloud);
  }

  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGoogleCloud, key.trim());
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGoogleCloud);
  }

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  // ── Groq (Whisper) key — optional, used only for precise word timing ──
  static Future<String?> getGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGroq);
  }

  static Future<void> saveGroqKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGroq, key.trim());
  }

  static Future<void> clearGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGroq);
  }

  static Future<bool> hasGroqKey() async {
    final key = await getGroqKey();
    return key != null && key.isNotEmpty;
  }

  // ── OpenAI (Whisper) key — optional primary transcription engine ──
  static Future<String?> getOpenAiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenAi);
  }

  static Future<void> saveOpenAiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenAi, key.trim());
  }

  static Future<void> clearOpenAiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOpenAi);
  }

  static Future<bool> hasOpenAiKey() async {
    final key = await getOpenAiKey();
    return key != null && key.isNotEmpty;
  }

  // ── ElevenLabs API key ──
  static const _keyElevenLabs = 'elevenlabs_api_key';

  static Future<String?> getElevenLabsKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyElevenLabs);
  }

  static Future<void> saveElevenLabsKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyElevenLabs, key.trim());
  }

  static Future<void> clearElevenLabsKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyElevenLabs);
  }

  static Future<bool> hasElevenLabsKey() async {
    final key = await getElevenLabsKey();
    return key != null && key.isNotEmpty;
  }
}
