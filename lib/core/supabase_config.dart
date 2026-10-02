import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://ydbaubclhthgvooimsct.supabase.co';
  static const String anonKey = 'sb_publishable_dSvXCiW0YM0DxqpjoZzdKw_j6xex1lj';
}

SupabaseClient get supabase => Supabase.instance.client;