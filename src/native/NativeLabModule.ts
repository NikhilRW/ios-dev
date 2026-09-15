import { requireNativeModule } from "expo-modules-core";

export type DeviceInfo = {
  name: string;
  system: string;
  version: string;
};

type NativeLabModuleType = {
  greet(name: string): string;
  getDeviceInfo(): Promise<DeviceInfo>;
};

export default requireNativeModule("NativeLabModule") as NativeLabModuleType;
