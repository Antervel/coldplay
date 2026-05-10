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
    elif hasattr(obj, "item"):  # numpy scalars
        return obj.item()
    else:
        return obj


def extract_nsfw_score(predictions):
    if isinstance(predictions, list) and len(predictions) > 0:
        if isinstance(predictions[0], list):
            predictions = predictions[0]

        if isinstance(predictions[0], dict):
            scores = {p["label"].lower(): p["score"] for p in predictions}
            return scores.get("nsfw", 0.0)

        if isinstance(predictions[0], str):
            return 1.0 if predictions[0].lower() == "nsfw" else 0.0

    return 0.0


# ---- Chunking logic ----

def chunk_text(text, tokenizer, max_len=None, stride=50):
    if max_len is None:
        max_len = tokenizer.model_max_length

    # Reserve space for special tokens
    effective_max_len = max_len - 2

    tokens = tokenizer.encode(text, add_special_tokens=False)

    chunks = []
    step = effective_max_len - stride

    for i in range(0, len(tokens), step):
        chunk_tokens = tokens[i:i + effective_max_len]
        chunk = tokenizer.decode(chunk_tokens)
        chunks.append(chunk)

    return chunks


# ---- Classification helpers ----

def classify_sexual(text):
    tokenizer = sexual_model.tokenizer
    chunks = chunk_text(text, tokenizer)

    scores = []
    for chunk in chunks:
        preds = sexual_model(chunk)[0]
        score = extract_nsfw_score(preds)
        scores.append(score)

    return max(scores) if scores else 0.0


def classify_detox(text):
    tokenizer = sexual_model.tokenizer  # reuse tokenizer safely
    chunks = chunk_text(text, tokenizer)

    aggregated = {}

    for chunk in chunks:
        preds = detox_model.predict(chunk)
        for k, v in preds.items():
            aggregated.setdefault(k, []).append(v)

    # Max aggregation per label
    return {k: max(vs) for k, vs in aggregated.items()}


# ---- Routes ----

@app.get("/")
def health():
    return {"status": "ok"}


@app.post("/score")
def score_text(request: TextRequest):
    text = request.text

    sexual_score = classify_sexual(text)
    detox = classify_detox(text)

    response = {
        "input": text,
        "sexual_score": sexual_score,
        "detoxify": detox
    }

    return to_python_types(response)
