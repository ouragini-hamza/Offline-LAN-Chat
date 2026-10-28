import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';

class ChatDatabase {
  Future<Database>? _databaseFuture;

  Future<Database> get _db => _databaseFuture ??= _openDatabase();

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    return openDatabase(
      p.join(databasePath, 'locallink.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            peer_id TEXT NOT NULL,
            peer_name TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            is_outgoing INTEGER NOT NULL,
            delivery_status TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX messages_peer_time ON messages(peer_id, created_at)',
        );
      },
    );
  }

  Future<void> saveMessage(ChatMessage message) async {
    final database = await _db;
    await database.insert(
      'messages',
      message.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> saveIncomingMessage(ChatMessage message) async {
    final database = await _db;
    final existing = await database.query(
      'messages',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [message.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    await database.insert(
      'messages',
      message.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  Future<void> updateDeliveryStatus(String id, String status) async {
    final database = await _db;
    await database.update(
      'messages',
      {'delivery_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ChatMessage>> loadMessages(String peerId) async {
    final database = await _db;
    final rows = await database.query(
      'messages',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromDatabase).toList();
  }

  Future<List<ConversationPreview>> loadRecentConversations() async {
    final database = await _db;
    final rows = await database.rawQuery('''
      SELECT messages.peer_id,
             messages.peer_name,
             messages.body,
             messages.created_at,
             messages.is_outgoing
      FROM messages
      INNER JOIN (
        SELECT peer_id, MAX(created_at) AS latest
        FROM messages
        GROUP BY peer_id
      ) AS newest
        ON newest.peer_id = messages.peer_id
       AND newest.latest = messages.created_at
      ORDER BY messages.created_at DESC
    ''');
    return rows.map(ConversationPreview.fromDatabase).toList();
  }

  Future<void> close() async {
    final databaseFuture = _databaseFuture;
    if (databaseFuture != null) {
      await (await databaseFuture).close();
      _databaseFuture = null;
    }
  }
}
