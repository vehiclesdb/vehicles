# Bundled plates dataset (PRD-PLATES, full corpus)

Copy of `plates/` from the public data repo (EXCLUDING `_art/`),
refreshed on gem releases:

- **Source**: https://github.com/vehiclesdb/vehiclesdb `plates/`
- **Commit**: `523f488ac4dd84a9694fdc984f90639c8b0da6dd`
- **License**: CC-BY 4.0 (see the data repo's LICENSE + ATTRIBUTION.md)

Refresh: `git archive origin/main plates | tar -x --exclude 'plates/_art' -C data/`
then update the commit line (this file is gem-local — recreate if lost).
