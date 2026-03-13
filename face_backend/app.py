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


def _extract_face(image_path: Path):
    image = cv2.imread(str(image_path))
    if image is None:
        return None

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = FACE_DETECTOR.detectMultiScale(
        gray,
        scaleFactor=1.2,
        minNeighbors=5,
        minSize=(80, 80),
    )

    if len(faces) == 0:
        return None

    x, y, w, h = max(faces, key=lambda face: face[2] * face[3])
    face_region = gray[y : y + h, x : x + w]
    return cv2.resize(face_region, (200, 200))


def _detect_faces(image_path: Path):
    image = cv2.imread(str(image_path))
    if image is None:
        return []

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = FACE_DETECTOR.detectMultiScale(
        gray,
        scaleFactor=1.2,
        minNeighbors=5,
        minSize=(80, 80),
    )

    image_height, image_width = gray.shape[:2]
    detected_faces = []
    for x, y, w, h in sorted(faces, key=lambda face: face[0])[:10]:
        face_region = gray[y : y + h, x : x + w]
        if face_region.size == 0:
            continue
        detected_faces.append(
            {
                "face": cv2.resize(face_region, (200, 200)),
                "x": round(x / image_width, 4),
                "y": round(y / image_height, 4),
                "w": round(w / image_width, 4),
                "h": round(h / image_height, 4),
            }
        )
    return detected_faces


def _load_training_data():
    faces = []
    labels = []
    label_map = {}
    next_label = 0

    for filename in REGISTER_FOLDER.iterdir():
        if not filename.is_file() or filename.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue

        face_region = _extract_face(filename)
        if face_region is None:
            continue

        employee_id, employee_name = filename.stem.split("_", 1)
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

    if not employee_name or not employee_id:
        return jsonify({"error": "Name and employee ID are required"}), 400

    temp_path = TEMP_FOLDER / "register_check.jpg"
    image.save(temp_path)

    face_region = _extract_face(temp_path)
    if face_region is None:
        return jsonify({"error": "No face detected in uploaded image"}), 400

    filename = f"{employee_id}_{secure_filename(employee_name)}.png"
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

    unknown_face = _extract_face(temp_path)
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
    if matched and confidence <= 65:
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


@app.post("/recognize-group")
def recognize_group():
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400

    expected_ids = {
        item.strip()
        for item in request.form.get("expectedEmpIds", "").split(",")
        if item.strip()
    }

    uploaded_image = request.files["image"]
    temp_path = TEMP_FOLDER / "group_verify_check.jpg"
    uploaded_image.save(temp_path)

    detected_faces = _detect_faces(temp_path)
    if len(detected_faces) == 0:
        return jsonify({"error": "No face detected"}), 400

    faces, labels, label_map = _load_training_data()
    if len(faces) == 0:
        return jsonify({"error": "No registered faces found"}), 400

    recognizer = cv2.face.LBPHFaceRecognizer_create()
    recognizer.train(faces, labels)

    matches = []
    for detected_face in detected_faces:
        predicted_label, confidence = recognizer.predict(detected_face["face"])
        matched = next(
            (
                (employee_id, payload["name"])
                for employee_id, payload in label_map.items()
                if payload["label"] == predicted_label
            ),
            None,
        )

        if not matched or confidence > 65:
            continue

        employee_id, employee_name = matched
        if expected_ids and employee_id not in expected_ids:
            continue

        matches.append(
            {
                "empId": employee_id,
                "name": employee_name,
                "confidence": round(float(confidence), 2),
                "x": detected_face["x"],
                "y": detected_face["y"],
                "w": detected_face["w"],
                "h": detected_face["h"],
            }
        )

    if len(matches) == 0:
        return jsonify({"status": "fail", "message": "No expected face matched", "matches": []}), 401

    return (
        jsonify(
            {
                "status": "success",
                "message": f"{len(matches)} faces matched successfully.",
                "matches": matches,
            }
        ),
        200,
    )


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "5050")),
        debug=os.environ.get("FLASK_DEBUG") == "1",
    )
