/// Native macOS plugin for RbNotes: permissions, dual-source audio recording,
/// local whisper.cpp transcription and global dictation.
///
/// The host app depends on the `RbNative` interface and the model/enum types
/// exported here. The default concrete implementation is
/// `MethodChannelRbNative`.
library;

export 'src/enums.dart';
export 'src/exceptions.dart';
export 'src/method_channel_rb_native.dart'
    show MethodChannelRbNative, RbNativeChannels;
export 'src/models.dart';
export 'src/rb_native.dart';
