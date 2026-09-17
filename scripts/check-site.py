"""Check local assets, fragment targets and release metadata before publishing."""
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, "Duplicate HTML id"
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])
        if tag == "script" and "src" in attrs:
            self.scripts.append(attrs["src"])

page = Page()
page.feed((root / "docs/index.html").read_text())
for link in page.links:
    url = urlparse(link)
    if url.scheme:
        assert url.scheme == "https", link
    elif url.path:
        assert (root / "docs" / url.path).exists(), link
    elif url.fragment:
        assert url.fragment in page.ids, link
assert page.scripts == ["preview.js"], "Unexpected script dependency"
assert "https://www.paypal.com/donate/?hosted_button_id=7RDCBR3QXXEMJ" in page.links
for path in ("docs/PERFORMANCE.md", "PRIVACY.md", "docs/releases/0.1.0-beta.2.md"):
    assert (root / path).is_file(), path
print("Website assets, links and release documents validated.")
