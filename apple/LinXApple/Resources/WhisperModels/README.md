# Whisper Models

Place production whisper.cpp model files in this bundle resource directory:

- `ggml-tiny.bin`
- `ggml-base.bin`

Model binaries are intentionally not committed in this repository snapshot. The
runtime surfaces a clear `modelNotFound` error until a model file is bundled.
