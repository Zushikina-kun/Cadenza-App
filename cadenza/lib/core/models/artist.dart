import 'package:flutter/foundation.dart';

/// Represents a derived artist record. Artists are populated via
/// INSERT OR IGNORE during scan passes, keyed on name uniqueness.
@immutable
class Artist {
  final int? id;
  final String name;

  const Artist({this.id, required this.name});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
      };

  factory Artist.fromMap(Map<String, dynamic> map) => Artist(
        id: map['id'] as int?,
        name: map['name'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artist && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Artist(id: $id, name: $name)';
}
