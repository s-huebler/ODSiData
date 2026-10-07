"""Run the full claims synthesis pipeline.

Usage: python run_synthesis.py [--input Claims_Master_reflinked.xlsx]

Steps:
  01_atomize    → raw atomic rows from Claims_Master_reflinked
  02_subjects   → subject normalization
  03_taxonomy   → rank assignment
  04_valence    → valence mapping
  05_mechanism  → mechanism categorization
  06_canonical  → canonical claim assignment
  07_write_workbook → Claims_Synthesis3.xlsx + graph_data3.json
"""
import sys
import importlib

STEPS = [
    "01_atomize",
    "02_subjects",
    "03_taxonomy",
    "04_valence",
    "05_mechanism",
    "06_canonical",
    "07_write_workbook",
]


def run():
    df = None
    for step_name in STEPS:
        mod = importlib.import_module(step_name)
        try:
            if step_name == "01_atomize":
                df = mod.main()
            elif step_name == "07_write_workbook":
                mod.main(df)
                print(f"[{step_name}] done")
                continue
            else:
                df = mod.main(df)
            print(f"[{step_name}] ok — {len(df)} rows")
        except NotImplementedError as e:
            print(f"[{step_name}] STUB — skipping ({e})")
            break

    print("Pipeline run complete (stubs skipped).")


if __name__ == "__main__":
    run()
