import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  final String id;
  final String code;
  final String title;
  final String room;
  final List<String> facultyIds;

  const Course({
    required this.id,
    required this.code,
    required this.title,
    required this.room,
    required this.facultyIds,
  });

  factory Course.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawFaculty = data['facultyIds'];
    List<String> faculty = [];
    if (rawFaculty is List) {
      faculty = rawFaculty.map((e) => e.toString()).toList();
    }

    return Course(
      id: doc.id,
      code: data['code'] as String? ?? doc.id,
      title: data['title'] as String? ?? 'Untitled Course',
      room: data['room'] as String? ?? 'TBA',
      facultyIds: faculty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'title': title,
      'room': room,
      'facultyIds': facultyIds,
    };
  }
}
