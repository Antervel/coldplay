from fastapi import FastAPI
from pydantic import BaseModel
from detoxify import Detoxify
from transformers import pipeline

app = FastAPI()

# ---- Load models once ----

detox_model = Detoxify("original")

sexual_model = pipeline(
    "text-classification",
    model="michellejieli/NSFW_text_classifier",
    return_all_scores=True
)

# ---- Request schema ----

class TextRequest(BaseModel):
    text: str

# ---- Helpers ----

def to_python_types(obj):
    if isinstance(obj, dict):
        return {k: to_python_types(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [to_python_types(v) for v in obj]
    elif hasattr(obj, "item"):  # catches numpy scalars
        return obj.item()
    else:
        return obj

def extract_nsfw_score(predictions):
    # Case A: [[{...}, {...}]]
    if isinstance(predictions, list) and len(predictions) > 0:
        if isinstance(predictions[0], list):
            predictions = predictions[0]

        # Case B: [{label, score}]
        if isinstance(predictions[0], dict):
            scores = {p["label"].lower(): p["score"] for p in predictions}
            return scores.get("nsfw", 0.0)

        # Case C: ["NSFW"]
        if isinstance(predictions[0], str):
            return 1.0 if predictions[0].lower() == "nsfw" else 0.0

    # Fallback
    return 0.0

# ---- Routes ----

@app.get("/")
def health():
    return {"status": "ok"}

@app.post("/score")
def score_text(request: TextRequest):
    text = request.text

    # Detoxify
    detox = detox_model.predict(text)

    # Sexual classifier
    sexual_preds = sexual_model(text)[0]
    sexual_score = extract_nsfw_score(sexual_preds)

    response = {
        "input": text,
        "sexual": sexual_preds,
        "detoxify": detox
    }

    return to_python_types(response)
