import { signal } from '@preact/signals';

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

let deferred: BeforeInstallPromptEvent | null = null;
export const canInstall = signal(false);

export function initPwa() {
  if (typeof window === 'undefined') return;
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferred = e as BeforeInstallPromptEvent;
    canInstall.value = true;
  });
  window.addEventListener('appinstalled', () => {
    deferred = null;
    canInstall.value = false;
  });
}

export async function promptInstall() {
  if (!deferred) return;
  await deferred.prompt();
  await deferred.userChoice;
  deferred = null;
  canInstall.value = false;
}
