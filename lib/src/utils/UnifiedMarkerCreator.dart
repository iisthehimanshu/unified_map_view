import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:unified_map_view/src/config.dart';
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
  final bool expandCanvasForRotation;
  final FontWeight fontWeight;
  final bool showPillBorder;
  final bool pillShadow;
  final Color pillColor;
  final double? pillCornerRadius;

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
    required this.expandCanvasForRotation,
    required this.fontWeight,
    required this.showPillBorder,
    required this.pillShadow,
    required this.pillColor,
    this.pillCornerRadius,
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
        other.expandCanvasForRotation == expandCanvasForRotation &&
        other.fontWeight == fontWeight &&
        other.showPillBorder == showPillBorder &&
        other.pillShadow == pillShadow &&
        other.pillColor == pillColor &&
        other.pillCornerRadius == pillCornerRadius;
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
      expandCanvasForRotation,
      fontWeight,
      showPillBorder,
      pillShadow,
      pillColor,
      pillCornerRadius,
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
    Uint8List? imageBytes, // pre-fetched (and optionally pre-resized) source photo bytes; skips the internal fetch when provided
    MarkerLayout layout = MarkerLayout.vertical,
    TextFormat textFormat = TextFormat.smartWrap,
    Size imageSize = const Size(35, 35), // logical dp
    double fontSize = 12.0, // logical sp
    Color textColor = Colors.black,
    Color strokeColor = const Color(0xfff8f9fa),
    double strokeWidth = 2.0, // logical
    double spacing = 0.0, // logical
    Offset? customAnchor, // normalized if provided
    bool expandCanvasForRotation = false,
    FontWeight fontWeight = FontWeight.w500,
    bool showPillBorder = true,
    bool pillShadow = false,
    Color pillColor = Colors.white,
    double? pillCornerRadius, // logical dp; null → default stadium radius
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
      expandCanvasForRotation: expandCanvasForRotation,
      fontWeight: fontWeight,
      showPillBorder: showPillBorder,
      pillShadow: pillShadow,
      pillColor: pillColor,
      pillCornerRadius: pillCornerRadius,
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
      imageBytes: imageBytes,
      layout: layout,
      textFormat: textFormat,
      imageSize: imageSize,
      fontSize: fontSize,
      textColor: textColor,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      spacing: spacing,
      customAnchor: customAnchor,
      expandCanvasForRotation: expandCanvasForRotation,
      fontWeight: fontWeight,
      showPillBorder: showPillBorder,
      pillShadow: pillShadow,
      pillColor: pillColor,
      pillCornerRadius: pillCornerRadius,
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
    Uint8List? imageBytes,
    MarkerLayout layout = MarkerLayout.vertical,
    TextFormat textFormat = TextFormat.smartWrap,
    Size imageSize = const Size(35, 35), // logical dp
    double fontSize = 12.0, // logical sp
    Color textColor = Colors.black,
    Color strokeColor = const Color(0xfff8f9fa),
    double strokeWidth = 2.0, // logical
    double spacing = 0.0, // logical
    Offset? customAnchor, // normalized if provided
    bool expandCanvasForRotation = false,
    FontWeight fontWeight = FontWeight.w500,
    bool showPillBorder = true,
    bool pillShadow = false,
    Color pillColor = Colors.white,
    double? pillCornerRadius, // logical dp; null → default stadium radius
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

    if (imageBytes != null || (imageSource != null && imageSource.isNotEmpty)) {
      try {
        Uint8List? bytes = imageBytes;
        if (bytes == null) {
          if (imageSource!.startsWith('http')) {
            final response = await CacheController().fetchWithCache(imageSource);
            bytes = response;
          } else {
            final bd = await rootBundle.load(imageSource);
            bytes = bd.buffer.asUint8List();
          }
        }

        if (bytes != null) {
          // Decode original to get its natural dimensions
          final Completer<ui.Image> originalCompleter = Completer();
          ui.decodeImageFromList(
              bytes, (ui.Image img) => originalCompleter.complete(img));
          final ui.Image originalImage = await originalCompleter.future;

          // Fit within imageSize while preserving aspect ratio (BoxFit.contain)
          final double origW = originalImage.width.toDouble();
          final double origH = originalImage.height.toDouble();
          final double scale = min(imageWidthPx / origW, imageHeightPx / origH);
          actualImageSizePx = Size(origW * scale, origH * scale);

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

    // Prepare text painter (measured in pixels)
    TextPainter? fillPainter;
    double textWidthPx = 0;
    double textHeightPx = 0;
    final double pillPaddingH = fontSizePx * 0.9;
    final double pillPaddingV = fontSizePx * 0.2;

    if (layout != MarkerLayout.imageOnly && formattedText.isNotEmpty) {
      final fillStyle = TextStyle(
        fontFamily: 'PT_Sans',
        fontSize: fontSizePx,
        fontWeight: fontWeight,
        color: textColor,
        height: 1.0,
      );

      fillPainter = TextPainter(
        text: TextSpan(text: formattedText, style: fillStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      // We must give a sufficiently large max width in pixels.
      // This ensures multi-line wrapping behaves like you'd expect.
      // Choose a generous maximum width in pixels (e.g., 300 dp * ratio)
      final double maxTextWidthPx = (300.0 * ratio);
      fillPainter.layout(minWidth: 0, maxWidth: maxTextWidthPx);

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

      // canvas.drawRect(
      //   Rect.fromLTWH(imageX, imageY, actualImageSizePx.width, actualImageSizePx.height),
      //   Paint()
      //     ..color = Colors.red
      //     ..style = PaintingStyle.stroke
      //     ..strokeWidth = strokeWidthPx
      //     ..isAntiAlias = true,
      // );
    }

    // Draw pill + text with improved quality
    if (fillPainter != null && layout != MarkerLayout.imageOnly) {
      final textOffset = Offset(textX, textY);

      // Draw pill background
      final double pillRadius = pillCornerRadius != null
          ? pillCornerRadius * ratio
          : (textHeightPx + pillPaddingV * 1.2) / 2;

      final Rect pillRect = Rect.fromLTWH(
        textX - pillPaddingH,
        textY - pillPaddingV,
        textWidthPx + pillPaddingH * 2,
        textHeightPx + pillPaddingV * 2,
      );
      final RRect pillRRect =
          RRect.fromRectAndRadius(pillRect, Radius.circular(pillRadius));

      // Soft drop shadow beneath the card (gallery-style pill).
      if (pillShadow) {
        canvas.drawRRect(
          pillRRect.shift(Offset(0, 1.5 * ratio)),
          Paint()
            ..color = const Color(0x33000000)
            ..isAntiAlias = true
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * ratio),
        );
      }

      canvas.drawRRect(
        pillRRect,
        Paint()
          ..color = pillColor
          ..isAntiAlias = true
          ..style = PaintingStyle.fill,
      );

      if (showPillBorder) {
        canvas.drawRRect(
          pillRRect,
          Paint()
            ..color = Colors.black // your border color
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidthPx * 0.8, // or any fixed px value
        );
      }

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

  /// Separate cache for museum POI markers so their keys never collide with the
  /// pill-style [_markerCache] entries.
  static final Map<String, MarkerIconWithAnchor> _poiCache = {};

  /// Renders a museum "POI" marker as a single baked PNG:
  ///   [ photo card with white frame ]
  ///            \ /            (downward tail)
  ///             •             (location dot — the anchor point)
  ///           Title           (bold, white-haloed, smart-wrapped)
  ///
  /// The canvas is padded so the dot sits at the exact geometric centre, and the
  /// returned anchor is (0.5, 0.5). This lets the MapLibre custom-render layer
  /// (which only supports the "center"/"bottom" keyword anchors) place the dot
  /// precisely on the coordinate at every zoom. Title text is baked in, matching
  /// how the existing custom-rendering markers work.
  Future<MarkerIconWithAnchor> createMuseumPoiMarker({
    required String text,
    String? imageSource,
    Uint8List? imageBytes, // pre-fetched source photo bytes; skips the internal fetch when provided
    Size cardSize = const Size(90, 76), // logical dp — outer white card
    double frame = 5.0, // logical — white border thickness
    double cornerRadius = 16.0,
    double tailHeight = 12.0,
    double tailWidth = 20.0,
    double gapTailToDot = 5.0,
    double dotOuterRadius = 8.0,
    double dotInnerRadius = 4.5,
    double gapDotToText = 7.0,
    double fontSize = 15.0,
    Color textColor = const Color(0xFF1A1A1A),
    Color haloColor = const Color(0xFFFFFFFF),
    double haloWidth = 3.0,
    Color dotColor = const Color(0xFF8B1D1D),
    bool selected = false,
    Color selectedColor = const Color(0xFFCD084A),
    bool useCache = true,
  }) async {
    final String cacheKey =
        '$text|$imageSource|${cardSize.width}x${cardSize.height}|$fontSize|$selected';
    if (useCache && _poiCache.containsKey(cacheKey)) {
      return _poiCache[cacheKey]!;
    }

    // When selected, the card/tail frame, the dot core, and the title text all
    // switch to the highlight colour.
    final Color frameColor =
        selected ? selectedColor : const Color(0xFFFFFFFF);
    final Color effectiveDotColor = selected ? selectedColor : dotColor;
    final Color effectiveTextColor = selected ? selectedColor : textColor;

    final double ratio = ui.window.devicePixelRatio;

    // Logical → pixel
    final double cardW = cardSize.width * ratio;
    final double cardH = cardSize.height * ratio;
    final double framePx = frame * ratio;
    final double cornerPx = cornerRadius * ratio;
    final double tailHPx = tailHeight * ratio;
    final double tailWPx = tailWidth * ratio;
    final double gapTailDotPx = gapTailToDot * ratio;
    final double dotOuterPx = dotOuterRadius * ratio;
    final double dotInnerPx = dotInnerRadius * ratio;
    final double gapDotTextPx = gapDotToText * ratio;
    final double fontSizePx = fontSize * ratio;
    final double haloPx = haloWidth * ratio;

    // ── Title text painters (real outline via foreground stroke paint) ────────
    final String formattedText = formatText(text, TextFormat.smartWrap);
    TextPainter? fillPainter;
    TextPainter? strokePainter;
    double textW = 0, textH = 0;

    if (formattedText.isNotEmpty) {
      strokePainter = TextPainter(
        text: TextSpan(
          text: formattedText,
          style: TextStyle(
            fontFamily: 'PT_Sans',
            fontSize: fontSizePx,
            fontWeight: FontWeight.w700,
            height: 1.05,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = haloPx
              ..strokeJoin = StrokeJoin.round
              ..color = haloColor,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 300.0 * ratio);

      fillPainter = TextPainter(
        text: TextSpan(
          text: formattedText,
          style: TextStyle(
            fontFamily: 'PT_Sans',
            fontSize: fontSizePx,
            fontWeight: FontWeight.w700,
            height: 1.05,
            color: effectiveTextColor,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 300.0 * ratio);

      textW = fillPainter.width;
      textH = fillPainter.height;
    }

    // ── Vertical geometry, centred on the dot ─────────────────────────────────
    // Distance from dot-centre up to the top of the canvas, and down to bottom.
    final double aboveDot =
        cardH + tailHPx + gapTailDotPx + dotOuterPx;
    final double belowDot =
        dotOuterPx + (textH > 0 ? gapDotTextPx + textH : 0);
    final double halfMax = max(aboveDot, belowDot);

    final double canvasHf = halfMax * 2;
    final double canvasWf = max(cardW, textW) + haloPx * 2;

    final int canvasW = max(1, canvasWf.ceil());
    final int canvasH = max(1, canvasHf.ceil());

    final double centerX = canvasWf / 2;
    final double dotCenterY = halfMax;

    final double cardX = centerX - cardW / 2;
    final double cardTop = dotCenterY - aboveDot;
    final double cardBottom = cardTop + cardH;

    // ── Draw ──────────────────────────────────────────────────────────────────
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final cardRect = Rect.fromLTWH(cardX, cardTop, cardW, cardH);
    final cardRRect =
        RRect.fromRectAndRadius(cardRect, Radius.circular(cornerPx));

    // Tail path (rounded triangle) pointing down toward the dot.
    final tailPath = Path()
      ..moveTo(centerX - tailWPx / 2, cardBottom - 1)
      ..lineTo(centerX + tailWPx / 2, cardBottom - 1)
      ..lineTo(centerX, cardBottom + tailHPx)
      ..close();

    // Soft drop shadow for the card + tail.
    final shadowPaint = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * ratio);
    canvas.drawRRect(cardRRect.shift(Offset(0, 1.5 * ratio)), shadowPaint);
    canvas.drawPath(tailPath.shift(Offset(0, 1.5 * ratio)), shadowPaint);

    final framePaint = Paint()
      ..color = frameColor
      ..isAntiAlias = true;
    canvas.drawPath(tailPath, framePaint);
    canvas.drawRRect(cardRRect, framePaint);

    // Photo, cover-fit inside the inner (framed) rounded rect.
    final innerRect = Rect.fromLTWH(
      cardX + framePx,
      cardTop + framePx,
      cardW - framePx * 2,
      cardH - framePx * 2,
    );
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      Radius.circular(max(0, cornerPx - framePx * 0.6)),
    );

    ui.Image? photo;
    if (imageBytes != null || (imageSource != null && imageSource.isNotEmpty)) {
      try {
        Uint8List? bytes = imageBytes;
        if (bytes == null) {
          if (imageSource!.startsWith('http')) {
            bytes = await CacheController().fetchWithCache(imageSource);
          } else {
            final bd = await rootBundle.load(imageSource);
            bytes = bd.buffer.asUint8List();
          }
        }
        if (bytes != null) {
          final completer = Completer<ui.Image>();
          ui.decodeImageFromList(bytes, (img) => completer.complete(img));
          photo = await completer.future;
        }
      } catch (e) {
        print('⚠️ POI image load failed: $e');
        photo = null;
      }
    }

    canvas.save();
    canvas.clipRRect(innerRRect);
    if (photo != null) {
      final double imgW = photo.width.toDouble();
      final double imgH = photo.height.toDouble();
      // BoxFit.cover: scale up so the photo fills the box, crop the overflow.
      final double scale = max(innerRect.width / imgW, innerRect.height / imgH);
      final double srcW = innerRect.width / scale;
      final double srcH = innerRect.height / scale;
      final Rect srcRect = Rect.fromLTWH(
        (imgW - srcW) / 2,
        (imgH - srcH) / 2,
        srcW,
        srcH,
      );
      canvas.drawImageRect(
        photo,
        srcRect,
        innerRect,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawRect(innerRect, Paint()..color = const Color(0xFFE0E0E0));
    }
    canvas.restore();

    // Location dot (white ring + coloured core).
    canvas.drawCircle(
      Offset(centerX, dotCenterY),
      dotOuterPx,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      Offset(centerX, dotCenterY),
      dotInnerPx,
      Paint()
        ..color = effectiveDotColor
        ..isAntiAlias = true,
    );

    // Title text, centred below the dot.
    if (fillPainter != null && strokePainter != null) {
      final double textTop = dotCenterY + dotOuterPx + gapDotTextPx;
      final double textX = centerX - textW / 2;
      strokePainter.paint(canvas, Offset(textX, textTop));
      fillPainter.paint(canvas, Offset(textX, textTop));
    }

    final ui.Image finalImage =
        await recorder.endRecording().toImage(canvasW, canvasH);
    final ByteData? pngData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) {
      throw Exception('Failed to encode museum POI marker to PNG.');
    }

    final result = MarkerIconWithAnchor(
      pngData.buffer.asUint8List(),
      const Offset(0.5, 0.5),
    );
    if (useCache) _poiCache[cacheKey] = result;
    return result;
  }

  /// Path-stop marker: a circle carrying [text] (the stop number).
  ///  • Non-museum: white ring + blue core + white number.
  ///  • Museum: plain white circle + dark-maroon (#550005) number, and when
  ///    [stopName] is provided it is drawn as a label below the circle.
  ///
  /// The circle is kept at the vertical centre of the canvas (extra transparent
  /// padding is added above to balance the label below) so the priority layer's
  /// default "center" anchor still lands the circle on the coordinate.
  Future<Uint8List> createStopMarkerIcon(
    String text, {
    bool museum = false,
    String stopName = "",
  }) async {
    const double diameter = 60;
    const double radius = 30;
    const double labelGap = 8; // circle → label
    const Color museumColor = Color(0xFF550005);
    final bool hasLabel = museum && stopName.trim().isNotEmpty;

    // Number shown inside the circle.
    final numberPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: museum ? museumColor : Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Stop-name label (museum only), dark maroon with a white halo for contrast.
    TextPainter? labelFill;
    TextPainter? labelHalo;
    double labelW = 0, labelH = 0;
    if (hasLabel) {
      labelHalo = TextPainter(
        text: TextSpan(
          text: stopName,
          style: TextStyle(
            fontFamily: 'PT_Sans',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 160);

      labelFill = TextPainter(
        text: TextSpan(
          text: stopName,
          style: const TextStyle(
            fontFamily: 'PT_Sans',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: museumColor,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 160);

      labelW = labelFill.width;
      labelH = labelFill.height;
    }

    // Symmetric canvas so the circle centre is the canvas centre.
    final double belowHalf =
        hasLabel ? radius + labelGap + labelH : radius;
    final double halfHeight = max(radius, belowHalf);
    final double canvasW = max(diameter, labelW);
    final double canvasH = halfHeight * 2;
    final double centerX = canvasW / 2;
    final double centerY = halfHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White outer circle (both themes).
    canvas.drawCircle(
      Offset(centerX, centerY),
      radius,
      Paint()
        ..color = Colors.white
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );

    // Blue inner circle — omitted in the museum theme (outer circle only).
    if (!museum) {
      canvas.drawCircle(
        Offset(centerX, centerY),
        24,
        Paint()
          ..color = Colors.blue
          ..isAntiAlias = true
          ..style = PaintingStyle.fill,
      );
    }

    // Stop number, centred in the circle.
    numberPainter.paint(
      canvas,
      Offset(
        centerX - numberPainter.width / 2,
        centerY - numberPainter.height / 2,
      ),
    );

    // Stop name, centred below the circle (museum only).
    if (hasLabel) {
      final double labelTop = centerY + radius + labelGap;
      final double labelX = centerX - labelW / 2;
      labelHalo!.paint(canvas, Offset(labelX, labelTop));
      labelFill!.paint(canvas, Offset(labelX, labelTop));
    }

    final image = await recorder
        .endRecording()
        .toImage(canvasW.ceil(), canvasH.ceil());

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}