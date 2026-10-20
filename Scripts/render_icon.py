#!/usr/bin/env python3
"""Renders Support/AppIcon.svg to Support/AppIcon.png (1024x1024, transparent) with headless Chromium.
Needs Playwright: pip install playwright && playwright install chromium."""
import asyncio, pathlib, sys
from playwright.async_api import async_playwright

async def main(svg_path, png_path):
    svg = pathlib.Path(svg_path).read_text()
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1024, "height": 1024})
        await page.set_content(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
        await page.locator("svg").screenshot(path=png_path, omit_background=True)
        await browser.close()

asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "Support/AppIcon.svg",
                 sys.argv[2] if len(sys.argv) > 2 else "Support/AppIcon.png"))
print("rendered")
