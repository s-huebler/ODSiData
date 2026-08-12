#!/usr/bin/env python3
"""Utilities for maintaining a LaTeX taxon-tooltip dictionary.

The script is intentionally dependency-free and works directly with the
``taxa-dictionary.tex`` structure used in this project.

Main commands
-------------

``audit``
    Check that every named taxon command used by a summary is defined, that
    no generic rank wrappers remain, and that dictionary commands refer to
    valid lineage macros.

``inventory``
    Print a machine-readable inventory of lineage and display commands.

``merge``
    Add an alternative value to one rank in an existing lineage. Existing
    and new alternatives are joined with the literal text `` or `` and are
    de-duplicated.

``apply``
    Apply a JSON update specification. It can merge rank alternatives, add
    new lineage macros, and add new display/abbreviation commands.

The code does not decide taxonomy. Taxonomic interpretation must be made from
an article, its stated taxonomy database/version, and any explicitly allowed
external references. The script only makes the resulting edits reproducible.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


IDENT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]*$")
RANK_WRAPPERS = {"Phylum", "Class", "Order", "Family", "Genus", "Species"}
BASE_TAX_COMMANDS = {
    "taxPhylum",
    "taxClass",
    "taxOrder",
    "taxFamily",
    "taxGenus",
    "taxSpecies",
    "taxonTooltip",
}


class TaxaToolError(RuntimeError):
    """Raised for malformed input or unsafe requested edits."""


@dataclass(frozen=True)
class MacroDefinition:
    name: str
    kind: str
    start: int
    end: int
    body_open: int
    body_close: int

    @property
    def body_slice(self) -> slice:
        return slice(self.body_open + 1, self.body_close)


@dataclass
class AuditReport:
    errors: list[str]
    warnings: list[str]
    notes: list[str]

    @property
    def ok(self) -> bool:
        return not self.errors


_DEFINITION_RE = re.compile(
    r"\\(?P<kind>newcommand|DeclareRobustCommand)\s*"
    r"\{\\(?P<name>[A-Za-z@][A-Za-z0-9@]*)\}\s*\{",
    re.MULTILINE,
)


def _is_escaped(text: str, index: int) -> bool:
    """Return True when the character at *index* is escaped by backslashes."""
    backslashes = 0
    i = index - 1
    while i >= 0 and text[i] == "\\":
        backslashes += 1
        i -= 1
    return backslashes % 2 == 1


def _find_matching_brace(text: str, opening_index: int) -> int:
    if opening_index >= len(text) or text[opening_index] != "{":
        raise TaxaToolError("Internal parser error: expected an opening brace.")

    depth = 0
    for i in range(opening_index, len(text)):
        char = text[i]
        if _is_escaped(text, i):
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return i
            if depth < 0:
                break
    raise TaxaToolError(f"Unbalanced braces beginning at character {opening_index}.")


def parse_definitions(text: str) -> list[MacroDefinition]:
    definitions: list[MacroDefinition] = []
    for match in _DEFINITION_RE.finditer(text):
        body_open = match.end() - 1
        body_close = _find_matching_brace(text, body_open)
        definitions.append(
            MacroDefinition(
                name=match.group("name"),
                kind=match.group("kind"),
                start=match.start(),
                end=body_close + 1,
                body_open=body_open,
                body_close=body_close,
            )
        )
    return definitions


def definitions_by_name(text: str) -> dict[str, list[MacroDefinition]]:
    result: dict[str, list[MacroDefinition]] = {}
    for definition in parse_definitions(text):
        result.setdefault(definition.name, []).append(definition)
    return result


def get_unique_definition(text: str, name: str) -> MacroDefinition:
    matches = definitions_by_name(text).get(name, [])
    if not matches:
        raise TaxaToolError(f"Macro \\{name} is not defined.")
    if len(matches) > 1:
        raise TaxaToolError(f"Macro \\{name} is defined {len(matches)} times.")
    return matches[0]


def _normalise_macro_name(name: str) -> str:
    return name[1:] if name.startswith("\\") else name


def _split_or_values(value: str) -> list[str]:
    return [part.strip() for part in re.split(r"\s+or\s+", value.strip()) if part.strip()]


def merge_rank_value(text: str, lineage_name: str, rank: str, new_value: str) -> tuple[str, bool, str]:
    """Merge *new_value* into an existing rank line of a lineage macro."""
    lineage_name = _normalise_macro_name(lineage_name)
    if not lineage_name.startswith("taxLine"):
        raise TaxaToolError("Lineage macro names must begin with 'taxLine'.")
    if not rank.strip() or not new_value.strip():
        raise TaxaToolError("Rank and value must both be non-empty.")

    definition = get_unique_definition(text, lineage_name)
    body = text[definition.body_slice]

    pattern = re.compile(
        rf"(?m)^(?P<indent>[ \t]*){re.escape(rank)}:\s*"
        rf"(?P<value>.*?)(?P<suffix>\\textCR)?(?P<percent>%[ \t]*)$"
    )
    match = pattern.search(body)
    if not match:
        raise TaxaToolError(
            f"Rank '{rank}' is not present in lineage macro \\{lineage_name}. "
            "Add the rank explicitly rather than guessing an insertion position."
        )

    old_value = match.group("value").strip()
    merged: list[str] = []
    seen: set[str] = set()
    for candidate in [*_split_or_values(old_value), *_split_or_values(new_value)]:
        key = candidate.casefold()
        if key not in seen:
            seen.add(key)
            merged.append(candidate)

    merged_value = " or ".join(merged)
    if merged_value == old_value:
        return text, False, old_value

    replacement = (
        f"{match.group('indent')}{rank}: {merged_value}"
        f"{match.group('suffix') or ''}{match.group('percent')}"
    )
    new_body = body[: match.start()] + replacement + body[match.end() :]
    new_text = text[: definition.body_open + 1] + new_body + text[definition.body_close :]
    return new_text, True, merged_value


def _validate_identifier(value: str, label: str) -> None:
    if not IDENT_RE.fullmatch(value):
        raise TaxaToolError(
            f"Invalid {label} '{value}'. Use only ASCII letters and digits, starting with a letter."
        )


def _normalise_lineage_name(value: str) -> str:
    value = _normalise_macro_name(value)
    if not value.startswith("taxLine"):
        value = f"taxLine{value}"
    _validate_identifier(value, "lineage macro name")
    return value


def _normalise_command_name(value: str) -> str:
    value = _normalise_macro_name(value)
    if not value.startswith("tax"):
        value = f"tax{value}"
    _validate_identifier(value, "taxon command name")
    return value


def _coerce_rank_items(raw: Any) -> list[tuple[str, str]]:
    if isinstance(raw, dict):
        return [(str(k), str(v)) for k, v in raw.items()]
    if isinstance(raw, list):
        items: list[tuple[str, str]] = []
        for item in raw:
            if isinstance(item, dict) and "rank" in item and "value" in item:
                items.append((str(item["rank"]), str(item["value"])))
            elif isinstance(item, list) and len(item) == 2:
                items.append((str(item[0]), str(item[1])))
            else:
                raise TaxaToolError(
                    "Each lineage rank must be {'rank': ..., 'value': ...} or [rank, value]."
                )
        return items
    raise TaxaToolError("A lineage 'ranks' value must be an object or a list.")


def render_lineage(lineage_name: str, ranks: Iterable[tuple[str, str]]) -> str:
    lineage_name = _normalise_lineage_name(lineage_name)
    rank_items = [(rank.strip(), value.strip()) for rank, value in ranks]
    if not rank_items:
        raise TaxaToolError(f"New lineage \\{lineage_name} has no ranks.")
    for rank, value in rank_items:
        if not rank or not value:
            raise TaxaToolError(f"New lineage \\{lineage_name} has an empty rank or value.")
        if "\n" in rank or "\r" in rank or "\n" in value or "\r" in value:
            raise TaxaToolError("Rank labels and values must be single-line strings.")

    lines = [f"\\newcommand{{\\{lineage_name}}}{{%"]
    for index, (rank, value) in enumerate(rank_items):
        suffix = r"\textCR%" if index < len(rank_items) - 1 else "%"
        lines.append(f"{rank}: {value}{suffix}")
    lines.append("}")
    return "\n".join(lines)


def render_display_command(spec: dict[str, Any]) -> str:
    try:
        command_name = _normalise_command_name(str(spec["name"]))
        rank = str(spec["rank"]).strip()
        display_tex = str(spec["display_tex"]).strip()
        bookmark_text = str(spec["bookmark_text"]).strip()
        lineage_name = _normalise_lineage_name(str(spec["lineage"]))
    except KeyError as exc:
        raise TaxaToolError(f"Command specification is missing required key: {exc.args[0]}") from exc

    if rank not in RANK_WRAPPERS:
        raise TaxaToolError(
            f"Command \\{command_name} has unsupported rank '{rank}'. "
            f"Choose one of: {', '.join(sorted(RANK_WRAPPERS))}."
        )
    if not display_tex or not bookmark_text:
        raise TaxaToolError(f"Command \\{command_name} has empty display or bookmark text.")

    return (
        f"\\DeclareRobustCommand{{\\{command_name}}}{{%\n"
        f"  \\taxonTooltip{{\\tax{rank}{{{display_tex}}}}}"
        f"{{{bookmark_text}}}{{\\{lineage_name}}}\\xspace}}"
    )


def _insert_before_marker(text: str, marker: str, block: str) -> str:
    index = text.find(marker)
    if index < 0:
        raise TaxaToolError(f"Could not find insertion marker: {marker!r}")
    prefix = text[:index]
    suffix = text[index:]
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    return prefix + block.rstrip() + "\n\n" + suffix


def apply_update_spec(text: str, spec: dict[str, Any], *, allow_command_replace: bool = False) -> tuple[str, list[str]]:
    log: list[str] = []

    for update in spec.get("lineage_updates", []):
        if not isinstance(update, dict):
            raise TaxaToolError("Each lineage_updates item must be an object.")
        try:
            lineage = str(update["lineage"])
            rank = str(update["rank"])
            value = str(update["value"])
        except KeyError as exc:
            raise TaxaToolError(
                f"A lineage update is missing required key: {exc.args[0]}"
            ) from exc
        text, changed, merged = merge_rank_value(text, lineage, rank, value)
        action = "merged" if changed else "already present"
        log.append(f"{action}: \\{_normalise_macro_name(lineage)} / {rank} = {merged}")

    lineage_marker = (
        "% --------------------------------------------------------------------------\n"
        "% Named manuscript commands"
    )

    for lineage_spec in spec.get("lineages", []):
        if not isinstance(lineage_spec, dict):
            raise TaxaToolError("Each lineages item must be an object.")
        if "name" not in lineage_spec or "ranks" not in lineage_spec:
            raise TaxaToolError("Each new lineage requires 'name' and 'ranks'.")
        lineage_name = _normalise_lineage_name(str(lineage_spec["name"]))
        rank_items = _coerce_rank_items(lineage_spec["ranks"])
        existing = definitions_by_name(text).get(lineage_name, [])
        if existing:
            if len(existing) > 1:
                raise TaxaToolError(f"Cannot update duplicate lineage \\{lineage_name}.")
            for rank, value in rank_items:
                text, changed, merged = merge_rank_value(text, lineage_name, rank, value)
                action = "merged" if changed else "already present"
                log.append(f"{action}: \\{lineage_name} / {rank} = {merged}")
        else:
            block = render_lineage(lineage_name, rank_items)
            text = _insert_before_marker(text, lineage_marker, block)
            log.append(f"added lineage: \\{lineage_name}")

    added_commands: list[str] = []
    for command_spec in spec.get("commands", []):
        if not isinstance(command_spec, dict):
            raise TaxaToolError("Each commands item must be an object.")
        command_name = _normalise_command_name(str(command_spec.get("name", "")))
        rendered = render_display_command(command_spec)
        existing = definitions_by_name(text).get(command_name, [])
        if existing:
            if len(existing) > 1:
                raise TaxaToolError(f"Cannot update duplicate command \\{command_name}.")
            definition = existing[0]
            old = text[definition.start : definition.end].strip()
            if old == rendered.strip():
                log.append(f"already present: \\{command_name}")
                continue
            if not allow_command_replace:
                raise TaxaToolError(
                    f"Command \\{command_name} already exists with different content. "
                    "Review it manually or rerun with --allow-command-replace."
                )
            text = text[: definition.start] + rendered + text[definition.end :]
            log.append(f"replaced command: \\{command_name}")
        else:
            added_commands.append(rendered)
            log.append(f"added command: \\{command_name}")

    if added_commands:
        section = (
            "\n\n% --------------------------------------------------------------------------\n"
            "% Commands added by taxa_dictionary_tools.py\n"
            "% --------------------------------------------------------------------------\n"
            + "\n\n".join(added_commands)
            + "\n"
        )
        text = text.rstrip() + section

    return text, log


def _command_rank(body: str) -> str | None:
    match = re.search(r"\\tax(Phylum|Class|Order|Family|Genus|Species)\{", body)
    return match.group(1) if match else None


def _lineage_references(body: str) -> set[str]:
    return set(re.findall(r"\\(taxLine[A-Za-z0-9@]+)", body))


def parse_lineage_ranks(body: str) -> list[dict[str, str]]:
    ranks: list[dict[str, str]] = []
    line_re = re.compile(
        r"(?m)^[ \t]*(?P<rank>[A-Za-z][A-Za-z0-9 /-]*):\s*"
        r"(?P<value>.*?)(?:\\textCR)?%[ \t]*$"
    )
    for match in line_re.finditer(body):
        ranks.append({"rank": match.group("rank"), "value": match.group("value").strip()})
    return ranks


def build_inventory(text: str) -> dict[str, Any]:
    definitions = parse_definitions(text)
    lineages: list[dict[str, Any]] = []
    commands: list[dict[str, Any]] = []

    for definition in definitions:
        body = text[definition.body_slice]
        if definition.name.startswith("taxLine"):
            lineages.append(
                {
                    "name": definition.name,
                    "ranks": parse_lineage_ranks(body),
                }
            )
        elif definition.name.startswith("tax") and definition.name not in BASE_TAX_COMMANDS:
            commands.append(
                {
                    "name": definition.name,
                    "kind": definition.kind,
                    "rank": _command_rank(body),
                    "lineages": sorted(_lineage_references(body)),
                    "body": body.strip(),
                }
            )

    return {
        "lineages": sorted(lineages, key=lambda item: item["name"].casefold()),
        "commands": sorted(commands, key=lambda item: item["name"].casefold()),
    }


def audit_dictionary(dictionary_text: str, summary_text: str | None = None) -> AuditReport:
    errors: list[str] = []
    warnings: list[str] = []
    notes: list[str] = []

    grouped = definitions_by_name(dictionary_text)
    for name, definitions in sorted(grouped.items()):
        if len(definitions) > 1:
            errors.append(f"Macro \\{name} is defined {len(definitions)} times.")

    lineage_names = {name for name in grouped if name.startswith("taxLine")}
    named_commands = {
        name
        for name in grouped
        if name.startswith("tax")
        and not name.startswith("taxLine")
        and name not in BASE_TAX_COMMANDS
    }

    for command_name in sorted(named_commands):
        definition = grouped[command_name][0]
        body = dictionary_text[definition.body_slice]
        references = _lineage_references(body)
        if not references:
            errors.append(f"Named command \\{command_name} does not reference a lineage macro.")
        for reference in sorted(references):
            if reference not in lineage_names:
                errors.append(
                    f"Named command \\{command_name} references undefined lineage \\{reference}."
                )

        rank = _command_rank(body)
        if rank is None:
            errors.append(f"Named command \\{command_name} has no taxonomic rank wrapper.")
        elif rank in {"Genus", "Species"} and r"\textit{" not in body:
            errors.append(
                f"Named command \\{command_name} is {rank.lower()}-level but has no \\textit{{...}}."
            )
        if r"\xspace" not in body:
            warnings.append(f"Named command \\{command_name} does not end with \\xspace.")
        if r"\taxonTooltip" not in body:
            errors.append(f"Named command \\{command_name} does not use \\taxonTooltip.")

    for lineage_name in sorted(lineage_names):
        definition = grouped[lineage_name][0]
        body = dictionary_text[definition.body_slice]
        ranks = parse_lineage_ranks(body)
        if not ranks:
            errors.append(f"Lineage macro \\{lineage_name} contains no parseable rank lines.")
        seen_ranks: set[str] = set()
        for item in ranks:
            rank = item["rank"]
            if rank in seen_ranks:
                errors.append(f"Lineage macro \\{lineage_name} repeats rank '{rank}'.")
            seen_ranks.add(rank)
            options = _split_or_values(item["value"])
            if len(options) != len({option.casefold() for option in options}):
                warnings.append(
                    f"Lineage macro \\{lineage_name}, rank '{rank}', contains duplicate 'or' options."
                )

    notes.append(f"Dictionary contains {len(lineage_names)} lineage macros and {len(named_commands)} named commands.")

    if summary_text is not None:
        used = set(re.findall(r"\\(tax[A-Za-z0-9@]+)", summary_text))
        generic_used = sorted(used & BASE_TAX_COMMANDS)
        if generic_used:
            warnings.append(
                "Summary still uses generic taxonomic wrappers: "
                + ", ".join(f"\\{name}" for name in generic_used)
                + ". Replace taxon mentions with named dictionary commands."
            )

        named_used = {
            name
            for name in used
            if name not in BASE_TAX_COMMANDS and not name.startswith("taxLine")
        }
        undefined = sorted(named_used - named_commands)
        for name in undefined:
            errors.append(f"Summary uses undefined named taxon command \\{name}.")

        direct_lineage_use = sorted(name for name in used if name.startswith("taxLine"))
        for name in direct_lineage_use:
            errors.append(f"Summary directly uses internal lineage macro \\{name}.")

        notes.append(f"Summary uses {len(named_used)} distinct named taxon commands.")

    return AuditReport(errors=errors, warnings=warnings, notes=notes)


def print_audit(report: AuditReport) -> None:
    for note in report.notes:
        print(f"NOTE: {note}")
    for warning in report.warnings:
        print(f"WARNING: {warning}")
    for error in report.errors:
        print(f"ERROR: {error}")
    if report.ok:
        print("PASS: no audit errors found.")
    else:
        print(f"FAIL: {len(report.errors)} audit error(s) found.")


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise TaxaToolError(f"File not found: {path}") from exc


def _write_text(path: Path, text: str, *, backup: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup and path.exists():
        backup_path = path.with_suffix(path.suffix + ".bak")
        shutil.copy2(path, backup_path)
        print(f"Backup written: {backup_path}")
    path.write_text(text, encoding="utf-8")


def _output_path(input_path: Path, output: str | None, in_place: bool) -> Path:
    if in_place and output:
        raise TaxaToolError("Choose either --in-place or --output, not both.")
    if in_place:
        return input_path
    if output:
        return Path(output)
    raise TaxaToolError("Specify --output PATH or --in-place.")


def command_audit(args: argparse.Namespace) -> int:
    dictionary = _read_text(Path(args.dictionary))
    summary = _read_text(Path(args.summary)) if args.summary else None
    report = audit_dictionary(dictionary, summary)
    print_audit(report)
    if report.errors or (args.strict and report.warnings):
        return 1
    return 0


def command_inventory(args: argparse.Namespace) -> int:
    dictionary = _read_text(Path(args.dictionary))
    inventory = build_inventory(dictionary)
    json.dump(inventory, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def command_merge(args: argparse.Namespace) -> int:
    input_path = Path(args.dictionary)
    output_path = _output_path(input_path, args.output, args.in_place)
    text = _read_text(input_path)
    updated, changed, merged = merge_rank_value(text, args.lineage, args.rank, args.value)
    _write_text(output_path, updated, backup=args.in_place and not args.no_backup)
    status = "updated" if changed else "unchanged"
    print(f"{status}: \\{_normalise_macro_name(args.lineage)} / {args.rank} = {merged}")
    print(f"Written: {output_path}")
    return 0


def command_apply(args: argparse.Namespace) -> int:
    input_path = Path(args.dictionary)
    output_path = _output_path(input_path, args.output, args.in_place)
    text = _read_text(input_path)
    try:
        spec = json.loads(_read_text(Path(args.spec)))
    except json.JSONDecodeError as exc:
        raise TaxaToolError(f"Invalid JSON update specification: {exc}") from exc
    if not isinstance(spec, dict):
        raise TaxaToolError("The top-level update specification must be a JSON object.")

    updated, log = apply_update_spec(
        text,
        spec,
        allow_command_replace=args.allow_command_replace,
    )
    report = audit_dictionary(updated)
    if report.errors:
        print_audit(report)
        raise TaxaToolError("Refusing to write an updated dictionary that fails the audit.")

    _write_text(output_path, updated, backup=args.in_place and not args.no_backup)
    for item in log:
        print(item)
    print(f"Written: {output_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Audit and update a LaTeX taxon-tooltip dictionary."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit = subparsers.add_parser("audit", help="Audit a dictionary and optional summary.")
    audit.add_argument("--dictionary", required=True, help="Path to taxa-dictionary.tex")
    audit.add_argument("--summary", help="Path to a LaTeX summary/section to audit")
    audit.add_argument(
        "--strict",
        action="store_true",
        help="Return a non-zero exit code for warnings as well as errors",
    )
    audit.set_defaults(func=command_audit)

    inventory = subparsers.add_parser("inventory", help="Print dictionary inventory as JSON.")
    inventory.add_argument("--dictionary", required=True, help="Path to taxa-dictionary.tex")
    inventory.set_defaults(func=command_inventory)

    merge = subparsers.add_parser(
        "merge",
        help="Merge one alternative into an existing lineage rank using ' or '.",
    )
    merge.add_argument("--dictionary", required=True, help="Input taxa-dictionary.tex")
    merge.add_argument("--lineage", required=True, help="Lineage macro, e.g. taxLineFaecalibacterium")
    merge.add_argument("--rank", required=True, help="Rank label exactly as written, e.g. Order")
    merge.add_argument("--value", required=True, help="New alternative value")
    merge.add_argument("--output", help="Write to a new file")
    merge.add_argument("--in-place", action="store_true", help="Modify the input file")
    merge.add_argument(
        "--no-backup",
        action="store_true",
        help="With --in-place, do not create a .bak copy",
    )
    merge.set_defaults(func=command_merge)

    apply_cmd = subparsers.add_parser("apply", help="Apply a JSON update specification.")
    apply_cmd.add_argument("--dictionary", required=True, help="Input taxa-dictionary.tex")
    apply_cmd.add_argument("--spec", required=True, help="JSON update specification")
    apply_cmd.add_argument("--output", help="Write to a new file")
    apply_cmd.add_argument("--in-place", action="store_true", help="Modify the input file")
    apply_cmd.add_argument(
        "--allow-command-replace",
        action="store_true",
        help="Permit replacement of an existing named command with different content",
    )
    apply_cmd.add_argument(
        "--no-backup",
        action="store_true",
        help="With --in-place, do not create a .bak copy",
    )
    apply_cmd.set_defaults(func=command_apply)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except TaxaToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
