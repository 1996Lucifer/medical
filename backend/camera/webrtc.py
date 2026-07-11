import asyncio
import fractions
import time
from aiortc import VideoStreamTrack
import av

class CameraVideoStreamTrack(VideoStreamTrack):
    """
    A video stream track that yields frames from our CameraWorker.
    Converts OpenCV numpy arrays into PyAV frames for aiortc.
    """
    def __init__(self, queue: asyncio.Queue):
        super().__init__()
        self.queue = queue
        self.last_frame = None

    async def recv(self):
        pts, time_base = await self.next_timestamp()

        try:
            # Wait for a new frame from the queue.
            # Timeout is useful to keep WebRTC alive if the stream stutters.
            frame_np = await asyncio.wait_for(self.queue.get(), timeout=1.0)
            self.last_frame = frame_np
        except asyncio.TimeoutError:
            if self.last_frame is None:
                # Keep waiting if we never got one
                frame_np = await self.queue.get()
                self.last_frame = frame_np
            else:
                # Re-send the last frame to keep the WebRTC connection stable
                frame_np = self.last_frame

        # Convert numpy array (BGR from OpenCV) into a PyAV VideoFrame
        video_frame = av.VideoFrame.from_ndarray(frame_np, format="bgr24")
        video_frame.pts = pts
        video_frame.time_base = time_base

        return video_frame
