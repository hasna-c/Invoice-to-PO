import openai
import os
import base64
import json
from flask import Flask, request, render_template
from config import OPENAI_API_KEY
 
app = Flask(__name__)
openai.api_key = OPENAI_API_KEY
 
ALLOWED_IMAGE_TYPES = {"image/png", "image/jpeg", "image/jpg"}
 
@app.route("/")
def index():
    return render_template("index.html")
 
@app.route("/extract-text", methods=["POST"])
def extract_text():
    if "image" not in request.files or "doc_type" not in request.form:
        return render_template("index.html", error="Missing file or document type")
 
    file = request.files["image"]
    doc_type = request.form["doc_type"]
 
    if file.mimetype not in ALLOWED_IMAGE_TYPES:
        return render_template("index.html", error="Invalid file type. Only PNG, JPG, and JPEG are allowed.")
 
    if doc_type not in ["invoice", "po"]:
        return render_template("index.html", error="Invalid document type. Choose either 'invoice' or 'po'.")
 
    image_bytes = file.read()
    base64_image = base64.b64encode(image_bytes).decode("utf-8")
 
    prompt = (
        f"Extract structured details from a {doc_type} and return only a JSON response. "
        "Ensure the JSON follows this format exactly: "
        "{ "
        "   'po_number': '...', "
        "   'created_on': '...', "
        "   'delivery_date': '...', "
        "   'supplier_details': {'name': '...', 'location': '...'}, "
        "   'ship_to': {'name': '...', 'phone': '...', 'address': '...'}, "
        "   'created_by': '...', "
        "   'items': [ "
        "       {'item_name': '...', 'uom': '...', 'quantity': ..., 'price': ..., 'subtotal': ..., 'tax': ..., 'total': ...} "
        "   ], "
        "   'sub_total': ..., "
        "   'tax': ..., "
        "   'total_amount': ... "
        "} "
        "DO NOT include explanations, introductions, or anything other than valid JSON output."
    )
 
    try:
        response = openai.ChatCompletion.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Extract and return structured JSON data."},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_image}"}}
                    ],
                }
            ],
        )
 
        extracted_text = response["choices"][0]["message"]["content"]
       
        # Debugging print
        print("📝 Raw Extracted Text:", extracted_text)
 
        # Cleanup AI response
        extracted_text = extracted_text.strip().replace("```json", "").replace("```", "").strip()
 
        # Convert AI response to JSON
        extracted_data = json.loads(extracted_text)
 
        # Debugging print
        print("✅ Extracted Data Structure:", type(extracted_data), extracted_data)
 
        return render_template("result.html", data=dict(extracted_data))  # ✅ Ensuring data is a dictionary
 
    except json.JSONDecodeError:
        print("❌ JSON Parsing Error! Response was:", extracted_text)
        return render_template("index.html", error="Failed to parse extracted data.")
 
    except openai.error.OpenAIError as e:
        print("🚨 OpenAI API Error:", str(e))
        return render_template("index.html", error="Failed to process the image. Please try again.")
 
if __name__ == "__main__":
    app.run(debug=True)