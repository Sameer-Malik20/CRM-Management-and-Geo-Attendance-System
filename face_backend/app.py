from __future__ import annotations

import base64
import datetime
import io
import os
from pathlib import Path
import zipfile

import cv2
import numpy as np
from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
REGISTER_FOLDER = BASE_DIR / "faces"
TEMP_FOLDER = BASE_DIR / "temp"
CASCADE_PATH = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
FACE_DETECTOR = cv2.CascadeClassifier(str(CASCADE_PATH))
RECOGNITION_CONFIDENCE_THRESHOLD = 72.0

REGISTER_FOLDER.mkdir(parents=True, exist_ok=True)
TEMP_FOLDER.mkdir(parents=True, exist_ok=True)


def _hydrate_seed_faces():
    encoded_archive = os.environ.get("FACE_BACKEND_SEED_FACES_B64", "").strip()
    if not encoded_archive:
        return

    has_existing_faces = any(
        path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png"}
        for path in REGISTER_FOLDER.iterdir()
    )
    if has_existing_faces:
        return

    archive_bytes = base64.b64decode(encoded_archive)
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        archive.extractall(REGISTER_FOLDER)


_hydrate_seed_faces()

app = Flask(__name__)


def _normalize_face_image(image):
    if image is None:
        return None

    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image

    gray = cv2.equalizeHist(gray)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    return cv2.resize(gray, (200, 200))


def _extract_face_from_array(image):
    if image is None:
        return None

    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image

    faces = FACE_DETECTOR.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=6,
        minSize=(90, 90),
    )

    if len(faces) == 0:
        return None

    x, y, w, h = max(faces, key=lambda face: face[2] * face[3])
    padding_x = int(w * 0.18)
    padding_y = int(h * 0.22)
    x1 = max(x - padding_x, 0)
    y1 = max(y - padding_y, 0)
    x2 = min(x + w + padding_x, gray.shape[1])
    y2 = min(y + h + padding_y, gray.shape[0])
    face_region = gray[y1:y2, x1:x2]
    return _normalize_face_image(face_region)


def _extract_face(image_path: Path, allow_existing_crop=False):
    image = cv2.imread(str(image_path))
    if image is None:
        return None

    face_region = _extract_face_from_array(image)
    if face_region is not None:
        return face_region

    if not allow_existing_crop:
        return None

    height, width = image.shape[:2]
    aspect_ratio = width / max(height, 1)
    if width < 120 or height < 120 or not 0.75 <= aspect_ratio <= 1.35:
        return None

    return _normalize_face_image(image)


def _load_saved_face_sample(image_path: Path):
    image = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
    if image is None:
        return None

    return _normalize_face_image(image)


def _parse_registered_face_filename(image_path: Path):
    if "__" in image_path.stem:
        parts = image_path.stem.split("__", 2)
        employee_id = parts[0]
        employee_name = parts[2] if len(parts) > 2 else employee_id
        return employee_id, employee_name

    if "_" in image_path.stem:
        return image_path.stem.split("_", 1)

    return image_path.stem, image_path.stem


def _load_training_data():
    faces = []
    labels = []
    label_map = {}
    next_label = 0

    for filename in REGISTER_FOLDER.iterdir():
        if not filename.is_file() or filename.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue

        face_region = _load_saved_face_sample(filename)
        if face_region is None:
            continue

        employee_id, employee_name = _parse_registered_face_filename(filename)
        if employee_id not in label_map:
            label_map[employee_id] = {
                "label": next_label,
                "name": employee_name,
            }
            next_label += 1

        faces.append(face_region)
        labels.append(label_map[employee_id]["label"])

    return faces, np.array(labels), label_map


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/register")
def register_face():
    if (
        "image" not in request.files
        or "name" not in request.form
        or "empId" not in request.form
    ):
        return jsonify({"error": "Missing fields"}), 400

    image = request.files["image"]
    employee_name = request.form["name"].strip()
    employee_id = request.form["empId"].strip()
    sample_key = secure_filename(request.form.get("sampleKey", "").strip())
    replace_existing = request.form.get("replaceExisting", "false").lower() == "true"

    if not employee_name or not employee_id:
        return jsonify({"error": "Name and employee ID are required"}), 400

    temp_path = TEMP_FOLDER / "register_check.jpg"
    image.save(temp_path)

    face_region = _extract_face(temp_path, allow_existing_crop=True)
    if face_region is None:
        return jsonify({"error": "No face detected in uploaded image"}), 400

    if replace_existing:
        for existing_file in REGISTER_FOLDER.glob(f"{employee_id}*"):
            if existing_file.is_file():
                existing_file.unlink()

    if not sample_key:
        sample_key = datetime.datetime.now().strftime("%Y%m%d%H%M%S%f")

    filename = (
        f"{employee_id}__{sample_key}__{secure_filename(employee_name)}.png"
    )
    save_path = REGISTER_FOLDER / filename
    cv2.imwrite(str(save_path), face_region)

    return (
        jsonify(
            {
                "message": "Face registered successfully.",
                "empId": employee_id,
                "name": employee_name,
            }
        ),
        200,
    )


@app.post("/recognize")
def recognize_face():
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400

    uploaded_image = request.files["image"]
    temp_path = TEMP_FOLDER / "verify_check.jpg"
    uploaded_image.save(temp_path)

    unknown_face = _extract_face(temp_path, allow_existing_crop=True)
    if unknown_face is None:
        return jsonify({"error": "No face detected"}), 400

    faces, labels, label_map = _load_training_data()
    if len(faces) == 0:
        return jsonify({"error": "No registered faces found"}), 400

    recognizer = cv2.face.LBPHFaceRecognizer_create()
    recognizer.train(faces, labels)

    predicted_label, confidence = recognizer.predict(unknown_face)
    matched = next(
        (
            (employee_id, payload["name"])
            for employee_id, payload in label_map.items()
            if payload["label"] == predicted_label
        ),
        None,
    )

    # Lower confidence means better match for LBPH.
    if matched and confidence <= RECOGNITION_CONFIDENCE_THRESHOLD:
        employee_id, employee_name = matched
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        return (
            jsonify(
                {
                    "status": "success",
                    "empId": employee_id,
                    "name": employee_name,
                    "timestamp": timestamp,
                    "confidence": round(float(confidence), 2),
                    "message": "Face matched. Attendance can be marked.",
                }
            ),
            200,
        )

    return jsonify({"status": "fail", "message": "No match found"}), 401

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "5050")),
        debug=os.environ.get("FLASK_DEBUG") == "1",
    )
