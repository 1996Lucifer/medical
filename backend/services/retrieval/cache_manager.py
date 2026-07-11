class CacheManager:
    """
    Optional Cache layer (Redis or in-memory) for frequently accessed items.
    Currently implements a simple in-memory cache to prevent redundant SQL queries.
    """
    def __init__(self):
        self._cache = {}

    def get(self, key: str):
        return self._cache.get(key)

    def set(self, key: str, value: any):
        self._cache[key] = value

    def invalidate(self, key: str):
        if key in self._cache:
            del self._cache[key]

cache_manager = CacheManager()
