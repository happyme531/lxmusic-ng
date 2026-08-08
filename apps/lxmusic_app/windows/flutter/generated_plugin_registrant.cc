//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_decoder/audio_decoder_plugin_c_api.h>
#include <flutter_onnxruntime/flutter_onnxruntime_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioDecoderPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioDecoderPluginCApi"));
  FlutterOnnxruntimePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterOnnxruntimePlugin"));
}
