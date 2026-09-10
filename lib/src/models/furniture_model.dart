// lib/src/models/furniture_model.dart

class FurnitureModel {
  final String id;
  final String name;
  final String category;
  final double rotationY;
  final List<String> tags;
  final String description;
  final List<FurnitureShape> shapes;

  FurnitureModel({
    required this.id,
    required this.name,
    required this.category,
    required this.rotationY,
    required this.tags,
    required this.description,
    required this.shapes,
  });

  factory FurnitureModel.fromJson(Map<String, dynamic> json) {
    return FurnitureModel(
      id: json['_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      rotationY: (json['rotation_y'] as num?)?.toDouble() ?? 0.0,
      tags: List<String>.from(json['tags'] ?? []),
      description: json['description'] ?? '',
      shapes: (json['3d'] as List)
          .map((s) => FurnitureShape.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'category': category,
      'rotation_y': rotationY,
      'tags': tags,
      'description': description,
      '3d': shapes.map((s) => s.toJson()).toList(),
    };
  }
}

class FurnitureShape {
  final String shape;
  final String label;
  final double? w;
  final double? h;
  final double? d;
  final double? r;
  final double ox;
  final double oy;
  final double oz;
  final String color;
  final double roughness;
  final double metalness;
  final double? rx;
  final double? ry;
  final double? rz;

  /// Explicit footprint for a "polygon" shape: a list of [x, z] corner pairs
  /// in local metres, relative to the part centre. Null for box/cylinder/
  /// sphere parts, which derive their footprint from w/d or r instead.
  final List<List<double>>? points;

  FurnitureShape({
    required this.shape,
    required this.label,
    this.w,
    this.h,
    this.d,
    this.r,
    required this.ox,
    required this.oy,
    required this.oz,
    required this.color,
    required this.roughness,
    required this.metalness,
    this.rx,
    this.ry,
    this.rz,
    this.points,
  });

  factory FurnitureShape.fromJson(Map<String, dynamic> json) {
    return FurnitureShape(
      shape: json['shape'] as String,
      label: json['label'] as String,
      w: (json['w'] as num?)?.toDouble(),
      h: (json['h'] as num?)?.toDouble(),
      d: (json['d'] as num?)?.toDouble(),
      r: (json['r'] as num?)?.toDouble(),
      ox: (json['ox'] as num?)?.toDouble() ?? 0.0,
      oy: (json['oy'] as num?)?.toDouble() ?? 0.0,
      oz: (json['oz'] as num?)?.toDouble() ?? 0.0,
      color: json['color'] as String? ?? '#888888',
      roughness: (json['roughness'] as num?)?.toDouble() ?? 0.5,
      metalness: (json['metalness'] as num?)?.toDouble() ?? 0.0,
      rx: (json['rx'] as num?)?.toDouble(),
      ry: (json['ry'] as num?)?.toDouble(),
      rz: (json['rz'] as num?)?.toDouble(),
      points: (json['points'] as List?)
          ?.map((p) => (p as List)
              .map((n) => (n as num).toDouble())
              .toList())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shape': shape,
      'label': label,
      if (w != null) 'w': w,
      if (h != null) 'h': h,
      if (d != null) 'd': d,
      if (r != null) 'r': r,
      'ox': ox,
      'oy': oy,
      'oz': oz,
      'color': color,
      'roughness': roughness,
      'metalness': metalness,
      if (rx != null) 'rx': rx,
      if (ry != null) 'ry': ry,
      if (rz != null) 'rz': rz,
      if (points != null) 'points': points,
    };
  }
}
