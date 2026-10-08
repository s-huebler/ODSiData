#!/usr/bin/env python3
"""Take screenshots of the taxonomy ring visualization."""

import os
from pathlib import Path
from playwright.sync_api import sync_playwright

HTML_PATH = Path(__file__).resolve().parent.parent.parent / "output" / "gvhd_taxonomy_ring.html"
SCREENSHOTS_DIR = Path(__file__).resolve().parent / "screenshots"
SCREENSHOTS_DIR.mkdir(exist_ok=True)

URL = "file://" + str(HTML_PATH)
VIEWPORT = {"width": 1600, "height": 900}

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport=VIEWPORT)
    page.goto(URL, wait_until="networkidle")
    page.wait_for_timeout(2500)  # Let D3 finish drawing

    # 1. Default phylum view
    page.screenshot(path=str(SCREENSHOTS_DIR / "1_phylum.png"))
    print("Saved 1_phylum.png")

    # 2. Switch to genus level
    page.evaluate("document.querySelector('[value=genus]').click()")
    page.wait_for_timeout(2500)
    page.screenshot(path=str(SCREENSHOTS_DIR / "2_genus.png"))
    print("Saved 2_genus.png")

    # 3. Switch back to phylum; uncheck all evidence except murine
    page.evaluate("document.querySelector('[value=phylum]').click()")
    page.wait_for_timeout(1500)
    # Uncheck all evidence checkboxes first
    page.evaluate("""
        document.querySelectorAll('#evidence-filters input[type=checkbox]').forEach(function(c) {
            c.checked = false;
            c.dispatchEvent(new Event('change', {bubbles: true}));
        });
    """)
    page.wait_for_timeout(300)
    # Check only murine
    page.evaluate("""
        var cbs = document.querySelectorAll('#evidence-filters input[type=checkbox]');
        cbs.forEach(function(c) {
            if (c.dataset.ev && c.dataset.ev.toLowerCase().includes('murine')) {
                c.checked = true;
                c.dispatchEvent(new Event('change', {bubbles: true}));
            }
        });
    """)
    page.wait_for_timeout(1500)
    page.screenshot(path=str(SCREENSHOTS_DIR / "3_murine.png"))
    print("Saved 3_murine.png")

    # 4. Reset to phylum, click Clostridia
    page.evaluate("""
        document.querySelectorAll('#evidence-filters input[type=checkbox]').forEach(function(c) {
            c.checked = true;
            c.dispatchEvent(new Event('change', {bubbles: true}));
        });
    """)
    page.wait_for_timeout(500)
    page.evaluate("document.querySelector('[value=class]').click()")
    page.wait_for_timeout(2000)
    # Use the window helper to click Clostridia group
    result = page.evaluate("window._clickNode('Clostridia')")
    page.wait_for_timeout(1000)
    page.screenshot(path=str(SCREENSHOTS_DIR / "4_clostridia.png"))
    print(f"Saved 4_clostridia.png (clickNode found: {result})")

    browser.close()

print("All screenshots done.")
