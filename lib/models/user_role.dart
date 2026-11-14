/// User role classification for Amrita BLE Attendance Platform.
enum UserRole {
  student,
  faculty,
  admin;

  String get displayName {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.faculty:
        return 'Faculty';
      case UserRole.admin:
        return 'Administrator';
    }
  }

  String get firestoreKey {
    switch (this) {
      case UserRole.student:
        return 'student';
      case UserRole.faculty:
        return 'faculty';
      case UserRole.admin:
        return 'admin';
    }
  }

  /// Expected institutional email domain for each role
  String get expectedDomain {
    switch (this) {
      case UserRole.student:
        return '@ch.students.amrita.edu';
      case UserRole.faculty:
      case UserRole.admin:
        return '@ch.amrita.edu';
    }
  }

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase().trim()) {
      case 'student':
        return UserRole.student;
      case 'faculty':
        return UserRole.faculty;
      case 'admin':
      case 'administrator':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }
}
