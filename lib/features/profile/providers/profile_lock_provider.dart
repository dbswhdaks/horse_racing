import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/profile_lock_constants.dart';

/// 프로필 화면 잠금 상태 — true 이면 잠금이 해제되어 모든 정보를 볼 수 있다.
class ProfileLockNotifier extends StateNotifier<bool> {
  ProfileLockNotifier() : super(false) {
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(ProfileLockConstants.storageKey) ?? false;
      if (saved) state = true;
    } catch (_) {
      // 저장소 접근 실패 시 잠금 상태 유지
    }
  }

  /// 비밀번호가 일치하면 해제 상태를 저장하고 true 반환.
  Future<bool> unlock(String password) async {
    if (password.trim() != ProfileLockConstants.profilePassword) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileLockConstants.storageKey, true);
    } catch (_) {
      // 저장소 실패해도 메모리 상태는 true 로 유지
    }
    state = true;
    return true;
  }

  Future<void> lock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileLockConstants.storageKey, false);
    } catch (_) {}
    state = false;
  }
}

final profileLockProvider =
    StateNotifierProvider<ProfileLockNotifier, bool>((ref) {
  return ProfileLockNotifier();
});
