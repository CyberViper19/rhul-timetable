import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'flutter_timetable_model.dart';
import 'flutter_timetable_scraper.dart';
import 'app_theme_config.dart';
import 'main.dart' show themeNotifier;

bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isIOS => !kIsWeb && Platform.isIOS;

/// Universal Hardware-Backed Secure Storage Engine.
/// Automatically handles Android Keystore (AES-256 GCM) on Android,
/// Apple Keychain / Secure Enclave on iOS, and Web Storage on Web.
class SecureCredentialStorage {
  static const String _keyUsername = "encrypted_rhul_username";
  static const String _keyPassword = "encrypted_rhul_password";
  static const String _keyKeepLoggedIn = "rhul_keep_logged_in";

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Saves student credentials into platform secure storage
  Future<void> saveStudentCredentials({
    required String username,
    required String password,
    bool keepLoggedIn = true,
  }) async {
    if (keepLoggedIn) {
      await _secureStorage.write(key: _keyUsername, value: username.trim());
      await _secureStorage.write(key: _keyPassword, value: password.trim());
      await _secureStorage.write(key: _keyKeepLoggedIn, value: "true");
    } else {
      await wipeCredentials();
    }
  }

  /// Retrieves student credentials from platform secure storage
  Future<StudentCredentials?> getStudentCredentials() async {
    try {
      final u = await _secureStorage.read(key: _keyUsername);
      final p = await _secureStorage.read(key: _keyPassword);

      if (u != null && p != null && u.isNotEmpty && p.isNotEmpty) {
        return StudentCredentials(username: u, password: p);
      }
    } catch (_) {}
    return null;
  }

  /// Wipes the encrypted vault upon logout
  Future<void> wipeCredentials() async {
    try {
      await _secureStorage.delete(key: _keyUsername);
      await _secureStorage.delete(key: _keyPassword);
      await _secureStorage.delete(key: _keyKeepLoggedIn);
    } catch (_) {}
  }
}

class StudentCredentials {
  final String username;
  final String password;

  StudentCredentials({required this.username, required this.password});
}

/// Helper utility for detecting host OS and platform security engine details
class PlatformSecurityInfo {
  static String get storageEngineName {
    if (kIsWeb) {
      return "Web Secure Encrypted Storage";
    } else if (isAndroid) {
      return "Android Keystore";
    } else if (isIOS) {
      return "Apple Keychain / Secure Enclave";
    } else if (!kIsWeb && Platform.isMacOS) {
      return "macOS Keychain";
    } else if (!kIsWeb && Platform.isWindows) {
      return "Windows Credential Manager";
    } else {
      return "Hardware Secure Storage";
    }
  }

  static String get securityBadgeSubtitle {
    if (kIsWeb) {
      return "🔒 Protected by Web Browser Encrypted Storage";
    } else if (isAndroid) {
      return "🔒 Protected by Android Keystore (AES-256 GCM Hardware Vault)";
    } else if (isIOS) {
      return "🔒 Protected by Apple Keychain / Secure Enclave";
    } else {
      return "🔒 Protected by Hardware-Backed Encrypted Storage";
    }
  }

  static IconData get platformSecurityIcon {
    if (isIOS || (!kIsWeb && Platform.isMacOS)) {
      return CupertinoIcons.lock_shield_fill;
    }
    return Icons.security_rounded;
  }
}

/// Platform-Aware Security Badge Widget
class PlatformSecurityBadge extends StatelessWidget {
  final AppThemeConfig activeTheme;

  const PlatformSecurityBadge({super.key, required this.activeTheme});

  @override
  Widget build(BuildContext context) {
    final engineName = PlatformSecurityInfo.storageEngineName;
    final useIOSStyle = isIOS;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: activeTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(useIOSStyle ? 16 : 12),
        border: Border.all(
          color: activeTheme.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PlatformSecurityInfo.platformSecurityIcon,
            size: 20,
            color: activeTheme.primaryColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Hardware Encrypted: $engineName",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: activeTheme.textColor,
                    fontFamily: useIOSStyle ? ".SF Pro Text" : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Zero centralized backend storage. Credentials remain encrypted on your device.",
                  style: TextStyle(
                    fontSize: 11,
                    color: activeTheme.subtitleTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-Screen Platform-Aware Student Login Component
class StudentLoginScreen extends StatefulWidget {
  final Function(List<TimetableEvent> events, StudentCredentials creds) onLoginSuccess;

  const StudentLoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _keepLoggedIn = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  final _secureStorage = SecureCredentialStorage();

  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChanged);
    _checkSavedCredentials();
    _usernameFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    _usernameFocusNode.removeListener(_onFocusChange);
    _passwordFocusNode.removeListener(_onFocusChange);
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkSavedCredentials() async {
    final saved = await _secureStorage.getStudentCredentials();
    if (saved != null && mounted) {
      _usernameController.text = saved.username;
      _passwordController.text = saved.password;
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Please enter both username and password.";
      });
      return;
    }

    try {
      final scraper = DirectDartTimetableScraper();
      final events = await scraper.scrapeTimetable(
        username: username,
        password: password,
      );

      if (events.isNotEmpty) {
        await _secureStorage.saveStudentCredentials(
          username: username,
          password: password,
          keepLoggedIn: _keepLoggedIn,
        );

        if (mounted) {
          widget.onLoginSuccess(events, StudentCredentials(username: username, password: password));
        }
      } else {
        setState(() {
          _errorMessage = "Failed to retrieve timetable. Please check your credentials.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Authentication failed: ${e.toString().replaceAll("Exception: ", "")}";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showKeepLoggedInInfoDialog(AppThemeConfig activeTheme) {
    final engineName = PlatformSecurityInfo.storageEngineName;
    final useIOSStyle = isIOS;

    if (useIOSStyle) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text("Keep me logged in ($engineName)"),
          content: const Text(
            "Your device will encrypt and securely store your login details using Apple Keychain & Secure Enclave. Not recommended for shared or public devices.",
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text("Got it"),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: activeTheme.cardBackgroundColor,
          title: Text(
            "Keep me logged in ($engineName)",
            style: TextStyle(color: activeTheme.textColor, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Your device will encrypt and securely store your login details using $engineName. Not recommended for shared or public devices.",
            style: TextStyle(color: activeTheme.subtitleTextColor, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Got it", style: TextStyle(color: activeTheme.primaryColor)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIOSStyle = isIOS;
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final activeTheme = AppThemeConfig.getTheme(themeNotifier.value, systemBrightness);

    return Scaffold(
      backgroundColor: activeTheme.scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(
                  PlatformSecurityInfo.platformSecurityIcon,
                  size: 64,
                  color: activeTheme.primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  "Royal Holloway Login",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: activeTheme.textColor,
                    fontFamily: useIOSStyle ? ".SF Pro Display" : null,
                  ),
                ),
                const SizedBox(height: 16),
                PlatformSecurityBadge(activeTheme: activeTheme),
                const SizedBox(height: 32),
                _buildPlatformTextField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  placeholder: "ZPACxxx",
                  label: "University Username",
                  icon: useIOSStyle ? CupertinoIcons.person_fill : Icons.person_rounded,
                  useIOSStyle: useIOSStyle,
                  activeTheme: activeTheme,
                ),
                const SizedBox(height: 16),
                _buildPlatformTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  placeholder: "Portal Password",
                  label: "Portal Password",
                  icon: useIOSStyle ? CupertinoIcons.lock_fill : Icons.key_rounded,
                  isObscure: _obscurePassword,
                  useIOSStyle: useIOSStyle,
                  activeTheme: activeTheme,
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Icon(
                        _obscurePassword 
                            ? (useIOSStyle ? CupertinoIcons.eye_fill : Icons.visibility)
                            : (useIOSStyle ? CupertinoIcons.eye_slash_fill : Icons.visibility_off),
                        color: _passwordFocusNode.hasFocus
                            ? activeTheme.primaryColor
                            : activeTheme.subtitleTextColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    useIOSStyle
                        ? Transform.scale(
                            scale: 0.8,
                            child: CupertinoSwitch(
                              value: _keepLoggedIn,
                              activeTrackColor: activeTheme.primaryColor,
                              onChanged: (val) => setState(() => _keepLoggedIn = val),
                            ),
                          )
                        : SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _keepLoggedIn,
                              activeColor: activeTheme.primaryColor,
                              onChanged: (val) => setState(() => _keepLoggedIn = val ?? true),
                            ),
                          ),
                    const SizedBox(width: 12),
                    Text(
                      "Keep me logged in",
                      style: TextStyle(
                        color: activeTheme.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _showKeepLoggedInInfoDialog(activeTheme),
                      child: Icon(
                        useIOSStyle ? CupertinoIcons.info_circle : Icons.info_outline_rounded,
                        size: 18,
                        color: activeTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _buildPlatformButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  isLoading: _isLoading,
                  label: "Log In",
                  useIOSStyle: useIOSStyle,
                  activeTheme: activeTheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String placeholder,
    required String label,
    required IconData icon,
    bool isObscure = false,
    required bool useIOSStyle,
    required AppThemeConfig activeTheme,
    Widget? suffix,
  }) {
    final isFocused = focusNode.hasFocus;
    final accentColor = activeTheme.primaryColor;

    if (useIOSStyle) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: activeTheme.cardBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused ? accentColor : activeTheme.borderColor,
            width: isFocused ? 1.5 : 1.0,
          ),
        ),
        child: CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          obscureText: isObscure,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          prefix: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(
              icon,
              color: isFocused ? accentColor : activeTheme.subtitleTextColor,
              size: 20,
            ),
          ),
          suffix: suffix,
          decoration: const BoxDecoration(color: Colors.transparent),
          style: TextStyle(color: activeTheme.textColor),
          placeholderStyle: TextStyle(color: activeTheme.subtitleTextColor),
        ),
      );
    } else {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isObscure,
        style: TextStyle(color: activeTheme.textColor),
        decoration: InputDecoration(
          labelText: label,
          hintText: placeholder,
          hintStyle: TextStyle(color: activeTheme.subtitleTextColor),
          labelStyle: TextStyle(color: isFocused ? accentColor : activeTheme.subtitleTextColor),
          prefixIcon: Icon(icon, color: isFocused ? accentColor : activeTheme.subtitleTextColor),
          suffixIcon: suffix,
          filled: true,
          fillColor: activeTheme.cardBackgroundColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: activeTheme.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accentColor, width: 2),
          ),
        ),
      );
    }
  }

  Widget _buildPlatformButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required String label,
    required bool useIOSStyle,
    required AppThemeConfig activeTheme,
  }) {
    final textColor = activeTheme.buttonTextColor;
    if (useIOSStyle) {
      return CupertinoButton(
        color: activeTheme.primaryColor,
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(vertical: 16),
        onPressed: onPressed,
        child: isLoading
            ? CupertinoActivityIndicator(color: textColor)
            : Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
      );
    } else {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: activeTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: textColor, strokeWidth: 2),
              )
            : Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
              ),
      );
    }
  }
}
