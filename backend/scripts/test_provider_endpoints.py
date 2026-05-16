"""
Quick smoke-test: validate that each provider's test endpoint
exists and returns the right error code for an invalid key.

Run from backend/: python scripts/test_provider_endpoints.py
"""
import asyncio
import httpx

DUMMY_KEY = "INVALID_KEY_FOR_TESTING_12345"


async def check(name: str, method: str, url: str, **kwargs) -> None:
    async with httpx.AsyncClient(timeout=12.0) as client:
        try:
            fn = client.get if method == "GET" else client.post
            resp = await fn(url, **kwargs)
            status = resp.status_code
            ok = status in (200, 400, 401, 403, 422)  # all acceptable — NOT 404/000
            mark = "✅" if ok else "❌"
            note = ""
            if status == 200:
                note = "(valid key accepted)"
            elif status == 400:
                note = "(bad key rejected correctly — Google uses 400 not 401)"
            elif status == 401:
                note = "(bad key rejected correctly)"
            elif status == 403:
                note = "(forbidden — plan restriction, key format OK)"
            elif status == 422:
                note = "(unprocessable — key accepted, bad params)"
            elif status == 404:
                note = "⚠️  ENDPOINT NOT FOUND — URL is wrong!"
            print(f"{mark}  {name:<15} HTTP {status}  {note}")
        except httpx.ConnectError as e:
            print(f"❌  {name:<15} CONNECTION ERROR — {e}")
        except Exception as e:
            print(f"❌  {name:<15} EXCEPTION — {e}")


async def main():
    print("=" * 60)
    print("Provider Endpoint Smoke-Test (dummy key)")
    print("=" * 60)

    await asyncio.gather(
        # AI providers — all use GET /models with Bearer token
        check("Groq",
              "GET",
              "https://api.groq.com/openai/v1/models",
              headers={"Authorization": f"Bearer {DUMMY_KEY}"}),

        check("OpenAI",
              "GET",
              "https://api.openai.com/v1/models",
              headers={"Authorization": f"Bearer {DUMMY_KEY}"}),

        check("Gemini",
              "GET",
              "https://generativelanguage.googleapis.com/v1beta/models",
              params={"key": DUMMY_KEY}),

        # Search providers
        check("Hunter",
              "GET",
              "https://api.hunter.io/v2/account",
              params={"api_key": DUMMY_KEY}),

        check("Apollo",
              "POST",
              "https://api.apollo.io/api/v1/mixed_people/search",
              json={"api_key": DUMMY_KEY, "per_page": 1},
              headers={"Content-Type": "application/json"}),

        check("RocketReach",
              "GET",
              "https://api.rocketreach.co/v2/api/account",
              headers={"Api-Key": DUMMY_KEY}),
    )
    print("=" * 60)
    print("Ollama skipped (local only — needs server running)")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(main())
