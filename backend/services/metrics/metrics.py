import time
from typing import Dict, Any

class MetricsTracker:
    """
    Tracks telemetry such as Latency, Tokens, Context Size, Cache Hits.
    """
    def __init__(self):
        self.logs = []

    def log_interaction(self, metric_data: Dict[str, Any]):
        """
        Expects keys like intent, tool, sql_latency, llm_latency, etc.
        """
        metric_data['timestamp'] = time.time()
        self.logs.append(metric_data)
        print(f"[Metrics] Logged: {metric_data}")
        # In a real system, this would write to the database LLMAuditLog

metrics_tracker = MetricsTracker()
