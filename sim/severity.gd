## Severity tiers for diagnostics.
##
## ERROR blocks the power-on commit: the switch will not close until every ERROR is
## cleared. WARNING lets power flow but tells you the build is wrong. INFO is advisory.
class_name Severity
extends RefCounted

enum Level { INFO, WARNING, ERROR }

const LABEL := {
	Level.INFO: "INFO",
	Level.WARNING: "WARNING",
	Level.ERROR: "ERROR",
}

## Sort weight so the worst finding surfaces first in the HUD and the report.
static func rank(level: int) -> int:
	return 3 - level
