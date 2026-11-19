import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Applies native Windows 11 window styling that Flutter cannot express:
/// rounded window corners and a matching border colour.
///
/// Uses `DwmSetWindowAttribute` from `dwmapi.dll`. On Windows 10 or when the
/// attribute is unsupported the call is a no-op, so the app keeps working.
class WindowStyle {
  static bool _applied = false;

  static void applyRoundedCorners({String title = 'klaro.'}) {
    if (!Platform.isWindows || _applied) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindow = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

      final titlePtr = title.toNativeUtf16();
      final hwnd = findWindow(nullptr, titlePtr);
      malloc.free(titlePtr);
      if (hwnd == 0) return;

      final dwmapi = DynamicLibrary.open('dwmapi.dll');
      final setAttribute = dwmapi.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Int32>, Uint32),
          int Function(int, int, Pointer<Int32>, int)>('DwmSetWindowAttribute');

      // DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2
      final corner = malloc<Int32>()..value = 2;
      setAttribute(hwnd, 33, corner, 4);
      malloc.free(corner);

      // DWMWA_BORDER_COLOR = 34, a neutral hairline that matches the app chrome.
      final border = malloc<Int32>()..value = 0x00E8E8E8;
      setAttribute(hwnd, 34, border, 4);
      malloc.free(border);

      _applied = true;
    } catch (_) {
      // Older Windows builds: keep the default square frame.
    }
  }
}
