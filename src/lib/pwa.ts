import { signal } from '@preact/signals';

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

declare global {
  interface Window {
    /** Captured by an inline script in <head>, before the app has loaded. */
    __bip?: BeforeInstallPromptEvent | null;
  }
}

let deferred: BeforeInstallPromptEvent | null = null;
export const canInstall = signal(false);

const isStandalone = () =>
  matchMedia('(display-mode: standalone), (display-mode: window-controls-overlay)').matches ||
  (navigator as { standalone?: boolean }).standalone === true;

function capture(e: BeforeInstallPromptEvent | null | undefined) {
  if (!e || isStandalone()) return;
  deferred = e;
  canInstall.value = true;
}

export function initPwa() {
  if (typeof window === 'undefined') return;
  // Chrome usually fires beforeinstallprompt before this module runs, so pick up the early capture.
  capture(window.__bip);
  window.addEventListener('bip-ready', () => capture(window.__bip));
  window.addEventListener('appinstalled', () => {
    deferred = null;
    window.__bip = null;
    canInstall.value = false;
  });
}

export async function promptInstall() {
  if (!deferred) return;
  await deferred.prompt();
  await deferred.userChoice;
  deferred = null;
  window.__bip = null;
  canInstall.value = false;
}
