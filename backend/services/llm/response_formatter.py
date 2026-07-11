class ResponseFormatter:
    """
    Formats the final output for the API response.
    """
    def format_direct_sql_response(self, rows: list) -> str:
        """Formats raw SQL rows when an LLM isn't necessary."""
        if not rows:
            return "No records found."
        
        # Simple markdown table formatter
        keys = list(rows[0].keys())
        header = "| " + " | ".join(keys) + " |"
        separator = "|" + "|".join(["---"] * len(keys)) + "|"
        
        body = []
        for row in rows:
            row_vals = [str(row.get(k, "")) for k in keys]
            body.append("| " + " | ".join(row_vals) + " |")
            
        return "\n".join([header, separator] + body)

response_formatter = ResponseFormatter()
