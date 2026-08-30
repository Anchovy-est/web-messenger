import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../services/api_client.dart';

class SearchRepository {
  SearchRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Matches the backend: partial match on username, exact match on
  /// email (see backend/src/models/user.model.js `searchUsers`).
  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await _apiClient.dio.get(
        '/users/search',
        queryParameters: {'q': query},
      );
      final users = response.data['users'] as List;
      return users.cast<Map<String, dynamic>>().map(User.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
