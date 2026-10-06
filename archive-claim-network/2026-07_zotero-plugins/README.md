# Zotero plugins (July 2026)

**When:** Jul 9 – 16 2026.

**What was being attempted:** Getting cleaner citation keys and DOIs straight out of Zotero
for the reference-matching step.

- `zotero-better-bibtex-9.0.36.xpi`: Better BibTeX installer (stable `Author_Year` citekeys, .bib export).
- `zotadata.xpi`: Zotadata plugin installer (metadata/DOI discovery, attachment checks).
- `zotero-zotadata-main/`: Zotadata source checkout, including `node_modules`, kept from building or
  inspecting the plugin.

**Status:** Tooling only, with no research outputs. All of it can be re-downloaded, and
`node_modules` can be rebuilt with `npm install`. Excluded from git (see `.gitignore`).
