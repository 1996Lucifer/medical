import multiprocessing as mp
def worker(q):
    try:
        from camera.vision_service_mediapipe import VisionServiceMediapipe
        import mediapipe
        q.put("SUCCESS")
    except Exception as e:
        q.put(f"ERROR: {type(e).__name__}: {e}")

if __name__ == "__main__":
    q = mp.Queue()
    p = mp.Process(target=worker, args=(q,))
    p.start()
    print(q.get())
    p.join()
