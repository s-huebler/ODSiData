# Microbe evidence table and translational radial figure (July 2026)

**When:** Jul 13 – 14 2026.

**What was being attempted:** A figure-oriented alternative to the network. Taxa sit on a ring
grouped by phylogeny, with inner and outer rings showing GVHD direction, depth of evidence,
mechanism (metabolite class) and how far therapeutic testing has gone. The aim was to visualize
**translational gaps**.

| File | Role |
|---|---|
| `Microbe_Evidence_Table.xlsx` | Driver table (one row per taxon), auto-derived from batch-1 `Claims_Synthesis_Reference.xlsx`. README sheet lists the fields that still need manual review. |
| `Microbe_Evidence_Figure_draft.svg` | First static draft of the figure |
| `gvhd_translational_radial.html` | Interactive proof of concept |
| `gvhd_translational_radial_preview.svg` | Static preview of the interactive version |

**Status:** Proof of concept built on batch-1 data only. Not updated for batch 2. The
therapeutic ring is sparse until a therapeutics-focused extraction (the Studies sheet) is
synthesized. Could be revived from `claim-network/data/Claims_Synthesis2.xlsx` plus the
Studies sheet of `parsed2_Claims_15July.xlsx`.
