import markdown
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
md_path = os.path.join(script_dir, 'อธิบายโค้ดทุกบรรทัด-UP-BUS.md')
html_path = os.path.join(script_dir, 'อธิบายโค้ดทุกบรรทัด-UP-BUS.html')

with open(md_path, 'r', encoding='utf-8') as f:
    md_content = f.read()

html_body = markdown.markdown(md_content, extensions=['tables', 'fenced_code', 'codehilite', 'toc'])

full_html = f"""<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UP BUS - Line-by-Line Code Explanation</title>
<link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;600;700&display=swap" rel="stylesheet">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: 'Sarabun', 'Segoe UI', sans-serif;
    font-size: 14px;
    line-height: 1.7;
    color: #2d2d2d;
    background: #f5f0ff;
    padding: 20px;
  }}
  .container {{
    max-width: 900px;
    margin: 0 auto;
    background: #fff;
    border-radius: 16px;
    padding: 40px;
    box-shadow: 0 4px 30px rgba(128,0,128,0.08);
  }}
  h1 {{
    font-size: 2em;
    color: #6a1b9a;
    border-bottom: 3px solid #ce93d8;
    padding-bottom: 12px;
    margin: 30px 0 20px;
  }}
  h2 {{
    font-size: 1.4em;
    color: #7b1fa2;
    margin: 25px 0 12px;
    padding: 8px 12px;
    background: linear-gradient(90deg, #f3e5f5, transparent);
    border-left: 4px solid #9c27b0;
    border-radius: 4px;
  }}
  h3 {{
    font-size: 1.15em;
    color: #8e24aa;
    margin: 18px 0 8px;
  }}
  p {{ margin: 8px 0; }}
  ul, ol {{ margin: 8px 0 8px 24px; }}
  li {{ margin: 4px 0; }}
  table {{
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
    font-size: 13px;
  }}
  th {{
    background: #9c27b0;
    color: #fff;
    padding: 8px 12px;
    text-align: left;
    font-weight: 600;
  }}
  td {{
    border: 1px solid #e0d0ee;
    padding: 6px 12px;
  }}
  tr:nth-child(even) {{ background: #faf5ff; }}
  code {{
    background: #f3e5f5;
    padding: 2px 6px;
    border-radius: 4px;
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 13px;
    color: #6a1b9a;
  }}
  pre {{
    background: #1e1e2e;
    color: #cdd6f4;
    padding: 16px;
    border-radius: 10px;
    overflow-x: auto;
    font-size: 13px;
    line-height: 1.5;
    margin: 12px 0;
  }}
  pre code {{
    background: none;
    color: inherit;
    padding: 0;
  }}
  hr {{
    border: none;
    border-top: 2px dashed #ce93d8;
    margin: 30px 0;
  }}
  strong {{ color: #6a1b9a; }}
  em {{ color: #7b1fa2; }}
  blockquote {{
    border-left: 4px solid #ce93d8;
    background: #faf5ff;
    padding: 12px 16px;
    margin: 12px 0;
    border-radius: 0 8px 8px 0;
  }}
  @media print {{
    body {{ background: #fff; padding: 0; font-size: 11px; }}
    .container {{ box-shadow: none; padding: 10px; border-radius: 0; }}
    h1 {{ font-size: 1.5em; page-break-after: avoid; }}
    h2 {{ font-size: 1.2em; page-break-after: avoid; }}
    pre {{ font-size: 10px; page-break-inside: avoid; }}
    table {{ page-break-inside: avoid; }}
    hr {{ page-break-before: always; border: none; }}
  }}
</style>
</head>
<body>
<div class="container">
{html_body}
</div>
</body>
</html>"""

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(full_html)

print(f"[OK] Created HTML: {html_path}")
print(f"[OK] Open in browser and press Ctrl+P to save as PDF")
