import re
from typing import Any, Dict, List, Optional

_CHART_KEYWORDS = re.compile(
    r"\b(chart|graph|pie chart|bar chart|graphical form|graphical|plot|visuali[sz]e)\b",
    re.IGNORECASE,
)
_PIE_KEYWORDS = re.compile(r"\bpie\b", re.IGNORECASE)

# Preferred label columns, in priority order, when several string columns
# are available (e.g. a raw table row has both a name and a status string).
_LABEL_COLUMN_PRIORITY = [
    "staff_name", "patient_name", "name", "camera_name", "equipment_id",
    "equipment_type", "username",
]


def wants_chart(message: str) -> bool:
    return bool(_CHART_KEYWORDS.search(message))


def _pick_label_column(sample: Dict[str, Any]) -> Optional[str]:
    for preferred in _LABEL_COLUMN_PRIORITY:
        if preferred in sample and isinstance(sample[preferred], str):
            return preferred
    for k, v in sample.items():
        if isinstance(v, str):
            return k
    return None


def _pick_numeric_column(sample: Dict[str, Any], exclude: Optional[str]) -> Optional[str]:
    for k, v in sample.items():
        if k == exclude:
            continue
        if isinstance(v, bool):
            continue
        # Surrogate/foreign keys (id, staff_id, camera_id, ...) are numeric
        # but meaningless as a chart value - skip them so the group-by-count
        # fallback below runs instead of charting raw row ids.
        if k == "id" or k.endswith("_id"):
            continue
        if isinstance(v, (int, float)):
            return k
    return None


def build_chart_spec(rows: List[Dict[str, Any]], message: str) -> Optional[Dict[str, Any]]:
    """
    Builds a chart spec directly from real SQL rows - deliberately not from
    anything the LLM generated, so the numbers shown can't be hallucinated.
    Only returns a spec when the shape of the data actually supports one;
    the caller falls back to the normal table/text response otherwise.
    """
    if not rows or not wants_chart(message):
        return None

    sample = rows[0]
    label_col = _pick_label_column(sample)
    if label_col is None:
        return None

    # Only trust an explicit numeric column when the data actually looks
    # aggregated (one row per distinct label - e.g. a GROUP BY/count query).
    # Otherwise this is a raw table of individual records (e.g. one row per
    # attendance clock-in, with the same staff_name repeated many times),
    # and any numeric column on it (a per-event confidence score, a
    # latitude, an event id) is incidental, not a meaningful chart value -
    # using it would chart nonsense (one slice per row instead of per staff).
    label_values = [row.get(label_col) for row in rows if row.get(label_col) is not None]
    is_aggregated = bool(label_values) and len(set(label_values)) == len(label_values)

    value_col = _pick_numeric_column(sample, exclude=label_col) if is_aggregated else None

    if value_col:
        # An explicit numeric column exists (e.g. an aggregate query already
        # returned a count/amount/percentage) - use it directly.
        labels: List[str] = []
        values: List[float] = []
        for row in rows[:25]:
            label = row.get(label_col)
            value = row.get(value_col)
            if label is None or value is None:
                continue
            try:
                values.append(float(value))
            except (TypeError, ValueError):
                continue
            labels.append(str(label))
        title = value_col.replace("_", " ").title()
    else:
        # No numeric column (a raw table of individual records, e.g. one row
        # per attendance clock-in) - group by the label column and count
        # occurrences, which is the natural chart for "how many X per Y".
        counts: Dict[str, int] = {}
        for row in rows:
            label = row.get(label_col)
            if label is None:
                continue
            key = str(label)
            counts[key] = counts.get(key, 0) + 1
        labels = list(counts.keys())[:25]
        values = [float(counts[l]) for l in labels]
        title = f"Count by {label_col.replace('_', ' ').title()}"

    if not labels or not values or len(labels) != len(values):
        return None

    chart_type = "pie" if _PIE_KEYWORDS.search(message) else "bar"
    return {
        "type": chart_type,
        "title": title,
        "labels": labels,
        "values": values,
    }
