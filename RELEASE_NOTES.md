## What's Changed

- **Fixed target options appearing but not working on click**: Removed strict function type checks on `canInteract` and `action` in `qb-target` / `qtarget` compat layers. In FiveM, cross-resource callbacks arrive as callable tables (funcrefs), which were previously dropped. (Credits to **cookieocore2026** and **koda.codes** for reporting this!)
- **Fixed target re-activating right after click**: Confirming an option now resets the targeting state to idle, requiring the key to be pressed again to re-target instead of immediately reopening if the key was still held.
