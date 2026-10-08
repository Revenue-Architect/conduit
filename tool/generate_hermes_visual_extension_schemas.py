#!/usr/bin/env python3
"""Regenerate the app schema from the generation contract, without dependencies."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
schemas = json.loads((root / "docs/hermes-a2ui-mobile/references/extension-schemas.json").read_text())
output = root / "lib/features/hermes/widgets/hermes_visual_extension_schemas.dart"
output.write_text("// Generated from docs/hermes-a2ui-mobile/references/extension-schemas.json.\n// Keep these two representations identical.\nconst hermesVisualExtensionSchemasJson = r\"\"\"" + json.dumps(schemas, separators=(",", ":")) + "\"\"\";\n")
