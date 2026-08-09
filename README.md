# Dictaste for macOS

> **Canonical monorepo (star this for free Developer plan):**  
> https://github.com/johnmatveyev-lab/dictaste  
> Source lives in `mac/` there (Apache-2.0).

This repository remains a **mirror** of the Mac client for historical links.

## Build

Prefer the monorepo:

```bash
git clone https://github.com/johnmatveyev-lab/dictaste.git
cd dictaste/mac
brew install xcodegen && xcodegen generate
./scripts/install_local.sh
```

Or from this repo (same layout as monorepo `mac/`):

```bash
brew install xcodegen
xcodegen generate
./scripts/install_local.sh
```

**Product:** https://dictaste.vercel.app  
**Free for developers:** star `johnmatveyev-lab/dictaste` → https://dictaste.vercel.app/developers/setup  
