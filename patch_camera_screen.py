import re

with open("flutter_source/lib/camera/camera_screen.dart", "r") as f:
    code = f.read()

code = code.replace("_connectEventsStream();", "// _connectEventsStream();")

with open("flutter_source/lib/camera/camera_screen.dart", "w") as f:
    f.write(code)
