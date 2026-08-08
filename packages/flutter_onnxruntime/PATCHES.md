# LxMusic-NG local changes

- Android inference accepts requested outputs and caller-owned pinned outputs.
  This uses the official ONNX Runtime Java preallocated-output API so
  autoregressive models can update fixed-capacity KV caches in place.
- Android can allocate zero-filled OrtValues directly in native memory, avoiding
  hundreds of MiB of platform-channel traffic when initializing KV caches.
- Android uses ONNX Runtime 1.28.0 instead of the upstream package's 1.23.0
  dependency, which crashed with an illegal Arm instruction on the target phone.
- Android reports `ARM_NN` as unavailable because ONNX Runtime 1.28.0 removed
  the Java `SessionOptions.addArmNN` API.
