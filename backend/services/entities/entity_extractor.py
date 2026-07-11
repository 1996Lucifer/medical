import re
from typing import Dict, Any

class EntityExtractor:
    """
    Extracts entities (Patient Name, MRN, Staff Name, Equipment ID, Camera Name, Date, etc.)
    from the user's message using Regex and NLP heuristics. No LLM used here.
    
    TODO: Integrate GLiNER for more advanced lightweight Named Entity Recognition.
    """
    
    def __init__(self):
        # Basic patterns for common entity types
        self.patterns = {
            # Matches "Patient John", "name is John", or "John's latest report" (allows optional words like 'latest' or 'medical')
            "Patient Name": r"(?i)\b(?:patient|name is)\s+([a-zA-Z0-9'.-]+(?:\s+[a-zA-Z0-9'.-]+)?)\b|\b([a-zA-Z0-9.-]+(?:\s+[a-zA-Z0-9.-]+)?)'s\s+(?:[a-zA-Z]+\s+)*(?:report|history|record|file)",
            "MRN": r"(?i)\b(?:mrn|id)\s*[:#-]?\s*([A-Z0-9]+)\b",
            "Equipment ID": r"(?i)\b(?:equipment|wheelchair|ventilator)\s*#?\s*([A-Z0-9-]+)\b",
            "Camera Name": r"(?i)\b(?:camera|cctv)\s+([a-zA-Z0-9\s]+)\b",
            "Staff Name": r"(?i)\b(?:staff|dr|doctor|nurse)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b",
            # Very basic date matching (YYYY-MM-DD or DD/MM/YYYY)
            "Date": r"\b(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\b"
        }

    def extract_entities(self, text: str) -> Dict[str, Any]:
        """
        Parses text and extracts a dictionary of known entities.
        """
        entities = {}
        
        # Simple regex extractions
        for entity_type, pattern in self.patterns.items():
            match = re.search(pattern, text)
            if match:
                # Handle regex OR groups (returns first non-None group)
                groups = [g for g in match.groups() if g is not None]
                if groups:
                    val = groups[0].strip()
                    # Clean up trailing 's if it got captured
                    if val.endswith("'s"):
                        val = val[:-2]
                    entities[entity_type] = val

        # Catch-all named entity fallback (just grab any capitalized word sequence as a potential 'name')
        if "Patient Name" not in entities and "Staff Name" not in entities:
            # Naive: try to find anything looking like a proper noun next to keywords
            pass
            
        # Example specific heuristics
        if "today" in text.lower():
            entities["Timeframe"] = "today"
        elif "yesterday" in text.lower():
            entities["Timeframe"] = "yesterday"
            
        return entities

entity_extractor = EntityExtractor()
