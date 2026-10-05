#!/bin/bash
# tvhub 构建脚本（macOS，使用 /Applications/DevEco-Studio.app 自带工具链）
# 用法：./build-mac.sh          # 编译 + 打包（默认 debug，未签名）
set -e
DEVECO=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME="$DEVECO/sdk"
export NODE_HOME="$DEVECO/tools/node"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$DEVECO/tools/ohpm/bin:$DEVECO/tools/hvigor/bin:$PATH"
cd "$(dirname "$0")"
echo "== ohpm install =="
ohpm install
echo "== hvigor build =="
hvigorw assembleHap --mode module -p product=default --no-daemon
echo "== 产物 =="
find entry/build -name "*.hap" | head
