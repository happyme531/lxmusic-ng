//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_decoder
import file_picker
import flutter_onnxruntime
import package_info_plus
import sentry_flutter
import shared_preferences_foundation

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioDecoderPlugin.register(with: registry.registrar(forPlugin: "AudioDecoderPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  FlutterOnnxruntimePlugin.register(with: registry.registrar(forPlugin: "FlutterOnnxruntimePlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SentryFlutterPlugin.register(with: registry.registrar(forPlugin: "SentryFlutterPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
}
