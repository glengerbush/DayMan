/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_BASE_PATH?: string;
  readonly VITE_ANDROID_APK_URL?: string;
  readonly VITE_MACOS_DOWNLOAD_URL?: string;
  readonly VITE_LINUX_APPIMAGE_URL?: string;
  readonly VITE_LINUX_DEB_URL?: string;
  readonly VITE_LINUX_RPM_URL?: string;
  readonly VITE_LINUX_ARCH_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
