abstract interface class AccessTokenProvider {
  Future<String> accessToken({bool forceRefresh = false});
}
