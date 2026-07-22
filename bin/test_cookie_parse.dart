import 'dart:io';

List<String> splitSetCookieHeader(String raw) {
  final List<String> cookies = [];
  int start = 0;
  bool inExpires = false;

  for (int i = 0; i < raw.length; i++) {
    if (i + 7 <= raw.length && raw.substring(i, i + 7).toLowerCase() == 'expires') {
      inExpires = true;
    }
    if (raw[i] == ';' && inExpires) {
      inExpires = false;
    }
    if ((raw[i] == ',' || raw[i] == '\n') && !inExpires) {
      final part = raw.substring(start, i).trim();
      if (part.isNotEmpty) cookies.add(part);
      start = i + 1;
    }
  }
  final lastPart = raw.substring(start).trim();
  if (lastPart.isNotEmpty) cookies.add(lastPart);
  return cookies;
}

void main() {
  final sampleHeader = "ASP.NET_SessionId=mriesqzaoaawouudec4d5xr0; path=/; HttpOnly; SameSite=Lax, ScientiaSWS=5DD04CDF29B3AC9F; expires=Wed, 21-Oct-2026 08:37:19 GMT; path=/; HttpOnly";

  final split = splitSetCookieHeader(sampleHeader);
  print("Split parts count: ${split.length}");
  for (final part in split) {
    try {
      final c = Cookie.fromSetCookieValue(part);
      print("Parsed Cookie: ${c.name} = ${c.value}");
    } catch (e) {
      print("Failed to parse part '$part': $e");
    }
  }
}
