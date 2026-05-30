import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class WavChunk {
  final String path;
  final double startTime;
  final double duration;

  WavChunk({
    required this.path,
    required this.startTime,
    required this.duration,
  });
}

class WavChunker {
  /// Splits a WAV file into smaller chunks of [chunkDurationSeconds].
  /// Returns a list of [WavChunk] containing the path and start time of each chunk.
  static Future<List<WavChunk>> splitWav(String inputPath, {double chunkDurationSeconds = 15.0}) async {
    final file = File(inputPath);
    if (!file.existsSync()) {
      throw Exception('WAV file not found: $inputPath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 44) {
      throw Exception('Invalid WAV file (too small).');
    }

    final byteData = ByteData.sublistView(bytes);

    // Read header details
    final numChannels = byteData.getUint16(22, Endian.little);
    final sampleRate = byteData.getUint32(24, Endian.little);
    final bitsPerSample = byteData.getUint16(34, Endian.little);

    final bytesPerSample = numChannels * (bitsPerSample ~/ 8);
    final bytesPerSecond = sampleRate * bytesPerSample;

    // Find the 'data' chunk
    int dataOffset = 12; // Start after 'WAVE'
    while (dataOffset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
      final chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset += 8; // Move past 'data' and size
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    if (dataOffset >= bytes.length) {
      throw Exception('WAV data chunk not found.');
    }

    final rawData = bytes.sublist(dataOffset);
    
    // Calculate chunk size
    int bytesPerChunk = (chunkDurationSeconds * bytesPerSecond).toInt();
    bytesPerChunk -= (bytesPerChunk % bytesPerSample); // Align to sample boundary

    final tempDir = await getTemporaryDirectory();
    final baseName = DateTime.now().millisecondsSinceEpoch.toString();
    
    final chunks = <WavChunk>[];
    int offset = 0;
    int chunkIndex = 0;

    while (offset < rawData.length) {
      final end = (offset + bytesPerChunk < rawData.length) ? offset + bytesPerChunk : rawData.length;
      final chunkData = rawData.sublist(offset, end);
      
      final chunkWavPath = '${tempDir.path}/chunk_${baseName}_$chunkIndex.wav';
      
      // Build new 44-byte WAV header for the chunk
      final header = _buildWavHeader(chunkData.length, numChannels, sampleRate, bitsPerSample);
      
      final chunkFile = File(chunkWavPath);
      final writer = chunkFile.openSync(mode: FileMode.write);
      writer.writeFromSync(header);
      writer.writeFromSync(chunkData);
      writer.closeSync();

      final actualDuration = chunkData.length / bytesPerSecond;
      final startTime = offset / bytesPerSecond;

      chunks.add(WavChunk(
        path: chunkWavPath,
        startTime: startTime,
        duration: actualDuration,
      ));

      offset = end;
      chunkIndex++;
    }

    return chunks;
  }

  static Uint8List _buildWavHeader(int dataLength, int channels, int sampleRate, int bitsPerSample) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    
    final header = Uint8List(44);
    final bd = ByteData.view(header.buffer);
    
    // "RIFF"
    header[0] = 0x52; header[1] = 0x49; header[2] = 0x46; header[3] = 0x46;
    bd.setUint32(4, 36 + dataLength, Endian.little);
    
    // "WAVE"
    header[8] = 0x57; header[9] = 0x41; header[10] = 0x56; header[11] = 0x45;
    
    // "fmt "
    header[12] = 0x66; header[13] = 0x6D; header[14] = 0x74; header[15] = 0x20;
    bd.setUint32(16, 16, Endian.little); // Subchunk1Size
    bd.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    
    // "data"
    header[36] = 0x64; header[37] = 0x61; header[38] = 0x74; header[39] = 0x61;
    bd.setUint32(40, dataLength, Endian.little);
    
    return header;
  }
}
