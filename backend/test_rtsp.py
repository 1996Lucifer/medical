import urllib.parse
import asyncio
import time

async def check_rtsp(url):
    try:
        parsed = urllib.parse.urlparse(url)
        host = parsed.hostname
        port = parsed.port or 554
        print(f"Checking {host}:{port}")
        
        fut = asyncio.open_connection(host, port)
        reader, writer = await asyncio.wait_for(fut, timeout=2.0)
        writer.close()
        await writer.wait_closed()
        return "online"
    except Exception as e:
        return f"offline: {e}"

async def main():
    print(await check_rtsp("rtsp://DevTest:MaaGanga$123@192.168.1.27:554/stream1"))

asyncio.run(main())
