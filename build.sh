#!/bin/bash
set -e
cd "$(dirname "$0")"

APP=build/RemotePad.app
ARCHS=${ARCHS:-arm64}          # arm64 | x86_64 | universal
SIGN_ID=${CODESIGN_IDENTITY:-}

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 官方 Siri Remote 3D 模型属于 Apple 版权资源，仓库不附带。
# 自行准备同名文件放到 Resources/SiriRemote.usdz 即可启用 1:1 外观；
# 没有该文件时 App 使用程序化替代模型，功能完全一致。
if [ -f Resources/SiriRemote.usdz ]; then
  cp Resources/SiriRemote.usdz "$APP/Contents/Resources/SiriRemote.usdz"
else
  echo "note: Resources/SiriRemote.usdz 不存在，将使用程序化模型"
fi

FLAGS=(
  -O
  -framework Cocoa -framework IOKit -framework ServiceManagement
  -framework SceneKit -framework CoreBluetooth
  -F /System/Library/PrivateFrameworks -framework MultitouchSupport
  -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks
)

build_one() {
  swiftc "${FLAGS[@]}" -target "$1-apple-macos13.0" \
    -o "$APP/Contents/MacOS/RemotePad$2" Sources/*.swift
}

if [ "$ARCHS" = "universal" ]; then
  build_one arm64 .arm64
  build_one x86_64 .x86_64
  lipo -create -output "$APP/Contents/MacOS/RemotePad" \
    "$APP/Contents/MacOS/RemotePad.arm64" "$APP/Contents/MacOS/RemotePad.x86_64"
  rm -f "$APP/Contents/MacOS/RemotePad.arm64" "$APP/Contents/MacOS/RemotePad.x86_64"
else
  build_one "$ARCHS" ""
fi

# 有本地自签证书就用，没有就用 ad-hoc 签名（自用足够；对外分发需开发者证书 + 公证）
if [ -z "$SIGN_ID" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "RemotePad Signer"; then
    SIGN_ID="RemotePad Signer"
  else
    SIGN_ID="-"
  fi
fi

codesign --force --deep --identifier com.once.remotepad --sign "$SIGN_ID" "$APP"
echo "built: $APP (arch=$ARCHS, sign=$SIGN_ID)"
