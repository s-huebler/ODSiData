# Reproducible bacterial-taxon annotation workflow

This bundle supports a cumulative Overleaf workflow in which bacterial taxa are:

- color-coded by the rank discussed in each paper;
- italicized at genus and species level;
- wrapped in named LaTeX commands;
- given full-lineage hover text through `pdfcomment`/`\pdftooltip`;
- accumulated across papers without prematurely resolving taxonomy conflicts.

## Files

- `REPRODUCIBLE_PROMPT.md` — self-contained prompt for a new AI conversation.
- `taxa_dictionary_tools.py` — dependency-free audit and update utility.
- `taxa-dictionary.tex` — a copy of the current working dictionary at the time this bundle was created.
- `example-summary.tex` — the current converted summary, used as a working example and test fixture.
- `taxa-updates-template.json` — structured template for additions and conflict merges.
- `example-merge-faeca.json` — demonstration of the `Clostridiales or Eubacteriales` merge rule; it is not applied automatically.

## The workflow used

1. **Read the article and its methods.** Identify the sequencing method, taxonomy database, and version. Preserve the paper's terminology rather than silently modernizing it.
2. **Inventory the current dictionary.** Record existing lineage macros and display commands so existing definitions are reused.
3. **Extract taxa from the summary.** Include orders, families, genera, species, abbreviations, `sp.`, `spp.`, ASV-assigned taxa, and unclassified labels.
4. **Verify rank in context.** Determine the level at which the paper actually reports each feature. A bare genus word may still refer to an unresolved species-level shotgun feature.
5. **Build or merge lineage macros.** Add missing lineages. When a later paper supports a different value at one rank, retain unique alternatives joined by ` or `.
6. **Create named display commands.** Full species names, abbreviations, and context-specific visible variants share one lineage macro.
7. **Replace taxon text in the summary.** Change only taxon markup; preserve all scientific content and rendered wording.
8. **Audit.** Confirm that every named command is defined, lineages exist, generic wrappers are gone, and genus/species italics are present.
9. **Compile-test.** Use a minimal document with the real preamble and dictionary. Tooltip behavior depends on the PDF viewer even when compilation is successful.
10. **Return reproducible artifacts.** Save the updated dictionary, updated summary, optional JSON update spec, and a short change log.

## Conflict policy

The script and prompt use a deliberately non-reconciling policy during data collection:

```latex
Order: Clostridiales%
```

plus a later supported value of `Eubacteriales` becomes:

```latex
Order: Clostridiales or Eubacteriales%
```

Existing order is preserved, exact duplicates are ignored, and no current/former designation is chosen at this stage.

## Quick audit

```bash
python3 taxa_dictionary_tools.py audit \
  --dictionary taxa-dictionary.tex \
  --summary example-summary.tex
```

The command exits with status 0 when no audit errors are found. Add `--strict` to treat warnings as failures.

## Inventory as JSON

```bash
python3 taxa_dictionary_tools.py inventory \
  --dictionary taxa-dictionary.tex \
  > dictionary-inventory.json
```

## Merge one rank alternative

Write to a new file:

```bash
python3 taxa_dictionary_tools.py merge \
  --dictionary taxa-dictionary.tex \
  --lineage taxLineFaecalibacterium \
  --rank Order \
  --value Eubacteriales \
  --output taxa-dictionary-updated.tex
```

Edit in place while retaining a `.bak` backup:

```bash
python3 taxa_dictionary_tools.py merge \
  --dictionary taxa-dictionary.tex \
  --lineage taxLineFaecalibacterium \
  --rank Order \
  --value Eubacteriales \
  --in-place
```

## Apply a JSON update specification

First copy `taxa-updates-template.json`, replace its placeholders with source-supported values, and save it as (for example) `taxa-updates.json`. Then run:

```bash
python3 taxa_dictionary_tools.py apply \
  --dictionary taxa-dictionary.tex \
  --spec taxa-updates.json \
  --output taxa-dictionary-updated.tex
```

For a working demonstration of the `or` merge rule, use `example-merge-faeca.json` on a copy of the dictionary.

The JSON specification can:

- merge an alternative into an existing rank;
- add a new lineage;
- add multiple display commands, including abbreviations, that share a lineage.

The script refuses to overwrite an existing display command with different content unless `--allow-command-replace` is supplied. In-place edits create a backup unless `--no-backup` is supplied.

## Important boundary

The helper script does **not** infer taxonomy. It only applies structured edits and checks LaTeX consistency. Taxonomic assignments must come from the attached paper, its stated taxonomy database/version, or an explicitly identified external source.
