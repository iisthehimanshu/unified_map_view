package org.maplibre.maplibregl;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.Style;
import org.maplibre.android.style.layers.CustomLayer;
import org.maplibre.android.style.layers.Layer;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.List;

/**
 * Adds wall images: upright textured rectangles sharing one image, drawn by a native custom layer
 * (src/main/cpp/wall_image_layer.cpp).
 */
final class WallImageLayer {
  static {
    System.loadLibrary("maplibregl_wallimage");
  }

  // OpenGL ES 3.0 guarantees at least this texture size.
  private static final int MAX_TEXTURE_SIZE = 2048;

  private WallImageLayer() {}

  static void add(
      @NonNull MapLibreMap map,
      @NonNull Style style,
      @NonNull String id,
      @NonNull double[] walls,
      double opacity,
      boolean doubleSided,
      @NonNull byte[] encodedImage,
      @Nullable String belowLayerId) {
    if (walls.length < 6 || walls.length % 6 != 0) {
      throw new IllegalArgumentException("Walls must hold 6 values per wall");
    }
    BitmapFactory.Options options = new BitmapFactory.Options();
    options.inScaled = false;
    options.inPreferredConfig = Bitmap.Config.ARGB_8888;
    Bitmap bitmap = BitmapFactory.decodeByteArray(encodedImage, 0, encodedImage.length, options);
    if (bitmap == null) {
      throw new IllegalArgumentException("Could not decode the wall image");
    }
    bitmap = fitTexture(bitmap);

    // ARGB_8888 bitmaps are premultiplied and copy out as R, G, B, A bytes,
    // which is what the shader expects.
    ByteBuffer pixels =
        ByteBuffer.allocateDirect(bitmap.getByteCount()).order(ByteOrder.nativeOrder());
    bitmap.copyPixelsToBuffer(pixels);
    int width = bitmap.getWidth();
    int heightPx = bitmap.getHeight();
    bitmap.recycle();

    if (style.getLayer(id) != null) {
      style.removeLayer(id);
    }

    List<Layer> layers = style.getLayers();
    int layersAbove = 0;
    boolean insertBelow = false;
    if (belowLayerId != null) {
      for (int i = 0; i < layers.size(); i++) {
        if (belowLayerId.equals(layers.get(i).getId())) {
          layersAbove = layers.size() - i;
          insertBelow = true;
          break;
        }
      }
    }

    long host =
        nativeCreate(
            walls, opacity, doubleSided, pixels, width, heightPx, layers.size() + 1, layersAbove);
    if (host == 0) {
      throw new IllegalStateException("Could not create the wall image layer");
    }

    CustomLayer layer = new CustomLayer(id, host);
    if (insertBelow) {
      style.addLayerBelow(layer, belowLayerId);
    } else {
      style.addLayer(layer);
    }
    map.triggerRepaint();
  }

  static void remove(@NonNull MapLibreMap map, @NonNull Style style, @NonNull String id) {
    if (style.getLayer(id) != null) {
      style.removeLayer(id);
      map.triggerRepaint();
    }
  }

  private static Bitmap fitTexture(Bitmap bitmap) {
    int w = bitmap.getWidth();
    int h = bitmap.getHeight();
    boolean wrongConfig = bitmap.getConfig() != Bitmap.Config.ARGB_8888;
    if (w <= MAX_TEXTURE_SIZE && h <= MAX_TEXTURE_SIZE && !wrongConfig) {
      return bitmap;
    }
    float scale = Math.min(1f, (float) MAX_TEXTURE_SIZE / Math.max(w, h));
    int nw = Math.max(1, Math.round(w * scale));
    int nh = Math.max(1, Math.round(h * scale));
    Bitmap scaled = Bitmap.createScaledBitmap(bitmap, nw, nh, true);
    if (scaled.getConfig() != Bitmap.Config.ARGB_8888) {
      Bitmap converted = scaled.copy(Bitmap.Config.ARGB_8888, false);
      if (scaled != bitmap) scaled.recycle();
      scaled = converted;
    }
    if (scaled != bitmap) bitmap.recycle();
    return scaled;
  }

  /** walls: startLat, startLng, endLat, endLng, base, height for each wall. */
  private static native long nativeCreate(
      double[] walls,
      double opacity,
      boolean doubleSided,
      ByteBuffer rgba,
      int width,
      int heightPx,
      int layerCount,
      int layersAbove);
}
