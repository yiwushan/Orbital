#!/usr/bin/env python3
"""
Lightweight presence detector for Orbital.

Protocol (stdout, line-based):
  STATUS <text>
  EVENT PERSON 1
  EVENT PERSON 0
  ERROR <text>
"""

import argparse
import importlib.util
import os
import subprocess
import sys
import time


def emit(message: str) -> None:
    print(message, flush=True)


def has_cv2() -> bool:
    return importlib.util.find_spec("cv2") is not None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Orbital presence detector")
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--sample-ms", type=int, default=900)
    parser.add_argument("--required-hits", type=int, default=2)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--libcamera-index", type=int, default=1)
    parser.add_argument("--motion-threshold", type=float, default=12.0)
    return parser.parse_args()


def capture_with_cam(camera_index: int, path: str) -> bool:
    cmd = [
        "cam",
        f"-c{camera_index}",
        "-C1",
        f"--file={path}",
        "--stream=role=viewfinder,width=640,height=480,pixelformat=RGB888",
    ]
    try:
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=6,
        )
        return os.path.exists(path) and os.path.getsize(path) > 0
    except Exception:
        return False


def run_cv2_mode(args: argparse.Namespace) -> int:
    sample_s = max(0.2, args.sample_ms / 1000.0)
    required_hits = max(1, args.required_hits)

    import cv2  # pylint: disable=import-error,import-outside-toplevel

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        return 3

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, max(160, args.width))
    cap.set(cv2.CAP_PROP_FPS, 10)

    cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    face_cascade = cv2.CascadeClassifier(cascade_path)
    if face_cascade.empty():
        emit("ERROR cascade_load_failed")
        cap.release()
        return 4

    emit("STATUS ready(cv2-face)")
    person_on = False
    hit_count = 0
    frame_count = 0

    try:
        while True:
            ok, frame = cap.read()
            if not ok or frame is None:
                emit("STATUS frame_read_failed")
                time.sleep(sample_s)
                continue

            if frame.shape[1] > args.width:
                ratio = float(args.width) / float(frame.shape[1])
                new_h = max(120, int(frame.shape[0] * ratio))
                frame = cv2.resize(frame, (args.width, new_h), interpolation=cv2.INTER_AREA)

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = face_cascade.detectMultiScale(
                gray,
                scaleFactor=1.12,
                minNeighbors=5,
                minSize=(36, 36),
            )

            detected_now = len(faces) > 0
            if detected_now:
                hit_count += 1
            else:
                hit_count = 0

            person_detected = hit_count >= required_hits
            if person_detected != person_on:
                person_on = person_detected
                emit(f"EVENT PERSON {1 if person_on else 0}")

            frame_count += 1
            if frame_count % 60 == 0:
                emit("STATUS watching(cv2-face)")

            time.sleep(sample_s)
    except KeyboardInterrupt:
        pass
    finally:
        cap.release()

    return 0


def run_cam_motion_fallback(args: argparse.Namespace) -> int:
    sample_s = max(0.8, args.sample_ms / 1000.0)
    required_hits = max(1, args.required_hits)
    threshold = max(1.0, args.motion_threshold)
    tmp_path = "/tmp/orbital_presence_frame.bin"
    prev_sample = None
    person_on = False
    hit_count = 0
    frame_count = 0

    emit("STATUS fallback(cam-motion)")

    try:
        while True:
            ok = capture_with_cam(args.libcamera_index, tmp_path)
            if not ok:
                emit("STATUS cam_capture_failed")
                time.sleep(sample_s)
                continue

            with open(tmp_path, "rb") as f:
                data = f.read()

            if not data:
                emit("STATUS empty_frame")
                time.sleep(sample_s)
                continue

            # Downsample bytes directly for a cheap motion score on raw buffers.
            sample = data[::128]
            if prev_sample is None:
                prev_sample = sample
                time.sleep(sample_s)
                continue

            size = min(len(sample), len(prev_sample))
            if size == 0:
                time.sleep(sample_s)
                continue

            diff_sum = 0
            for i in range(size):
                diff_sum += abs(sample[i] - prev_sample[i])

            motion_score = diff_sum / size
            prev_sample = sample

            detected_now = motion_score >= threshold
            if detected_now:
                hit_count += 1
            else:
                hit_count = 0

            person_detected = hit_count >= required_hits
            if person_detected != person_on:
                person_on = person_detected
                emit(f"EVENT PERSON {1 if person_on else 0}")

            frame_count += 1
            if frame_count % 20 == 0:
                emit("STATUS watching(cam-motion)")

            time.sleep(sample_s)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    return 0


def main() -> int:
    args = parse_args()

    if not has_cv2():
        emit("ERROR cv2_missing (install python3-opencv)")
        return 2

    rc = run_cv2_mode(args)
    if rc == 3:
        emit(f"STATUS cv2_open_failed ({args.device}), fallback_to_cam")
        return run_cam_motion_fallback(args)
    return rc


if __name__ == "__main__":
    sys.exit(main())
