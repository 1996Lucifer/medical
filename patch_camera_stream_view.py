import re

with open("flutter_source/lib/camera/camera_stream_view.dart", "r") as f:
    code = f.read()

code = code.replace("super.initState();", "super.initState();\n    print('CameraStreamView INIT: ${widget.cameraId}');")
code = code.replace("super.dispose();", "print('CameraStreamView DISPOSE: ${widget.cameraId}');\n    super.dispose();")

with open("flutter_source/lib/camera/camera_stream_view.dart", "w") as f:
    f.write(code)
