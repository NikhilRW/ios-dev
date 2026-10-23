# Attendance App

A one-screen React Native CLI + TypeScript attendance tracker for Android. Subjects are saved on the device using memory-mapped MMKV storage, so they remain after the app closes. Chat uses a simple on-device phrase parser. No account or server is needed.

## Run on Android (bare React Native CLI)

1. Install Node.js 22.13+, Android Studio/Android SDK, and set up an Android emulator or USB-connected device (see the [React Native environment guide](https://reactnative.dev/docs/set-up-your-environment)).
2. In this folder, run `bun install` (or `npm install`).
3. Run `bun run start` (or `npm start`) to start Metro. In a second terminal run `bun run android` (or `npm run android`) to build and install the native Android app.

Add subjects with attended and total class counts, use Present/Absent, or type “I missed Maths today”, “I attended Maths today”, or “What if I miss one Maths class?” in chat. Confirm proposed chat changes before they are saved. When chat cannot identify a subject, type its name in the next message.
