import { useState } from "react";
import { Button, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import NativeLabModule, { DeviceInfo } from "../native/NativeLabModule";

export default function App() {
  const [message, setMessage] = useState("");
  const [device, setDevice] = useState<DeviceInfo | null>(null);

  function callSwiftFunction() {
    const result = NativeLabModule.greet("Nikhil");
    setMessage(result);
  }

  async function loadDeviceInfo() {
    const result = await NativeLabModule.getDeviceInfo();
    setDevice(result);
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>Expo + Swift Lab</Text>

        <Button title="Call Swift function" onPress={callSwiftFunction} />

        {message ? <Text style={styles.result}>{message}</Text> : null}

        <Button title="Get iPhone information" onPress={loadDeviceInfo} />

        {device ? (
          <View style={styles.card}>
            <Text>Device: {device.name}</Text>
            <Text>System: {device.system}</Text>
            <Text>Version: {device.version}</Text>
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    justifyContent: "center",
    gap: 20,
    padding: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: "700",
  },
  result: {
    fontSize: 17,
  },
  card: {
    gap: 6,
    padding: 16,
    borderRadius: 12,
    backgroundColor: "#eeeeee",
  },
});
