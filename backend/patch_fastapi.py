import os
import site

packages = site.getsitepackages()
fastapi_deps = None
for p in packages:
    candidate = os.path.join(p, "fastapi", "dependencies", "utils.py")
    if os.path.exists(candidate):
        fastapi_deps = candidate
        break

if not fastapi_deps:
    fastapi_deps = ".venv/lib/python3.14/site-packages/fastapi/dependencies/utils.py"

with open(fastapi_deps, "r") as f:
    content = f.read()

# Fix the indentation error
content = content.replace(
"""            try:
solved = await call(**solved_result.values)
        except TypeError as e:""",
"""            try:
                solved = await call(**solved_result.values)
            except TypeError as e:"""
)

with open(fastapi_deps, "w") as f:
    f.write(content)
print("Patched indentation!")
