import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:math';

import '../database/cache/cache_controller.dart';

class MarkerIconWithAnchor {
  final Uint8List icon;
  final Offset anchor; // normalized [0..1] offset

  MarkerIconWithAnchor(this.icon, this.anchor);
}

enum MarkerLayout {
  vertical, // Image top, text bottom
  horizontal, // Image left, text right
  textOnly, // No image, just text
  imageOnly, // Only image, no text
}

enum TextFormat {
  simple,
  smartWrap,
  lhFormat,
  centered,
}

/// Cache key for marker identification
class MarkerCacheKey {
  final String text;
  final String? imageSource;
  final MarkerLayout layout;
  final TextFormat textFormat;
  final Size imageSize;
  final double fontSize;
  final Color textColor;
  final Color strokeColor;
  final double strokeWidth;
  final double spacing;
  final Offset? customAnchor;
  final bool maintainAspectRatio;
  final bool expandCanvasForRotation;

  MarkerCacheKey({
    required this.text,
    this.imageSource,
    required this.layout,
    required this.textFormat,
    required this.imageSize,
    required this.fontSize,
    required this.textColor,
    required this.strokeColor,
    required this.strokeWidth,
    required this.spacing,
    this.customAnchor,
    required this.maintainAspectRatio,
    required this.expandCanvasForRotation,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MarkerCacheKey &&
        other.text == text &&
        other.imageSource == imageSource &&
        other.layout == layout &&
        other.textFormat == textFormat &&
        other.imageSize == imageSize &&
        other.fontSize == fontSize &&
        other.textColor == textColor &&
        other.strokeColor == strokeColor &&
        other.strokeWidth == strokeWidth &&
        other.spacing == spacing &&
        other.customAnchor == customAnchor &&
        other.maintainAspectRatio == maintainAspectRatio &&
        other.expandCanvasForRotation == expandCanvasForRotation;
  }

  @override
  int get hashCode {
    return Object.hash(
      text,
      imageSource,
      layout,
      textFormat,
      imageSize,
      fontSize,
      textColor,
      strokeColor,
      strokeWidth,
      spacing,
      customAnchor,
      maintainAspectRatio,
      expandCanvasForRotation,
    );
  }
}

class UnifiedMarkerCreator {
  // Static cache to persist across instances
  static final Map<MarkerCacheKey, MarkerIconWithAnchor> _markerCache = {};

  // Cache statistics (optional, for debugging/monitoring)
  static int _cacheHits = 0;
  static int _cacheMisses = 0;

  /// Clear all cached markers
  static void clearCache() {
    _markerCache.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  /// Remove a specific marker from cache
  static void removeCachedMarker(MarkerCacheKey key) {
    _markerCache.remove(key);
  }

  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'size': _markerCache.length,
      'hits': _cacheHits,
      'misses': _cacheMisses,
      'hitRate': _cacheMisses > 0
          ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(2) + '%'
          : '0%',
    };
  }

  /// Creates a crisp marker that keeps the same *physical* size across devices.
  /// Results are cached automatically for faster subsequent access.
  /// imageSize is in logical dp (same units you'd expect for Flutter widgets).
  ///
  /// When [expandCanvasForRotation] is true, creates a larger canvas to allow
  /// proper rotation around the anchor point without clipping.
  Future<MarkerIconWithAnchor> createUnifiedMarker({
    required String text,
    String? imageSource,
    MarkerLayout layout = MarkerLayout.vertical,
    TextFormat textFormat = TextFormat.smartWrap,
    Size imageSize = const Size(35, 35), // logical dp
    double fontSize = 12.0, // logical sp
    Color textColor = Colors.black,
    Color strokeColor = const Color(0xfff8f9fa),
    double strokeWidth = 2.0, // logical
    double spacing = 0.0, // logical
    Offset? customAnchor, // normalized if provided
    bool maintainAspectRatio = true,
    bool expandCanvasForRotation = false,
    bool useCache = true, // New parameter to optionally disable cache
  }) async {
    // Create cache key
    final cacheKey = MarkerCacheKey(
      text: text,
      imageSource: imageSource,
      layout: layout,
      textFormat: textFormat,
      imageSize: imageSize,
      fontSize: fontSize,
      textColor: textColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      spacing: spacing,
      customAnchor: customAnchor,
      maintainAspectRatio: maintainAspectRatio,
      expandCanvasForRotation: expandCanvasForRotation,
    );

    // Check cache first
    if (useCache && _markerCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _markerCache[cacheKey]!;
    }

    _cacheMisses++;

    // Generate marker if not in cache
    final marker = await _generateMarker(
      text: text,
      imageSource: imageSource,
      layout: layout,
      textFormat: textFormat,
      imageSize: imageSize,
      fontSize: fontSize,
      textColor: textColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      spacing: spacing,
      customAnchor: customAnchor,
      maintainAspectRatio: maintainAspectRatio,
      expandCanvasForRotation: expandCanvasForRotation,
    );

    // Store in cache
    if (useCache) {
      _markerCache[cacheKey] = marker;
    }

    return marker;
  }

  /// Internal method that does the actual marker generation
  Future<MarkerIconWithAnchor> _generateMarker({
    required String text,
    String? imageSource,
    MarkerLayout layout = MarkerLayout.vertical,
    TextFormat textFormat = TextFormat.smartWrap,
    Size imageSize = const Size(35, 35), // logical dp
    double fontSize = 12.0, // logical sp
    Color textColor = Colors.black,
    Color strokeColor = const Color(0xfff8f9fa),
    double strokeWidth = 2.0, // logical
    double spacing = 0.0, // logical
    Offset? customAnchor, // normalized if provided
    bool maintainAspectRatio = true,
    bool expandCanvasForRotation = false,
  }) async {
    final double ratio = ui.window.devicePixelRatio; // device pixel ratio

    // Convert logical sizes to pixel sizes (so final PNG has pixel-perfect content)
    final double imageWidthPx = imageSize.width * ratio;
    final double imageHeightPx = imageSize.height * ratio;
    final double fontSizePx = fontSize * ratio;
    final double strokeWidthPx = strokeWidth * ratio;
    final double spacingPx = spacing * ratio;

    // Format text
    final String formattedText = formatText(text, textFormat);

    // Load & decode image at exact pixel size (if provided)
    ui.Image? markerImage;
    Size actualImageSizePx = Size(imageWidthPx, imageHeightPx);

    if (imageSource != null && imageSource.isNotEmpty) {
      try {
        Uint8List? bytes;
        if (imageSource.startsWith('http')) {
          final response = await CacheController().fetchWithCache(imageSource!);
           bytes = response;
        } else {
          final bd = await rootBundle.load(imageSource);
          bytes = bd.buffer.asUint8List();
        }

        if (bytes != null) {
          // Decode original to get aspect ratio
          final Completer<ui.Image> originalCompleter = Completer();
          ui.decodeImageFromList(
              bytes, (ui.Image img) => originalCompleter.complete(img));
          final ui.Image originalImage = await originalCompleter.future;
          if (maintainAspectRatio) {
            final double origAR = originalImage.width / originalImage.height;
            final double targetAR = imageWidthPx / imageHeightPx;
            if (origAR > targetAR) {
              // image is wider -> fit width
              actualImageSizePx = Size(imageWidthPx, imageWidthPx / origAR);
            } else {
              // image is taller or equal -> fit height
              actualImageSizePx = Size(imageHeightPx * origAR, imageHeightPx);
            }
          } else {
            actualImageSizePx = Size(imageWidthPx, imageHeightPx);
          }

          // instantiate codec at final pixel size (prevents later upscaling)
          final codec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: actualImageSizePx.width.toInt().clamp(1, 10000),
            targetHeight: actualImageSizePx.height.toInt().clamp(1, 10000),
          );
          final frame = await codec.getNextFrame();
          markerImage = frame.image;
        }
      } catch (e) {
        // keep markerImage null and fallback to text-only layout
        print('⚠️ image load failed: $e');
        markerImage = null;
      }
    }

    // If attempted image but failed -> fallback to textOnly (unless imageOnly requested)
    if (markerImage == null &&
        imageSource != null &&
        layout != MarkerLayout.imageOnly) {
      layout = MarkerLayout.textOnly;
    }
    if (layout == MarkerLayout.imageOnly && markerImage == null) {
      throw Exception('imageOnly requires a valid image source');
    }

    // Prepare text painters (measured in pixels)
    TextPainter? fillPainter;
    TextPainter? strokePainter;
    double textWidthPx = 0;
    double textHeightPx = 0;
    final double pillPaddingH = fontSizePx * 0.4;
    final double pillPaddingV = fontSizePx * 0.2;

    if (layout != MarkerLayout.imageOnly && formattedText.isNotEmpty) {
      final fillStyle = TextStyle(
        fontFamily: 'PT_Sans',
        fontSize: fontSizePx,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.0,
      );
      final strokeStyle = TextStyle(
        fontFamily: 'PT_Sans',
        fontSize: fontSizePx,
        fontWeight: FontWeight.w500,
        color: strokeColor,
        height: 1.0,
      );

      fillPainter = TextPainter(
        text: TextSpan(text: formattedText, style: fillStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      strokePainter = TextPainter(
        text: TextSpan(text: formattedText, style: strokeStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      // We must give a sufficiently large max width in pixels.
      // This ensures multi-line wrapping behaves like you'd expect.
      // Choose a generous maximum width in pixels (e.g., 300 dp * ratio)
      final double maxTextWidthPx = (300.0 * ratio);
      fillPainter.layout(minWidth: 0, maxWidth: maxTextWidthPx);
      strokePainter.layout(minWidth: 0, maxWidth: maxTextWidthPx);

      textWidthPx = fillPainter.width;
      textHeightPx = fillPainter.height;
    }

    // Compute canvas size in pixels depending on layout
    double? canvasWidthPx;
    double? canvasHeightPx;
    double imageX = 0, imageY = 0, textX = 0, textY = 0;

    // Calculate content size first (before expansion)
    double contentWidthPx;
    double contentHeightPx;

    switch (layout) {
      case MarkerLayout.horizontal:
        if (markerImage != null) {
          contentWidthPx = actualImageSizePx.width +
              spacingPx +
              (textWidthPx + pillPaddingH * 2) +  // ← pill padding
              strokeWidthPx * 2;
          contentHeightPx =
              max(actualImageSizePx.height, textHeightPx + pillPaddingV * 2) + // ← pill padding
                  strokeWidthPx * 2;
          canvasWidthPx = contentWidthPx;
          canvasHeightPx = contentHeightPx;
          imageX = strokeWidthPx;
          imageY = (canvasHeightPx - actualImageSizePx.height) / 2;
          textX = imageX + actualImageSizePx.width + spacingPx + pillPaddingH; // ← offset by pill padding
          textY = (canvasHeightPx - textHeightPx) / 2;
        } else {
          contentWidthPx = textWidthPx + pillPaddingH * 2 + strokeWidthPx * 2; // ← pill padding
          contentHeightPx = textHeightPx + pillPaddingV * 2 + strokeWidthPx * 2;
          canvasWidthPx = contentWidthPx;
          canvasHeightPx = contentHeightPx;
          textX = strokeWidthPx + pillPaddingH; // ← offset
          textY = strokeWidthPx + pillPaddingV;
        }
        break;

      case MarkerLayout.vertical:
        if (markerImage != null) {
          contentWidthPx =
              max(actualImageSizePx.width, textWidthPx + pillPaddingH * 2) + // ← pill padding
                  strokeWidthPx * 2;
          contentHeightPx = actualImageSizePx.height +
              spacingPx +
              (textHeightPx + pillPaddingV * 2) + // ← pill padding
              strokeWidthPx * 2;
          canvasWidthPx = contentWidthPx;
          canvasHeightPx = contentHeightPx;
          imageX = (canvasWidthPx - actualImageSizePx.width) / 2;
          imageY = strokeWidthPx;
          textX = (canvasWidthPx - textWidthPx) / 2; // text centered, pill drawn around it
          textY = imageY + actualImageSizePx.height + spacingPx + pillPaddingV; // ← offset
        } else {
          contentWidthPx = textWidthPx + pillPaddingH * 2 + strokeWidthPx * 2;
          contentHeightPx = textHeightPx + pillPaddingV * 2 + strokeWidthPx * 2;
          canvasWidthPx = contentWidthPx;
          canvasHeightPx = contentHeightPx;
          textX = strokeWidthPx + pillPaddingH;
          textY = strokeWidthPx + pillPaddingV;
        }
        break;

      case MarkerLayout.textOnly:
        contentWidthPx = textWidthPx + pillPaddingH * 2 + strokeWidthPx * 2;
        contentHeightPx = textHeightPx + pillPaddingV * 2 + strokeWidthPx * 2;
        canvasWidthPx = contentWidthPx;
        canvasHeightPx = contentHeightPx;
        textX = strokeWidthPx + pillPaddingH;
        textY = strokeWidthPx + pillPaddingV;
        break;

      case MarkerLayout.imageOnly:
      // unchanged
        break;
    }

    // Calculate initial anchor before expansion
    Offset initialAnchor;
    if (customAnchor != null) {
      initialAnchor = customAnchor;
    } else {
      // Default anchors depending on layout:
      if (markerImage == null) {
        // Center for text-only
        initialAnchor = Offset(0.5, 0.5);
      } else {
        switch (layout) {
          case MarkerLayout.horizontal:
          // center of image horizontally, bottom of canvas vertically
            final double ax = (imageX + actualImageSizePx.width / 2) / canvasWidthPx!;
            final double ay = (imageY + actualImageSizePx.height) / canvasHeightPx!;
            initialAnchor = Offset(ax.clamp(0.0, 1.0), ay.clamp(0.0, 1.0));
            break;
          case MarkerLayout.vertical:
          // center horizontally, bottom of image vertically (so marker tip aligns)
            final double ax2 = (imageX + actualImageSizePx.width / 2) / canvasWidthPx!;
            final double ay2 = (imageY + actualImageSizePx.height) / canvasHeightPx!;
            initialAnchor = Offset(ax2.clamp(0.0, 1.0), ay2.clamp(0.0, 1.0));
            break;
          case MarkerLayout.imageOnly:
            initialAnchor = Offset(0.5, 0.5);
            break;
          case MarkerLayout.textOnly:
            initialAnchor = Offset(0.5, 0.5);
            break;
        }
      }
    }

    // Expand canvas for rotation if requested
    double offsetX = 0;
    double offsetY = 0;
    Offset finalAnchor = initialAnchor;

    if (expandCanvasForRotation) {
      // Calculate the pivot point in pixels
      final double pivotX = canvasWidthPx! * initialAnchor.dx;
      final double pivotY = canvasHeightPx! * initialAnchor.dy;

      // Calculate maximum distance from pivot to any corner
      final corners = [
        Offset(0, 0),
        Offset(canvasWidthPx, 0),
        Offset(0, canvasHeightPx),
        Offset(canvasWidthPx, canvasHeightPx),
      ];

      double maxDistance = 0;
      for (final corner in corners) {
        final distance = sqrt(
            pow(corner.dx - pivotX, 2) + pow(corner.dy - pivotY, 2)
        );
        maxDistance = max(maxDistance, distance);
      }

      // New canvas should be a square that can contain the full rotation
      // Add some padding for safety (10%)
      final double expandedSize = maxDistance * 2 * 1.1;

      // Calculate new canvas dimensions
      final double expandedCanvasWidth = max(canvasWidthPx, expandedSize);
      final double expandedCanvasHeight = max(canvasHeightPx, expandedSize);

      // Calculate offset to center the original content with pivot at canvas center
      offsetX = (expandedCanvasWidth / 2) - pivotX;
      offsetY = (expandedCanvasHeight / 2) - pivotY;

      // Update drawing positions
      imageX += offsetX;
      imageY += offsetY;
      textX += offsetX;
      textY += offsetY;

      // Update canvas dimensions
      canvasWidthPx = expandedCanvasWidth;
      canvasHeightPx = expandedCanvasHeight;

      // Anchor is now at the center of the expanded canvas
      finalAnchor = Offset(0.5, 0.5);
    }

    // Ensure integer pixel dimensions at least 1
    final int canvasW = max(1, canvasWidthPx!.ceil());
    final int canvasH = max(1, canvasHeightPx!.ceil());

    // Draw into picture recorder (working in pixel units)
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Optional: Draw debug circle at pivot point (comment out in production)
    // if (expandCanvasForRotation) {
    //   final paint = Paint()
    //     ..color = Colors.red.withOpacity(0.5)
    //     ..style = PaintingStyle.fill;
    //   canvas.drawCircle(
    //     Offset(canvasWidthPx / 2, canvasHeightPx / 2),
    //     5 * ratio,
    //     paint,
    //   );
    // }

    // Draw image (if exists) with high quality
    if (markerImage != null) {
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high;
      canvas.drawImage(markerImage, Offset(imageX, imageY), paint);
    }

    // Draw text stroke then fill with improved quality
    if (fillPainter != null &&
        strokePainter != null &&
        layout != MarkerLayout.imageOnly) {
      final textOffset = Offset(textX, textY);

      // Draw pill background
        final double pillRadius = (textHeightPx + pillPaddingV * 1.2) / 2;

        final Rect pillRect = Rect.fromLTWH(
          textX - pillPaddingH,
          textY - pillPaddingV,
          textWidthPx + pillPaddingH * 2,
          textHeightPx + pillPaddingV * 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(pillRect, Radius.circular(pillRadius)),
          Paint()
            ..color = Colors.white
            ..isAntiAlias = true
            ..style = PaintingStyle.fill,
        );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, Radius.circular(pillRadius)),
        Paint()
          ..color = const Color(0xffcc1616) // your border color
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidthPx * 1, // or any fixed px value
      );

      fillPainter.paint(canvas, textOffset);
    }

    // Finish and convert to image at final pixel dimensions
    final ui.Image finalImage =
    await recorder.endRecording().toImage(canvasW, canvasH);
    final ByteData? pngBytesData =
    await finalImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytesData == null)
      throw Exception('Failed to encode marker image to PNG.');
    final Uint8List pngBytes = pngBytesData.buffer.asUint8List();

    return MarkerIconWithAnchor(pngBytes, finalAnchor);
  }

  String formatText(String text, TextFormat format) {
    switch (format) {
      case TextFormat.simple:
        return text;
      case TextFormat.centered:
        return text;
      case TextFormat.lhFormat:
        final lhRegex = RegExp(r'^(LH\s*\d+)\s*-\s*(.+)$');
        if (lhRegex.hasMatch(text)) {
          final match = lhRegex.firstMatch(text)!;
          return "${match.group(1)!}\n${match.group(2)!}";
        } else {
          final words = text.split(RegExp(r'\s+'));
          if (words.length >= 2) {
            return "${words[0]} ${words[1]}";
          }
          return words[0];
        }
      case TextFormat.smartWrap:
        final rawWords = text.trim().split(RegExp(r'\s+'));
        List<String> words = [];

        for (int i = 0; i < rawWords.length; i++) {
          // Case 1: already hyphenated like A-1 or Block-C
          if (rawWords[i].contains('-')) {
            words.add(rawWords[i]);
            continue;
          }

          // Case 2: spaced hyphen like A - B or Cabin - 1
          if (i + 2 < rawWords.length && rawWords[i + 1] == '-') {
            words.add('${rawWords[i]} - ${rawWords[i + 2]}');
            i += 2;
            continue;
          }

          words.add(rawWords[i]);
        }

        List<String> lines = [];
        int index = 0;
        bool isFirstWordNumber = words.isNotEmpty && RegExp(r'^\d+(/\d+)?$').hasMatch(words[0]);
        if (isFirstWordNumber) {
          lines.add(words[0]);
          index = 1;
        }
        int remainingCount = words.length - index;
        if (remainingCount == 2) {
          lines.add(words[index]);
          lines.add(words[index + 1]);
          index += 2;
        } else if (remainingCount % 2 == 1 && index < words.length) {
          lines.add(words[index]);
          index++;
        }
        while (index < words.length) {
          if (index + 1 < words.length) {
            String firstWord = words[index];
            String secondWord = words[index + 1];
            String pair = "$firstWord $secondWord";
            if (pair.length > 20) {
              lines.add(firstWord);
              index++;
            } else {
              lines.add(pair);
              index += 2;
            }
          } else {
            lines.add(words[index]);
            index++;
          }
        }
        List<String> finalLines = [];
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i];
          List<String> lineWords = line.split(' ');
          if (lineWords.last.length <= 2 && i + 1 < lines.length) {
            String shortWord = lineWords.last;
            String restOfLine = lineWords.sublist(0, lineWords.length - 1).join(' ');
            String nextLineWithShort = "$shortWord ${lines[i + 1]}";
            if (nextLineWithShort.length <= 20) {
              if (restOfLine.isNotEmpty) {
                finalLines.add(restOfLine);
              }
              lines[i + 1] = nextLineWithShort;
            } else {
              finalLines.add(line);
            }
          } else {
            finalLines.add(line);
          }
        }
        return finalLines.join("\n");
    }
  }
}