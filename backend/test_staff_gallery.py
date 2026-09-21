"""Regression test for the face-recognition gallery construction in
routers/staff.py's load_staff_list().

Bug (found via /investigate 2026-09-14): load_staff_list() emitted one
gallery row PER ENROLLMENT PHOTO instead of one row per staff member - a
staff member with 5 enrolled photos contributed 5 separate rows to
VisionServiceZones.staff_embeddings_matrix, all labeled with their name.
Since a live match is decided by the single highest-scoring row across the
WHOLE gallery (np.argmax), more rows per identity means more independent
"attempts" for a random face to score high against that identity by
chance - inflating the effective false-accept rate without any code bug in
the matching threshold itself. Two different real people were both scoring
65-66% against a single identity that had 5 enrollment-photo rows in the
live gallery.

Fix: average every enrolled photo's embedding into ONE canonical,
re-normalized embedding per staff member (_average_normalized), so the
gallery always has exactly one row per identity regardless of how many
photos they enrolled.
"""
import numpy as np

from routers.staff import _average_normalized


class _FakePhoto:
    def __init__(self, embedding, upper_embedding=None):
        self.embedding = embedding
        self.upper_embedding = upper_embedding


class _FakeStaff:
    def __init__(self, id, name, embedding=None, upper_embedding=None, photos=None):
        self.id = id
        self.name = name
        self.embedding = embedding
        self.upper_embedding = upper_embedding
        self.photos = photos or []


def test_average_normalized_collapses_multiple_vectors_to_one_unit_vector():
    rng = np.random.default_rng(0)
    vectors = [rng.normal(size=512).astype(np.float32) * scale for scale in (1.0, 2.5, 0.3)]

    result = _average_normalized(vectors)

    assert result is not None
    assert result.shape == (512,)
    assert abs(np.linalg.norm(result) - 1.0) < 1e-5, "result must be re-normalized to a unit vector"


def test_average_normalized_returns_none_for_empty_input():
    assert _average_normalized([]) is None


def test_load_staff_list_emits_exactly_one_row_per_staff_member(monkeypatch):
    """The actual regression: with several enrolled photos, the gallery
    must still have exactly one row per staff member - not one per photo."""
    import routers.staff as staff_module

    rng = np.random.default_rng(1)
    five_photos = [_FakePhoto(rng.normal(size=512).astype(np.float32)) for _ in range(5)]
    eight_photos = [_FakePhoto(rng.normal(size=512).astype(np.float32)) for _ in range(8)]

    fake_staff = [
        _FakeStaff(id=2, name="Dr. Deepak", embedding=None, photos=five_photos),
        _FakeStaff(id=4, name="Anamika", embedding=None, photos=eight_photos),
    ]

    class _FakeQuery:
        def all(self):
            return fake_staff

    class _FakeDB:
        def query(self, model):
            return _FakeQuery()

    result = staff_module.load_staff_list(_FakeDB())

    assert len(result) == 2, (
        f"expected exactly 1 gallery row per staff member (2 total), got "
        f"{len(result)} - the one-row-per-photo bug is back"
    )
    ids = {entry["id"] for entry in result}
    assert ids == {2, 4}
    for entry in result:
        assert len(entry["embedding"]) == 512
