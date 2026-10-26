#!/bin/sh
# Wire the app's own Gt7Direct plugin (direct PS5 telemetry + GT7 sign-in) into
# the generated Capacitor projects. Run after `npx cap add ios|android`; safe to
# re-run (npm run ios / npm run android call it for you).
set -e
cd "$(dirname "$0")"
if [ -d ios/App/App ]; then
  cp plugin/ios/Gt7DirectPlugin.swift plugin/ios/MainViewController.swift ios/App/App/
  # use our view controller (it registers the plugin)
  sed -i '' 's/customClass="CAPBridgeViewController" customModule="Capacitor"/customClass="MainViewController" customModule="App" customModuleProvider="target"/' ios/App/App/Base.lproj/Main.storyboard 2>/dev/null || true
  # add the two Swift files to the Xcode target if they aren't in it yet
  if ! grep -q Gt7DirectPlugin.swift ios/App/App.xcodeproj/project.pbxproj; then
    ruby -e 'begin; require "xcodeproj"; rescue LoadError; puts "  (gem install xcodeproj, or drag native/plugin/ios/*.swift into the App target in Xcode)"; exit; end
      p = Xcodeproj::Project.open("ios/App/App.xcodeproj"); t = p.targets.find { |x| x.name == "App" }; g = p.main_group["App"]
      %w[Gt7DirectPlugin.swift MainViewController.swift].each { |f| t.add_file_references([g.new_file(f)]) unless g.files.any? { |x| x.path == f } }
      p.save' || true
  fi
  PL=ios/App/App/Info.plist
  /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'GT7 Endgame talks to your PS5 on your Wi-Fi to read live telemetry from Gran Turismo 7.'" "$PL" 2>/dev/null || true
  echo "iOS: Gt7Direct wired in."
fi
if [ -d android/app/src/main ]; then
  D=android/app/src/main/java/com/labern/gt7endgame
  mkdir -p "$D" && cp plugin/android/Gt7DirectPlugin.kt "$D/"
  MA="$D/MainActivity.java"
  if [ -f "$MA" ] && ! grep -q Gt7DirectPlugin "$MA"; then
    cat > "$MA" <<'JAVA'
package com.labern.gt7endgame;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    registerPlugin(Gt7DirectPlugin.class);
    super.onCreate(savedInstanceState);
  }
}
JAVA
  fi
  # Kotlin support for the plugin file
  grep -q "kotlin-android" android/app/build.gradle || sed -i.bak "1s/^/apply plugin: 'kotlin-android'\n/" android/app/build.gradle
  grep -q "kotlin-gradle-plugin" android/build.gradle || sed -i.bak "s/dependencies {/dependencies {\n        classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24'/" android/build.gradle
  # Kotlin must target the same JVM as Capacitor's Java (17)
  grep -q "jvmTarget" android/app/build.gradle || sed -i.bak "s/^android {/android {\n    kotlinOptions { jvmTarget = '17' }/" android/app/build.gradle
  echo "Android: Gt7Direct wired in."
fi
