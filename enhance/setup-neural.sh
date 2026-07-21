#!/bin/bash
# Installs the neural enhance engine: Real-ESRGAN (ncnn/Vulkan build).
# Official prebuilt from the xinntao/Real-ESRGAN GitHub releases.
set -euo pipefail
cd "$(dirname "$0")"
if [ -x vendor/realesrgan/realesrgan-ncnn-vulkan ]; then
  echo "neural engine already installed → vendor/realesrgan"
  exit 0
fi
URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
mkdir -p vendor/realesrgan
echo "downloading Real-ESRGAN (~50 MB)…"
curl -fL --retry 3 -o vendor/realesrgan.zip "$URL"
unzip -oq vendor/realesrgan.zip -d vendor/realesrgan
chmod +x vendor/realesrgan/realesrgan-ncnn-vulkan
rm vendor/realesrgan.zip
echo "installed → vendor/realesrgan ($(du -sh vendor/realesrgan | cut -f1))"
