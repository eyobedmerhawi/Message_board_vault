import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BoardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _messages =>
      _firestore.collection('messages');

  // Read messages and receive live updates.
  Stream<QuerySnapshot<Map<String, dynamic>>> getMessages() {
    return _messages.orderBy('createdAt', descending: true).snapshots();
  }

  // Create a new message.
  Future<void> createMessage(String text) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You must be signed in to post.');
    }

    final message = text.trim();

    if (message.isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    // Get the user's name from their Firestore profile.
    final profile = await _firestore.collection('users').doc(user.uid).get();

    if (!profile.exists) {
      throw Exception('User profile was not found.');
    }

    final data = profile.data()!;
    final firstName = (data['firstName'] as String).trim();
    final lastName = (data['lastName'] as String).trim();
    final authorName = '$firstName $lastName'.trim();

    await _messages.add({
      'text': message,
      'authorUid': user.uid,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    });
  }

  // Edit an existing message.
  Future<void> updateMessage(String messageId, String newText) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You must be signed in to edit.');
    }

    final text = newText.trim();

    if (text.isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    await _messages.doc(messageId).update({
      'text': text,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete an existing message.
  Future<void> deleteMessage(String messageId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You must be signed in to delete.');
    }

    await _messages.doc(messageId).delete();
  }
}
