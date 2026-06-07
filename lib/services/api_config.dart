import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const _keyGoogleCloud = 'gemini_api_key';
  static const _keyGroq = 'groq_api_key';
  static const _keyOpenAi = 'openai_api_key';
  static const _keyTenor = 'tenor_api_key';
  static const _keyFreesound = 'freesound_token';

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

  // ── Tenor key — optional, for meme GIF search (get a free key at tenor.com) ──
  static Future<String?> getTenorKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTenor);
  }

  static Future<void> saveTenorKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTenor, key.trim());
  }

  static Future<void> clearTenorKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTenor);
  }

  // ── Freesound token — optional, for meme/UI SFX search (free at freesound.org) ──
  static Future<String?> getFreesoundKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFreesound);
  }

  static Future<void> saveFreesoundKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFreesound, key.trim());
  }

  static Future<void> clearFreesoundKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFreesound);
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

}
