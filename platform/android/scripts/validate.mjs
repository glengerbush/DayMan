import { access, readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const repositoryRoot = dirname(dirname(root));
const required = [
  "capacitor.config.json",
  "android/settings.gradle",
  "android/app/build.gradle",
  "android/app/src/main/AndroidManifest.xml",
  "android/app/src/main/java/com/glengerbush/dayman/MainActivity.kt",
  "android/app/src/main/java/com/glengerbush/dayman/bridge/DayManJavascriptBridge.kt",
  "android/app/src/main/java/com/glengerbush/dayman/bridge/DayManWidgetPlugin.kt",
  "android/app/src/main/java/com/glengerbush/dayman/widget/DayManWidget.kt",
  "android/app/src/main/java/com/glengerbush/dayman/widget/DialRenderer.kt",
  "android/app/src/main/java/com/glengerbush/dayman/widget/WidgetRefreshScheduler.kt",
  "android/app/src/main/res/xml/dayman_widget_info.xml",
];

await Promise.all(required.map((path) => access(join(root, path))));

const config = JSON.parse(await readFile(join(root, "capacitor.config.json"), "utf8"));
if (config.appId !== "com.glengerbush.dayman" || config.webDir !== "www") {
  throw new Error("Capacitor identity or webDir does not match the Android shell");
}
if (config.plugins?.SystemBars?.insetsHandling !== "css") {
  throw new Error("Capacitor must expose Android system-bar insets to CSS");
}

const manifest = await readFile(
  join(root, "android/app/src/main/AndroidManifest.xml"),
  "utf8",
);
for (const marker of [
  "DayManWidgetReceiver",
  "SystemEventReceiver",
  "RECEIVE_BOOT_COMPLETED",
  "android.appwidget.action.APPWIDGET_UPDATE",
]) {
  if (!manifest.includes(marker)) throw new Error(`Manifest is missing ${marker}`);
}

const widget = await readFile(
  join(root, "android/app/src/main/java/com/glengerbush/dayman/widget/DayManWidget.kt"),
  "utf8",
);
if (!widget.includes("actionStartActivity<MainActivity>()")) {
  throw new Error("Widget root does not launch the full app");
}

const activity = await readFile(
  join(root, "android/app/src/main/java/com/glengerbush/dayman/MainActivity.kt"),
  "utf8",
);
if (!activity.includes('"DayManAndroid"') || !activity.includes("addJavascriptInterface")) {
  throw new Error("MainActivity does not expose window.DayManAndroid");
}
if (!activity.includes("override fun onResume()") || !activity.includes("refreshNow")) {
  throw new Error("MainActivity does not refresh widgets when the app resumes");
}

const snapshotCodec = await readFile(
  join(
    root,
    "android/app/src/main/java/com/glengerbush/dayman/widget/ClockSnapshot.kt",
  ),
  "utf8",
);
for (const marker of [
  "val snapshots: List<ClockSnapshot>",
  "snapshotFor(",
  "currentDateKey",
  "if (snapshots.isNotEmpty()) return null",
  "snapshot.takeIf { it.dateKey == currentDateKey }",
]) {
  if (!snapshotCodec.includes(marker)) {
    throw new Error(`Android snapshot queue support is missing ${marker}`);
  }
}

const sharedBridge = await readFile(
  join(repositoryRoot, "src/lib/platform-bridge.ts"),
  "utf8",
);
if (!sharedBridge.includes("snapshots: ClockSnapshot[]")) {
  throw new Error("Shared PlatformStateEnvelope does not expose its snapshot queue");
}

const sharedSnapshotModule = await readFile(
  join(repositoryRoot, "src/lib/clock-snapshot.ts"),
  "utf8",
);
if (!sharedSnapshotModule.includes("CLOCK_SNAPSHOT_QUEUE_DAYS = 32")) {
  throw new Error("Shared ClockSnapshot queue is not configured for 32 local dates");
}

const renderer = await readFile(
  join(root, "android/app/src/main/java/com/glengerbush/dayman/widget/DialRenderer.kt"),
  "utf8",
);
for (const marker of [
  "drawCurrentTimeHand",
  "snapshot.currentMinuteAt(instant)",
  "DashPathEffect",
  "drawHourTicksAndLabels",
  '"Rise $sunrise  •  Set $sunset"',
]) {
  if (!renderer.includes(marker)) {
    throw new Error(`Widget rendering support is missing ${marker}`);
  }
}
if (!widget.includes("moon-nearside.webp")) {
  throw new Error("Widget does not load the shared near-side Moon texture");
}

const fixturesDirectory = join(repositoryRoot, "fixtures/clock-snapshots");
const fixtureNames = (await readdir(fixturesDirectory)).filter((name) =>
  name.endsWith(".json"),
);
if (fixtureNames.length < 4) {
  throw new Error("Expected shared DST, polar, and Moon-phase ClockSnapshot fixtures");
}
for (const fixtureName of fixtureNames) {
  const fixture = JSON.parse(
    await readFile(join(fixturesDirectory, fixtureName), "utf8"),
  );
  if (
    fixture.schemaVersion !== 1 ||
    typeof fixture.dateKey !== "string" ||
    typeof fixture.timezone !== "string" ||
    !Array.isArray(fixture.arcs) ||
    !Array.isArray(fixture.events) ||
    typeof fixture.moon?.illumination !== "number"
  ) {
    throw new Error(`${fixtureName} does not match ClockSnapshot schemaVersion 1`);
  }
  for (const arc of fixture.arcs) {
    if (
      typeof arc.kind !== "string" ||
      !Array.isArray(arc.ranges) ||
      arc.ranges.some(
        (range) =>
          typeof range.startMinute !== "number" ||
          typeof range.endMinute !== "number",
      )
    ) {
      throw new Error(`${fixtureName} contains an invalid clock arc`);
    }
  }
}

console.log(
  `Android shell validation passed (${required.length} files, ${fixtureNames.length} shared fixtures).`,
);
