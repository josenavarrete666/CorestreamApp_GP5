import '../data/api_client.dart';
import '../models/api_models.dart';

class ApiAuthService {
  ApiAuthService(this.client);
  final ApiClient client;

  Future<ApiProfile> profile({bool passwordRequired = false}) async {
    return ApiProfile.fromJson(await client.request('/api/auth/me'), passwordRequired: passwordRequired);
  }

  Future<ApiProfile> login(String email, String password) async {
    final token = await client.login(email, password);
    return profile(passwordRequired: token.mustChangePassword);
  }

  Future<ApiProfile> restore() async {
    client.beginSession();
    final token = await client.refresh();
    return profile(passwordRequired: token.mustChangePassword);
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await client.request('/api/auth/change-password', method: 'POST',
        body: {'old_password': oldPassword, 'new_password': newPassword});
  }

  Future<bool> logout() => client.logout();
}
