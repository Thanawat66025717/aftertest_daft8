import markdown
import os

md_path = os.path.join(os.path.dirname(__file__), 'รายละเอียดโค้ดทั้งหมด-UP-BUS.md')
html_path = os.path.join(os.path.dirname(__file__), 'รายละเอียดโค้ดทั้งหมด-UP-BUS.html')

with open(md_path, 'r', encoding='utf-8') as f:
    md_text = f.read()

html_body = markdown.markdown(md_text, extensions=['tables', 'fenced_code', 'codehilite', 'toc'])

html_full = f"""<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="UTF-8">
<title>รายละเอียดโค้ดทั้งหมด UP BUS</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;600;700&family=Fira+Code:wght@400;500&display=swap');

  * {{ margin: 0; padding: 0; box-sizing: border-box; }}

  body {{
    font-family: 'Sarabun', sans-serif;
    font-size: 13px;
    line-height: 1.7;
    color: #1a1a2e;
    background: #fff;
    padding: 30px 40px;
    max-width: 900px;
    margin: 0 auto;
  }}

  h1 {{
    font-size: 22px;
    font-weight: 700;
    color: #6c3483;
    border-bottom: 3px solid #6c3483;
    padding-bottom: 8px;
    margin: 25px 0 15px 0;
    page-break-after: avoid;
  }}

  h2 {{
    font-size: 17px;
    font-weight: 700;
    color: #2c3e50;
    border-bottom: 2px solid #d5d8dc;
    padding-bottom: 5px;
    margin: 22px 0 10px 0;
    page-break-after: avoid;
  }}

  h3 {{
    font-size: 14px;
    font-weight: 600;
    color: #7d3c98;
    margin: 15px 0 8px 0;
    page-break-after: avoid;
  }}

  h4 {{
    font-size: 13px;
    font-weight: 600;
    color: #2980b9;
    margin: 10px 0 5px 0;
  }}

  p {{
    margin: 6px 0;
    text-align: justify;
  }}

  strong {{
    color: #2c3e50;
  }}

  ul, ol {{
    margin: 5px 0 5px 20px;
  }}

  li {{
    margin: 3px 0;
  }}

  table {{
    width: 100%;
    border-collapse: collapse;
    margin: 10px 0;
    font-size: 12px;
    page-break-inside: avoid;
  }}

  th {{
    background: #6c3483;
    color: white;
    font-weight: 600;
    padding: 6px 10px;
    text-align: left;
    border: 1px solid #5b2c6f;
  }}

  td {{
    padding: 5px 10px;
    border: 1px solid #d5d8dc;
    vertical-align: top;
  }}

  tr:nth-child(even) {{
    background: #f8f4fc;
  }}

  tr:hover {{
    background: #eee4f5;
  }}

  code {{
    font-family: 'Fira Code', monospace;
    font-size: 11.5px;
    background: #f0ecf5;
    padding: 1px 5px;
    border-radius: 3px;
    color: #6c3483;
  }}

  pre {{
    background: #2d2d3f;
    color: #e0e0e0;
    padding: 12px 15px;
    border-radius: 6px;
    overflow-x: auto;
    margin: 8px 0;
    font-size: 11px;
    line-height: 1.5;
    page-break-inside: avoid;
  }}

  pre code {{
    background: none;
    color: #e0e0e0;
    padding: 0;
  }}

  hr {{
    border: none;
    border-top: 1px solid #d5d8dc;
    margin: 18px 0;
  }}

  blockquote {{
    border-left: 3px solid #7d3c98;
    background: #f8f4fc;
    padding: 8px 15px;
    margin: 8px 0;
    font-size: 12px;
    color: #555;
    border-radius: 0 5px 5px 0;
  }}

  /* Print styles */
  @media print {{
    body {{
      padding: 15px 20px;
      font-size: 11px;
    }}
    h1 {{ font-size: 18px; margin: 15px 0 10px 0; }}
    h2 {{ font-size: 14px; margin: 15px 0 8px 0; }}
    h3 {{ font-size: 12px; }}
    table {{ font-size: 10px; }}
    pre {{ font-size: 9.5px; padding: 8px 10px; }}
    code {{ font-size: 10px; }}
    blockquote {{ font-size: 10.5px; }}

    h1, h2, h3 {{ page-break-after: avoid; }}
    table, pre, blockquote {{ page-break-inside: avoid; }}
    tr {{ page-break-inside: avoid; }}
  }}

  /* Page header for print */
  @page {{
    margin: 1.5cm;
    @top-center {{
      content: "UP BUS — รายละเอียดโค้ดทั้งหมด";
      font-size: 9px;
      color: #999;
    }}
  }}
</style>
</head>
<body>
{html_body}
<footer style="margin-top:30px; padding-top:10px; border-top:2px solid #6c3483; text-align:center; color:#999; font-size:11px;">
  📋 เอกสารสร้างอัตโนมัติจากโปรเจกต์ UP BUS — ใช้สำหรับอ่านเตรียมสอบ
</footer>
</body>
</html>"""

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(html_full)

print(f"Done! HTML saved to: {html_path}")
print("Open in browser -> Ctrl+P -> Save as PDF")
