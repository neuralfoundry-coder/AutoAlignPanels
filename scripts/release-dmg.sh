#!/bin/bash
# AutoAlignPanels — Developer ID 서명 + 공증 + DMG 생성 (직접 배포 전용)
#
# 자격 증명: 환경 변수 → 없으면 ~/.zshrc 의 같은 이름 변수에서 읽음
#   APP_STORE_CONNECT_API_KEY_ID   ASC API 키 ID
#   APP_STORE_CONNECT_ISSUER_ID    ASC Issuer ID
#   APP_STORE_CONNECT_KEY_PATH     .p8 경로 (~ 허용)
#   APP_STORE_TEAMID               팀 ID
#
# 서명: 키체인에 Developer ID Application 인증서가 없어도 된다. export 단계의
# -allowProvisioningUpdates + API 키로 Xcode 클라우드 관리 Developer ID 인증서를
# 사용한다(API 키에 Admin 권한 필요). 로컬 인증서가 있으면 DMG 자체도 서명한다.
#
# 사용법: ./scripts/release-dmg.sh
# 결과물: dist/AutoAlignPanels-<버전>.dmg (앱·DMG 모두 공증+스테이플 완료)
set -euo pipefail
cd "$(dirname "$0")/.."

# Xcode 툴체인 강제 (CommandLineTools 에는 #Preview 매크로 플러그인이 없음)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

zshrc_var() {
  [ -f ~/.zshrc ] || return 0
  sed -nE "s/^(export[[:space:]]+)?$1=['\"]?([^'\"]*)['\"]?[[:space:]]*$/\2/p" ~/.zshrc | tail -1
}
KEY_ID=${APP_STORE_CONNECT_API_KEY_ID:-$(zshrc_var APP_STORE_CONNECT_API_KEY_ID)}
ISSUER=${APP_STORE_CONNECT_ISSUER_ID:-$(zshrc_var APP_STORE_CONNECT_ISSUER_ID)}
KEY=${APP_STORE_CONNECT_KEY_PATH:-$(zshrc_var APP_STORE_CONNECT_KEY_PATH)}
KEY="${KEY/#\~/$HOME}"
TEAM=${APP_STORE_TEAMID:-$(zshrc_var APP_STORE_TEAMID)}

for v in KEY_ID ISSUER KEY TEAM; do
  [ -n "${!v}" ] || { echo "오류: $v 를 찾을 수 없습니다 (환경 변수 또는 ~/.zshrc)"; exit 1; }
done
[ -f "$KEY" ] || { echo "오류: API 키 파일 없음: $KEY"; exit 1; }
AUTH=(-authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
NOTARY=(--key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER")

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([0-9.]+)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/.*"([0-9]+)".*/\1/')
WORK=$(mktemp -d /tmp/aap-release.XXXXXX)
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true' EXIT
DMG="dist/AutoAlignPanels-${VERSION}.dmg"

echo "==> [1/6] xcodegen + Release 아카이브 (v${VERSION} build ${BUILD}, 샌드박스 없음)"
# project.yml 의 DEVELOPMENT_TEAM 은 ${DEVELOPMENT_TEAM} 로 비워 두고 여기서 주입한다
# (팀 ID 를 저장소에 커밋하지 않기 위해).
export DEVELOPMENT_TEAM="$TEAM"
xcodegen generate
# CODE_SIGN_ENTITLEMENTS 오버라이드: 직접 배포 빌드는 App Sandbox를 끈다.
# 샌드박스 앱은 손쉬운 사용 자동 등록, 이전 설치본 교체, 권한 리셋이 모두 막힌다.
xcodebuild clean archive \
  -project AutoAlignPanels.xcodeproj -scheme AutoAlignPanels -configuration Release \
  -archivePath "$WORK/AutoAlignPanels.xcarchive" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  CODE_SIGN_ENTITLEMENTS=AutoAlignPanelsDirect.entitlements \
  > "$WORK/archive.log" 2>&1 || { tail -30 "$WORK/archive.log"; echo "오류: 아카이브 실패 ($WORK/archive.log)"; exit 1; }

echo "==> [2/6] Developer ID 내보내기"
xcodebuild -exportArchive \
  -archivePath "$WORK/AutoAlignPanels.xcarchive" \
  -exportOptionsPlist ExportOptionsDirect.plist \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  > "$WORK/export.log" 2>&1 || { tail -30 "$WORK/export.log"; echo "오류: 내보내기 실패 ($WORK/export.log)"; exit 1; }
APP="$WORK/export/AutoAlignPanels.app"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=Developer ID Application" \
  || { echo "오류: Developer ID 로 서명되지 않았습니다"; codesign -dvv "$APP"; exit 1; }
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "app-sandbox" \
  && { echo "오류: 직접 배포 빌드에 샌드박스가 켜져 있습니다"; exit 1; }

echo "==> [3/6] 앱 공증 (1~5분 대기)"
ditto -c -k --keepParent "$APP" "$WORK/app.zip"
xcrun notarytool submit "$WORK/app.zip" "${NOTARY[@]}" --wait | tee "$WORK/notary-app.log"
grep -q "status: Accepted" "$WORK/notary-app.log" || { echo "오류: 앱 공증 실패"; exit 1; }
xcrun stapler staple "$APP"

echo "==> [4/6] DMG 생성"
mkdir -p dist "$WORK/stage"
rm -f "$DMG"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
hdiutil create -volname "AutoAlignPanels ${VERSION}" -srcfolder "$WORK/stage" -ov -format UDZO "$DMG"

echo "==> [5/6] DMG 서명 (로컬 Developer ID 인증서가 있을 때만; 동명 인증서 대비 해시로 지정)"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)
if [ -n "$IDENTITY" ]; then
  codesign -s "$IDENTITY" --timestamp "$DMG"
else
  echo "    로컬 Developer ID 인증서 없음 → DMG 서명 생략 (공증 티켓 스테이플로 Gatekeeper 통과)"
fi

echo "==> [6/6] DMG 공증 + 스테이플 + 검증"
xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait | tee "$WORK/notary-dmg.log"
grep -q "status: Accepted" "$WORK/notary-dmg.log" || { echo "오류: DMG 공증 실패"; exit 1; }
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG" | tail -1
mkdir -p "$WORK/mnt"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$WORK/mnt" -quiet
spctl -a -t exec -vv "$WORK/mnt/AutoAlignPanels.app"
hdiutil detach "$WORK/mnt" -quiet

rm -rf "$WORK"
echo ""
echo "완료: $DMG"
