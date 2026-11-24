"""List audio blobs not yet mirrored (missing or wrong size) -> work/remaining.txt (paths relative to the storage root)."""
import os
from pathlib import Path
root = Path(__file__).resolve().parent.parent
todo, have, size_left = [], 0, 0
for l in open(root / "work" / "blob_sizes.tsv"):
    key, size = l.split("\t"); size = int(size)
    rel = "%s/%s/%s" % (key[0:2], key[2:4], key)
    try:
        ok = os.path.getsize(root / "audio" / rel) == size
    except OSError:
        ok = False
    if ok: have += 1
    else: todo.append(rel); size_left += size
open(root / "work" / "remaining.txt", "w", newline="\n").write("\n".join(todo) + ("\n" if todo else ""))
print("complete %d, remaining %d files, %.1f GB" % (have, len(todo), size_left / 1e9))
