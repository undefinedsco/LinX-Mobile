# Whisper Models

Place production whisper.cpp model files in this bundle resource directory:

- `ggml-base.bin`

Model binaries are intentionally not committed. From `apple/`, run:

```sh
scripts/prepare-whisper.sh
```

The script downloads and verifies `ggml-base.bin` here. It also installs the
matching whisper.cpp XCFramework under `Vendors/Whisper/`.
