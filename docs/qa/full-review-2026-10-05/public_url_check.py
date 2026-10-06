#!/usr/bin/env python3
"""Read public DaBin pages without auth; retain local HTTP and policy-parity evidence."""

from concurrent.futures import ThreadPoolExecutor
import datetime
import hashlib
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.request


EVIDENCE = Path(__file__).resolve().parent
REPOSITORY = EVIDENCE.parents[2]
POLICY = REPOSITORY / "native/Resources/PrivacyPolicy.md"
URLS = {
    "configuredPolicyPage": "https://github.com/RoeyAsterix/DaBin/blob/main/native/Resources/PrivacyPolicy.md",
    "publicPolicyMarkdown": "https://raw.githubusercontent.com/RoeyAsterix/DaBin/main/native/Resources/PrivacyPolicy.md",
    "configuredSupportPage": "https://github.com/RoeyAsterix/DaBin/issues",
}
LIMIT = 2 * 1024 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def updated_line(data):
    return next((line.strip() for line in data.decode("utf-8", errors="replace").splitlines()
                 if line.strip().startswith("Updated ")), None)


def fetch(item):
    label, url = item
    started = time.monotonic()
    evidence = {"label": label, "requestedURL": url, "requestMethod": "GET",
                "authenticated": False, "timeoutSeconds": 12}
    body = None
    request = urllib.request.Request(url, headers={"User-Agent": "DaBin-local-public-readiness-check/1.0",
                                                   "Accept": "text/plain,text/html;q=0.9"})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            body = response.read(LIMIT + 1)
            evidence.update(httpStatus=response.status, finalURL=response.url,
                            contentType=response.headers.get("Content-Type"),
                            lastModified=response.headers.get("Last-Modified"),
                            etag=response.headers.get("ETag"))
            if len(body) > LIMIT:
                raise ValueError("Public response exceeds the two-MiB evidence limit")
            evidence.update(bodyBytes=len(body), bodySHA256=digest(body), reachable=response.status == 200)
            title = re.search(r"<title[^>]*>(.*?)</title>", body.decode("utf-8", errors="replace"), re.S | re.I)
            if title:
                evidence["pageTitle"] = re.sub(r"\s+", " ", title.group(1)).strip()
    except urllib.error.HTTPError as error:
        evidence.update(httpStatus=error.code, finalURL=error.url, reachable=False,
                        errorType=type(error).__name__, error=str(error))
    except (OSError, ValueError, urllib.error.URLError) as error:
        evidence.update(reachable=False, errorType=type(error).__name__, error=str(error))
    evidence["elapsedSeconds"] = round(time.monotonic() - started, 3)
    return label, evidence, body


def main():
    now = datetime.datetime.now(datetime.timezone.utc)
    output = EVIDENCE / ("public-links-" + now.strftime("%Y%m%dT%H%M%S%fZ"))
    output.mkdir(exist_ok=False)
    before = POLICY.read_bytes()
    results = {}
    public_policy = None
    with ThreadPoolExecutor(max_workers=3) as pool:
        for label, result, body in pool.map(fetch, URLS.items()):
            results[label] = result
            if label == "publicPolicyMarkdown" and result.get("httpStatus") == 200 and body:
                if body.startswith(b"# DaBin privacy"):
                    public_policy = body
                    (output / "public-policy.md").write_bytes(body)
                    result["savedMarkdown"] = "public-policy.md"
                    result["updatedLine"] = updated_line(body)
                else:
                    result["unexpectedMarkdownContent"] = True
    after = POLICY.read_bytes()
    comparison = {"localPath": str(POLICY), "localSHA256": digest(after),
                  "localUpdatedLine": updated_line(after), "localChangedDuringFetch": before != after,
                  "publicSHA256": digest(public_policy) if public_policy else None,
                  "publicUpdatedLine": updated_line(public_policy) if public_policy else None,
                  "exactBytesMatch": public_policy == after if public_policy is not None else None,
                  "normalizedTextMatch": (public_policy.decode("utf-8").replace("\r\n", "\n") ==
                                          after.decode("utf-8").replace("\r\n", "\n"))
                                         if public_policy is not None else None}
    receipt = {"checkedAtUTC": now.isoformat(), "results": results, "policyComparison": comparison,
               "supportContactAdequacy": "Not established by HTTP reachability; owner contact review remains pending.",
               "boundary": "Read-only public unauthenticated GET requests. No private app data, uploads, publication, account changes, signing or application actions.",
               "sourceScriptSHA256": digest(Path(__file__).read_bytes())}
    receipt_path = output / "verification.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"receipt": str(receipt_path), "results": results, "policyComparison": comparison}, indent=2))
    return 0 if all(value.get("reachable") for value in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
