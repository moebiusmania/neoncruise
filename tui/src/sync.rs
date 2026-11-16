//! Poison-tolerant locking.
//!
//! Every mutex here guards plain data (sample buffers, metadata maps) that stays valid even if a
//! thread panicked mid-update. With `lock().unwrap()`, one panic on a network or decoder thread
//! would poison the lock and turn every later access, including the UI's, into another panic.

use std::sync::{Mutex, MutexGuard, PoisonError};

pub trait LockExt<T> {
    fn lock_ok(&self) -> MutexGuard<'_, T>;
}

impl<T> LockExt<T> for Mutex<T> {
    fn lock_ok(&self) -> MutexGuard<'_, T> {
        self.lock().unwrap_or_else(PoisonError::into_inner)
    }
}
