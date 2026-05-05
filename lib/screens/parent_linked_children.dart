import 'package:cloud_firestore/cloud_firestore.dart';

class ParentLinkedChild {
  final String childId;
  final String childName;
  final DocumentReference<Map<String, dynamic>> childRef;

  const ParentLinkedChild({
    required this.childId,
    required this.childName,
    required this.childRef,
  });
}

List<ParentLinkedChild> extractParentLinkedChildren(
  Map<String, dynamic> parentData,
) {
  final linkedChildren = <ParentLinkedChild>[];

  List<dynamic> asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return const <dynamic>[];
  }

  final refsRaw = parentData['childRefs'] ?? parentData['childrenRefs'];
  final idsRaw = parentData['childIds'];
  final namesRaw = parentData['childNames'];

  final refs = asList(refsRaw);
  final ids = asList(idsRaw);
  final names = asList(namesRaw);

  if (refs.isNotEmpty) {
    for (var index = 0; index < refs.length; index++) {
      final childRef = _toChildReference(refs[index]);
      if (childRef == null) {
        continue;
      }
      final childId = childRef.id.trim();
      if (childId.isEmpty) {
        continue;
      }
      final childName =
          (index < names.length ? names[index] : '').toString().trim();
      linkedChildren.add(
        ParentLinkedChild(
          childId: childId,
          childName: childName.isEmpty ? childId : childName,
          childRef: childRef,
        ),
      );
    }
  } else if (ids.isNotEmpty) {
    for (var index = 0; index < ids.length; index++) {
      final childId = (ids[index] ?? '').toString().trim();
      if (childId.isEmpty) {
        continue;
      }
      final childName =
          (index < names.length ? names[index] : '').toString().trim();
      linkedChildren.add(
        ParentLinkedChild(
          childId: childId,
          childName: childName.isEmpty ? childId : childName,
          childRef: FirebaseFirestore.instance.collection('children').doc(childId),
        ),
      );
    }
  }

  if (linkedChildren.isEmpty) {
    final legacyChildRef = _toChildReference(parentData['childRef']);
    if (legacyChildRef != null) {
      final legacyChildId = legacyChildRef.id.trim();
      if (legacyChildId.isNotEmpty) {
        final childName =
            (parentData['childName'] ?? legacyChildId).toString().trim();
        linkedChildren.add(
          ParentLinkedChild(
            childId: legacyChildId,
            childName: childName.isEmpty ? legacyChildId : childName,
            childRef: legacyChildRef,
          ),
        );
      }
    } else {
      final legacyChildId = (parentData['childId'] ?? '').toString().trim();
      if (legacyChildId.isNotEmpty) {
        final childName =
            (parentData['childName'] ?? legacyChildId).toString().trim();
        linkedChildren.add(
          ParentLinkedChild(
            childId: legacyChildId,
            childName: childName.isEmpty ? legacyChildId : childName,
            childRef: FirebaseFirestore.instance
                .collection('children')
                .doc(legacyChildId),
          ),
        );
      }
    }
  }

  final seenChildIds = <String>{};
  return linkedChildren.where((child) => seenChildIds.add(child.childId)).toList();
}

DocumentReference<Map<String, dynamic>>? _toChildReference(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is DocumentReference) {
    final normalizedPath = _normalizeDocumentPath(raw.path);
    if (normalizedPath.isEmpty) {
      return null;
    }
    return FirebaseFirestore.instance.doc(normalizedPath);
  }
  if (raw is String) {
    final normalizedPath = _normalizeDocumentPath(raw);
    if (normalizedPath.isEmpty) {
      return null;
    }
    return FirebaseFirestore.instance.doc(normalizedPath);
  }
  return null;
}

String _normalizeDocumentPath(String rawPath) {
  var path = rawPath.trim();
  if (path.isEmpty) {
    return '';
  }

  if (path.startsWith('/')) {
    path = path.substring(1);
  }

  const documentsMarker = '/documents/';
  final markerIndex = path.indexOf(documentsMarker);
  if (markerIndex >= 0) {
    path = path.substring(markerIndex + documentsMarker.length);
  }

  if (path.startsWith('documents/')) {
    path = path.substring('documents/'.length);
  }

  final childIndex = path.indexOf('children/');
  if (childIndex >= 0) {
    path = path.substring(childIndex);
  }

  return path;
}