//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_decoder/audio_decoder_plugin.h>
#include <flutter_onnxruntime/flutter_onnxruntime_plugin.h>
#include <sentry_flutter/sentry_flutter_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) audio_decoder_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AudioDecoderPlugin");
  audio_decoder_plugin_register_with_registrar(audio_decoder_registrar);
  g_autoptr(FlPluginRegistrar) flutter_onnxruntime_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterOnnxruntimePlugin");
  flutter_onnxruntime_plugin_register_with_registrar(flutter_onnxruntime_registrar);
  g_autoptr(FlPluginRegistrar) sentry_flutter_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SentryFlutterPlugin");
  sentry_flutter_plugin_register_with_registrar(sentry_flutter_registrar);
}
