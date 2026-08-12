# Reproducible prompt: update a LaTeX taxon-tooltip dictionary and summary

Copy the prompt below into a new conversation and attach:

1. the article PDF;
2. the current LaTeX summary or section to edit;
3. the current `taxa-dictionary.tex`;
4. optionally, the document preamble if the taxon base commands or packages may have changed.

---

## Prompt

You are updating a cumulative LaTeX dictionary of bacterial taxa used across multiple paper summaries.

### Inputs

I have attached:

- an article PDF;
- a LaTeX summary/section based on that article;
- my current `taxa-dictionary.tex`;
- optionally, my current preamble.

### Required deliverables

Return all of the following:

1. an updated `taxa-dictionary.tex` as a downloadable file;
2. the edited summary/section as LaTeX, with every bacterial taxon mention replaced by a named dictionary command;
3. a brief change log listing:
   - newly added lineage macros;
   - newly added display or abbreviation commands;
   - existing lineage ranks amended with alternatives joined by `or`;
   - any unresolved or ambiguous classifications;
4. a validation report stating whether all taxon commands used in the summary are defined in the dictionary and whether a LaTeX compile test succeeded.

Do not merely describe the edits. Produce the updated files and the complete edited LaTeX block.

### Non-negotiable content rule

Do not change the wording, claims, numbers, order, punctuation, or scientific content of my summary. Only replace taxon text or existing generic taxonomic wrappers with named commands from the dictionary. Preserve the rendered text exactly, including articles such as `a` or `an`, abbreviations, `sp.`, `spp.`, and phrases such as `unclassified ... species`.

### Source-grounding rule

Use the attached paper as the primary source for:

- which taxa are being discussed;
- the taxonomic rank at which each result is reported;
- whether a feature comes from 16S, shotgun sequencing, an ASV, an unresolved species-level feature, or another method;
- the paper's own taxonomic terminology;
- the taxonomy database and version used by the paper, when stated.

Do not silently replace the paper's terminology with a newer taxonomy. If the paper does not support a rank or lineage value, do not invent it. Use wording such as `not specified`, `not resolved`, `unclassified`, or `not resolved by this paper-level label` as appropriate. External taxonomy sources may be used only when needed to fill a missing lineage rank; clearly identify any externally supplied value in the change log.

### Cumulative conflict policy

The dictionary is cumulative across papers. Do not delete or overwrite a previously recorded rank value merely because the new paper uses a different designation.

For each lineage macro and rank:

- if the new value is identical to an existing value, make no change;
- if the new paper supports a different value, append the new unique option using the literal separator ` or `;
- preserve the existing option order;
- do not duplicate an option;
- do not attempt to decide which designation is current, former, preferred, or synonymous unless I explicitly ask.

Example:

```latex
Order: Clostridiales%
```

plus a later paper assigning the same taxon to Eubacteriales becomes:

```latex
Order: Clostridiales or Eubacteriales%
```

This rule applies independently at every rank, including phylum, class, order, family, genus, and species.

### Taxonomic formatting rules

Use the existing rank colors and base commands in the preamble:

- phylum: `\taxPhylum{...}`;
- class: `\taxClass{...}`;
- order: `\taxOrder{...}`;
- family: `\taxFamily{...}`;
- genus: `\taxGenus{...}`;
- species or species-level feature: `\taxSpecies{...}`.

Italicize genus names and species names. Do not italicize family, order, class, or phylum names. For a phrase such as `Staphylococcus species`, italicize only `Staphylococcus`. For `sp.` or `spp.`, italicize the genus but not `sp.` or `spp.`.

### Dictionary architecture

Preserve the existing dictionary architecture unless a compile error requires a minimal repair:

1. one reusable lineage macro per taxonomic concept, named `\taxLine...`;
2. one or more robust display commands pointing to that lineage macro;
3. full-name and abbreviated species commands must share the same lineage macro;
4. each display command must use `\taxonTooltip`, the correct rank wrapper, and `\xspace`;
5. commands must remain safe in headings and PDF bookmarks through the existing `\texorpdfstring` implementation.

A lineage macro should follow this pattern:

```latex
\newcommand{\taxLineExample}{%
Domain: Bacteria\textCR%
Phylum: Examplephylum\textCR%
Class: Exampleclass\textCR%
Order: Exampleorder\textCR%
Family: Examplefamily\textCR%
Genus: Examplegenus\textCR%
Species: Examplegenus examplespecies%
}
```

A full species command should follow this pattern:

```latex
\DeclareRobustCommand{\taxExampleGenusExampleSpecies}{%
  \taxonTooltip{\taxSpecies{\textit{Examplegenus examplespecies}}}
  {Examplegenus examplespecies}{\taxLineExample}\xspace}
```

An abbreviated command should reuse the same lineage:

```latex
\DeclareRobustCommand{\taxEexamplespecies}{%
  \taxonTooltip{\taxSpecies{\textit{E. examplespecies}}}
  {E. examplespecies}{\taxLineExample}\xspace}
```

### Command naming rules

Use stable ASCII command names:

- order: `\taxClostridiales`;
- family: `\taxRuminococcaceae`;
- genus: `\taxFaecalibacterium`;
- full species: `\taxEnterococcusFaecium`;
- abbreviated species: `\taxEfaecium`;
- unresolved species-level feature: `\taxButyricicoccusSp`;
- a context-specific visible variant may use a clear suffix such as `Bare`, `Species`, or `Spp` while sharing the same lineage macro.

Do not create two independent lineage macros for a full species name and its abbreviation. Do not reuse a genus-level display command for a species-level result merely because only the genus word is visibly printed.

### Rank-assignment rules

Classify each mention according to the level discussed in the paper and the local sentence, not merely the grammatical appearance of the name.

Examples:

- a named order is order-level;
- a named family is family-level;
- a genus reported by 16S is genus-level;
- a shotgun feature reported as `Genus sp.` is species-level but unresolved;
- a bare genus word that refers back to an unresolved shotgun species-level feature may need a species-colored `Bare` command;
- an ASV assigned only to a genus remains an ASV/genus-assigned feature; use the visible genus command unless the sentence explicitly discusses species-level testing;
- `Genus species` as a generic phrase can require a species-level phrase command distinct from the genus command.

### Procedure

Follow this sequence:

1. Read the current dictionary and inventory every existing `\taxLine...` macro and named `\tax...` display command.
2. Read the supplied summary and list every taxon mention, including repeated forms, abbreviations, `sp.`, `spp.`, family/order names, ASV-assigned genera, and unclassified labels.
3. Locate each taxon in the paper and determine the rank and analytical context used by the authors.
4. Record the paper's taxonomy database/version and use it to interpret paper-era labels where possible.
5. Match each mention to an existing dictionary concept or define a new lineage macro.
6. Apply the cumulative conflict policy to every existing lineage rank.
7. Add full-name, abbreviated, and context-specific display commands as needed, reusing lineage macros.
8. Edit the summary by replacing taxon text or generic wrappers with named commands only. Do not alter content.
9. Audit the result:
   - every named `\tax...` command in the summary is defined exactly once;
   - every display command points to a defined lineage macro;
   - no generic `\taxOrder{...}`, `\taxGenus{...}`, and similar wrappers remain around taxa in the summary;
   - genus and species text is italicized correctly;
   - rank colors are correct;
   - full and abbreviated species forms share a lineage;
   - no duplicate lineage alternatives exist;
   - rendered wording remains unchanged.
10. Compile a minimal LaTeX test using the supplied preamble and updated dictionary when a TeX engine is available. Report any viewer-specific limitation of `pdfcomment` tooltips separately from compilation success.
11. Return the updated dictionary file, complete edited summary block, change log, and validation result.

### Optional helper script

A file named `taxa_dictionary_tools.py` may be attached with this prompt. Use it when available.

Audit an updated dictionary and summary:

```bash
python3 taxa_dictionary_tools.py audit \
  --dictionary taxa-dictionary-updated.tex \
  --summary summary-updated.tex
```

Merge one alternative into an existing rank:

```bash
python3 taxa_dictionary_tools.py merge \
  --dictionary taxa-dictionary.tex \
  --lineage taxLineFaecalibacterium \
  --rank Order \
  --value Eubacteriales \
  --output taxa-dictionary-updated.tex
```

Apply a structured JSON update specification:

```bash
python3 taxa_dictionary_tools.py apply \
  --dictionary taxa-dictionary.tex \
  --spec taxa-updates.json \
  --output taxa-dictionary-updated.tex
```

The helper script is only an editing and validation tool. It must not be treated as a source of taxonomic truth.

### Final response format

Give me:

1. a download link to the updated dictionary;
2. a download link to the updated summary `.tex`, if you created one;
3. the complete updated summary in a fenced `latex` code block;
4. a concise change log;
5. the audit and compile result;
6. source citations supporting the rank assignments and any classification conflicts.

Do not omit the files even if the code is also shown inline.
