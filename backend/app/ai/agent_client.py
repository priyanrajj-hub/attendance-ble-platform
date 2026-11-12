import logging
from typing import Optional, Dict, Any
import httpx
from app.config import settings

logger = logging.getLogger(__name__)


class AttendancePolicyEngine:
    """
    Deterministic rule-based policy engine for institutional attendance regulations.
    Used as an authoritative verification oracle and offline fallback.
    """

    MINIMUM_ATTENDANCE_PCT: float = 75.0
    CONDONATION_MINIMUM_PCT: float = 65.0

    @classmethod
    def calculate_margin(cls, attended: int, total: int) -> Dict[str, Any]:
        """
        Calculates safe skips or required attendance to hit 75%.
        """
        if total <= 0:
            return {
                "attended": attended,
                "total": total,
                "percentage": 100.0,
                "status": "Good Standing",
                "safe_skips": 0,
                "classes_needed": 0,
            }

        pct = (attended / total) * 100.0

        if pct >= cls.MINIMUM_ATTENDANCE_PCT:
            # How many more can we miss before falling below 75%?
            # (attended) / (total + x) >= 0.75  =>  0.75 * total + 0.75x <= attended
            # x <= (attended - 0.75 * total) / 0.75
            safe_skips = int((attended - 0.75 * total) / 0.75)
            return {
                "attended": attended,
                "total": total,
                "percentage": round(pct, 2),
                "status": "Safe",
                "safe_skips": max(0, safe_skips),
                "classes_needed": 0,
            }
        else:
            # How many consecutive classes needed to reach 75%?
            # (attended + y) / (total + y) >= 0.75  =>  attended + y >= 0.75 * total + 0.75y
            # 0.25y >= 0.75 * total - attended  =>  y >= (0.75 * total - attended) / 0.25
            classes_needed = int(-(-(0.75 * total - attended) // 0.25))  # Ceiling division
            condonable = pct >= cls.CONDONATION_MINIMUM_PCT
            return {
                "attended": attended,
                "total": total,
                "percentage": round(pct, 2),
                "status": "Shortage - Condonation Eligible" if condonable else "Critical Shortage (FA Risk)",
                "safe_skips": 0,
                "classes_needed": max(0, classes_needed),
            }

    @classmethod
    def answer_faq(cls, question: str) -> Optional[str]:
        q = question.lower()
        if "minimum" in q or "required" in q or "75" in q:
            return (
                "Under Amrita institutional attendance policy, a minimum of 75% attendance is required "
                "in each registered course to be eligible to sit for the end-semester examinations."
            )
        if "condonation" in q or "medical" in q or "65" in q:
            return (
                "Attendance between 65% and 74.9% may be condoned by the Dean / Campus Director on valid medical "
                "grounds or official institutional duty, provided an authentic medical certificate or duty leave "
                "form is submitted within 3 working days of returning to campus."
            )
        if "fa" in q or "failed attendance" in q or "below 65" in q:
            return (
                "Students with attendance below 65% are awarded FA (Failed due to Attendance Shortage) grade. "
                "They are not permitted to take the end-semester exam and must re-register for the course."
            )
        if "grievance" in q or "dispute" in q or "wrong" in q or "proxy" in q:
            return (
                "If an attendance session recorded you as absent or disputed due to Bluetooth packet mismatch, "
                "submit a formal grievance through the Grievance Portal within 48 hours for faculty review."
            )
        return None


class AIAgentClient:
    """
    Client connecting to Hugging Face Inference API for `priyanrajj/attendanceagent`.
    Falls back to deterministic institutional policy engine when offline or unconfigured.
    """

    def __init__(self):
        self.model_id = settings.HUGGINGFACE_MODEL_ID
        self.bucket_id = settings.HUGGINGFACE_BUCKET_ID
        self.api_token = settings.HUGGINGFACE_API_TOKEN
        self.api_url = settings.HUGGINGFACE_API_URL

    async def query(self, prompt: str, user_role: str = "student", context: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Executes a policy or grievance query.
        """
        # If API token is provided, attempt Hugging Face Inference API call
        if self.api_token and self.api_token.strip():
            headers = {"Authorization": f"Bearer {self.api_token}"}
            payload = {
                "inputs": prompt,
                "parameters": {
                    "max_new_tokens": 256,
                    "temperature": 0.2,
                    "return_full_text": False,
                },
            }
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    response = await client.post(self.api_url, headers=headers, json=payload)
                    if response.status_code == 200:
                        data = response.json()
                        text_output = (
                            data[0].get("generated_text", "")
                            if isinstance(data, list) and len(data) > 0
                            else str(data)
                        )
                        return {
                            "query": prompt,
                            "response": text_output,
                            "source": "huggingface_inference_api",
                            "model": self.model_id,
                            "bucket": self.bucket_id,
                        }
                    else:
                        logger.warning(
                            "HF Inference API returned status %s: %s",
                            response.status_code,
                            response.text,
                        )
            except Exception as e:
                logger.warning("HF Inference API request failed: %s", e)

        # Authoritative deterministic institutional fallback
        faq_answer = AttendancePolicyEngine.answer_faq(prompt)
        if faq_answer:
            response_text = faq_answer
        else:
            response_text = (
                f"Amrita Institutional Attendance Policy: 75% minimum required for all courses. "
                f"Condonation permitted down to 65% with Dean approval and medical certificates. "
                f"Regarding '{prompt}': Please consult your course instructor or student affairs coordinator."
            )

        calc_result = None
        if context and "attended" in context and "total" in context:
            calc_result = AttendancePolicyEngine.calculate_margin(
                int(context["attended"]), int(context["total"])
            )

        return {
            "query": prompt,
            "response": response_text,
            "source": "amrita_policy_engine_v1",
            "model": self.model_id,
            "bucket": self.bucket_id,
            "calculation": calc_result,
        }


ai_agent_client = AIAgentClient()
