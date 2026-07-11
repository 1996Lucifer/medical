from urllib.parse import unquote

def fix_rtsp_url(url: str):
    """
    FFmpeg does NOT URL-decode passwords — decode them here so FFmpeg gets
    the raw characters. Only re-encode @ and : since those break URL parsing.
    """
    if not isinstance(url, str) or not url.startswith("rtsp://"):
        return url

    at_index = url.rfind("@")
    if at_index == -1:
        return url

    prefix = url[:at_index]   # rtsp://user:pass
    suffix = url[at_index:]   # @host:port/path
    cred_str = prefix[7:]     # strip rtsp://

    if ":" in cred_str:
        user, pwd = cred_str.split(":", 1)
        user = unquote(user)
        pwd = unquote(pwd)
        pwd = pwd.replace("@", "%40").replace(":", "%3A")
        user = user.replace("@", "%40").replace(":", "%3A")
        return f"rtsp://{user}:{pwd}{suffix}"

    return url
