import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart'; // Required for Colors
import 'package:http/http.dart' as http;

/// A helper class to upload videos to YouTube using resumable upload.
class YouTubeUploader {
  final String accessToken;
  final String selectedChannelId;

  YouTubeUploader(this.accessToken, {required this.selectedChannelId});
  static const String _uploadInitiationUrl =
      'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status';
  static const int _chunkSize = 1024 * 1024 * 5; // 5 MB chunks
  static const int _maxRetries = 5;
  // final String selectedChannelId; 

  /// Uploads a video file to YouTube using a resumable upload session.
  ///
  /// [file]: The video file to upload.
  /// [accessToken]: The OAuth 2.0 access token.
  /// [title]: The title of the video.
  /// [description]: The description of the video.
  /// [onProgress]: A callback that receives upload progress as a 0-1 double.
  ///
  /// Returns the uploaded YouTube video ID.
  static Future<String> uploadVideo({
    required File file,
    // required String accessToken,
    // required String selectedChannelId,
    required String title,
    String description = '',
    required Function(double) onProgress,
  }) async {
    final totalSize = await file.length();

    // Step 1: Initiate the resumable upload session
    final initRes = await http.post(
      Uri.parse(_uploadInitiationUrl),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'video/*',
        'X-Upload-Content-Length': totalSize.toString(),
      },
      body: jsonEncode({
        'snippet': {
          'title': title,
          'description': description,
          'channelId': selectedChannelId
        },
        'status': {
          'privacyStatus': 'private',
        },
      }),
    );

    if (initRes.statusCode != 200) {
      Fluttertoast.showToast(
        msg: "Failed to initiate upload: ${initRes.body}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      throw Exception('Failed to initiate upload: ${initRes.body}');
    }

    final uploadUrl = initRes.headers['location'];
    if (uploadUrl == null) {
      Fluttertoast.showToast(
        msg: "Upload session URL not returned.",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      throw Exception('Upload session URL not returned');
    }

    final stream = file.openRead();
    int offset = 0;

    await for (final chunk in stream.transform(StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        for (int i = 0; i < data.length; i += _chunkSize) {
          final end = (i + _chunkSize < data.length) ? i + _chunkSize : data.length;
          sink.add(data.sublist(i, end));
        }
      },
    ))) {
      int retries = 0;
      bool uploaded = false;

      while (!uploaded && retries < _maxRetries) {
        final chunkLength = chunk.length;
        final rangeHeader = 'bytes $offset-${offset + chunkLength - 1}/$totalSize';

        try {
          final uploadRes = await http.put(
            Uri.parse(uploadUrl),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Length': chunkLength.toString(),
              'Content-Type': 'video/*',
              'Content-Range': rangeHeader,
            },
            body: chunk,
          );

          if (uploadRes.statusCode == 200 || uploadRes.statusCode == 201) {
            final resBody = jsonDecode(uploadRes.body);
            return resBody['id'];
          } else if (uploadRes.statusCode == 308) {
            offset += chunkLength;
            onProgress(offset / totalSize);
            uploaded = true;
          } else {
            throw HttpException(
              'Unexpected status code: ${uploadRes.statusCode}',
              uri: Uri.parse(uploadUrl),
            );
          }
        } catch (e) {
          retries++;
          if (retries >= _maxRetries) {
            Fluttertoast.showToast(
              msg: "Upload failed: $e",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
            rethrow;
          }
          await Future.delayed(Duration(seconds: 2 * retries));
        }
      }
    }

    Fluttertoast.showToast(
      msg: "Upload failed after maximum retries.",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
    throw Exception('Upload failed after maximum retries');
  }
}
