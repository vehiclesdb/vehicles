# Bundled plates dataset (PRD-PLATES, full corpus)

Copy of `plates/` from the public data repo (EXCLUDING `_art/`),
refreshed on gem releases:

- **Source**: https://github.com/vehiclesdb/vehiclesdb `plates/`
- **Commit**: `e8cc2f7db4139b8e9379da5c9803f297f2a4dd92`
- **License**: CC-BY 4.0 (see the data repo's LICENSE + ATTRIBUTION.md)

Refresh: `git archive origin/main plates | tar -x --exclude 'plates/_art' -C data/`
then update the commit line (this file is gem-local — recreate if lost).
