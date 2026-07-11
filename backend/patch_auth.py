import sys
with open("routers/auth.py", "r") as f:
    content = f.read()

content = content.replace("except jwt.PyJWTError:", """except jwt.PyJWTError as e:
        print(f"DEBUG AUTH: PyJWTError = {e}")""")
content = content.replace("if user is None:\n        raise credentials_exception", """if user is None:
        print(f"DEBUG AUTH: user not found: {username}")
        raise credentials_exception""")

with open("routers/auth.py", "w") as f:
    f.write(content)
