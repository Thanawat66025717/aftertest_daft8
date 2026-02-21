"""
สร้าง PDF อธิบายโค้ดทั้งโปรเจกต์ UP BUS
อ่าน Markdown → แปลงเป็น PDF ด้วย fpdf2 + Tahoma (Thai)
"""
import re
from fpdf import FPDF

# ===== ไฟล์ Markdown ที่จะรวม (เรียงตามลำดับ) =====
ARTIFACT_DIR = r"C:\Users\thana\.gemini\antigravity\brain\633b91cb-4db8-45f1-8f18-2e9c1110bbe5"
MD_FILES = [
    f"{ARTIFACT_DIR}\\explain_01_main.md",
    f"{ARTIFACT_DIR}\\explain_02_model.md",
    f"{ARTIFACT_DIR}\\explain_03_location_service.md",
    f"{ARTIFACT_DIR}\\explain_04_notification.md",
    f"{ARTIFACT_DIR}\\explain_06_upbus_page.md",
    f"{ARTIFACT_DIR}\\explain_07_busstop.md",
    f"{ARTIFACT_DIR}\\explain_08_route_plan.md",
    f"{ARTIFACT_DIR}\\explain_09_other_pages.md",
]

OUTPUT_PDF = r"z:\daft_ani-main\UP_BUS_Code_Explanation.pdf"


class ThaiPDF(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        # Add Tahoma font (supports Thai)
        self.add_font("Tahoma", "", r"C:\Windows\Fonts\tahoma.ttf", uni=True)
        self.add_font("Tahoma", "B", r"C:\Windows\Fonts\tahomabd.ttf", uni=True)
        self.set_auto_page_break(auto=True, margin=15)

    def header(self):
        self.set_font("Tahoma", "B", 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 6, "UP BUS - Code Explanation", align="R", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(200, 200, 200)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(3)

    def footer(self):
        self.set_y(-15)
        self.set_font("Tahoma", "", 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, f"หน้า {self.page_no()}/{{nb}}", align="C")

    def add_title_page(self):
        self.add_page()
        self.ln(60)
        self.set_font("Tahoma", "B", 28)
        self.set_text_color(100, 50, 150)
        self.cell(0, 15, "UP BUS", align="C", new_x="LMARGIN", new_y="NEXT")
        self.set_font("Tahoma", "B", 18)
        self.set_text_color(80, 80, 80)
        self.cell(0, 12, "อธิบายโค้ดทั้งโปรเจกต์", align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(5)
        self.set_font("Tahoma", "", 12)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, "ทำอะไร + ถ้าไม่มีจะเกิดอะไร ❌", align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(20)
        self.set_font("Tahoma", "", 10)
        self.set_text_color(150, 150, 150)
        self.cell(0, 8, "Auto-generated from source code", align="C", new_x="LMARGIN", new_y="NEXT")

    def write_h1(self, text):
        self.ln(4)
        self.set_font("Tahoma", "B", 16)
        self.set_text_color(100, 50, 150)
        self.multi_cell(0, 9, text, new_x="LMARGIN", new_y="NEXT")
        # underline
        self.set_draw_color(100, 50, 150)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(3)

    def write_h2(self, text):
        self.ln(3)
        self.set_font("Tahoma", "B", 13)
        self.set_text_color(50, 50, 50)
        self.multi_cell(0, 8, text, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def write_h3(self, text):
        self.ln(2)
        self.set_font("Tahoma", "B", 11)
        self.set_text_color(80, 80, 80)
        self.multi_cell(0, 7, text, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def write_text(self, text):
        self.set_font("Tahoma", "", 9)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5.5, text, new_x="LMARGIN", new_y="NEXT")

    def write_quote(self, text):
        self.set_font("Tahoma", "", 9)
        self.set_text_color(100, 100, 100)
        self.set_fill_color(245, 245, 245)
        x = self.get_x()
        self.set_x(x + 5)
        self.multi_cell(0, 5.5, text.strip("> ").strip(), new_x="LMARGIN", new_y="NEXT", fill=True)
        self.ln(1)

    def write_table(self, headers, rows):
        """Write a table with dynamic column widths"""
        avail_w = 190  # mm (A4 width - margins)
        n_cols = len(headers)

        # Calculate column widths based on content
        col_widths = []
        for i in range(n_cols):
            max_len = len(headers[i])
            for row in rows:
                if i < len(row):
                    max_len = max(max_len, len(row[i]))
            col_widths.append(max_len)

        total = sum(col_widths)
        if total > 0:
            col_widths = [max(15, (w / total) * avail_w) for w in col_widths]
            # Normalize to fit
            scale = avail_w / sum(col_widths)
            col_widths = [w * scale for w in col_widths]

        row_h = 6

        # Check if we need a page break for at least header + 2 rows
        needed = row_h * min(3, 1 + len(rows))
        if self.get_y() + needed > 270:
            self.add_page()

        # Header
        self.set_font("Tahoma", "B", 7.5)
        self.set_fill_color(100, 50, 150)
        self.set_text_color(255, 255, 255)
        for i, h in enumerate(headers):
            self.cell(col_widths[i], row_h, h, border=1, fill=True, align="C")
        self.ln(row_h)

        # Rows
        self.set_font("Tahoma", "", 7)
        self.set_text_color(40, 40, 40)
        alt = False
        for row in rows:
            # Check page break
            if self.get_y() + row_h > 275:
                self.add_page()
                # Re-draw header
                self.set_font("Tahoma", "B", 7.5)
                self.set_fill_color(100, 50, 150)
                self.set_text_color(255, 255, 255)
                for i, h in enumerate(headers):
                    self.cell(col_widths[i], row_h, h, border=1, fill=True, align="C")
                self.ln(row_h)
                self.set_font("Tahoma", "", 7)
                self.set_text_color(40, 40, 40)
                alt = False

            if alt:
                self.set_fill_color(248, 248, 255)
            else:
                self.set_fill_color(255, 255, 255)

            for i in range(n_cols):
                val = row[i] if i < len(row) else ""
                self.cell(col_widths[i], row_h, val, border=1, fill=True)
            self.ln(row_h)
            alt = not alt

        self.ln(2)

    def write_hr(self):
        self.ln(2)
        self.set_draw_color(200, 200, 200)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(3)


def parse_table(lines, start_idx):
    """Parse markdown table starting at start_idx, return (headers, rows, end_idx)"""
    headers = [h.strip() for h in lines[start_idx].strip("|").split("|")]
    # Skip separator line
    row_start = start_idx + 2
    rows = []
    i = row_start
    while i < len(lines) and "|" in lines[i] and lines[i].strip():
        cells = [c.strip() for c in lines[i].strip("|").split("|")]
        rows.append(cells)
        i += 1
    return headers, rows, i


def strip_emoji(text):
    """Remove emoji characters that Tahoma font cannot render"""
    # Remove common emoji ranges
    emoji_pattern = re.compile(
        "[\U0001F300-\U0001F9FF"  # Miscellaneous Symbols and Pictographs, Emoticons, etc.
        "\U00002702-\U000027B0"   # Dingbats
        "\U0000FE0F"              # Variation Selector
        "\u26A0\u274C\u2705\u2B50"  # Warning, Cross, Check, Star
        "]+", flags=re.UNICODE
    )
    return emoji_pattern.sub("", text)


def clean_md(text):
    """Remove markdown formatting for plain text"""
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)  # bold
    text = re.sub(r'`(.+?)`', r'\1', text)  # code
    text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)  # links
    text = strip_emoji(text)
    return text


def process_md_file(pdf, filepath):
    """Read a markdown file and render it into the PDF"""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Skip empty lines
        if not stripped:
            i += 1
            continue

        # H1
        if stripped.startswith("# "):
            pdf.add_page()
            pdf.write_h1(clean_md(stripped[2:]))
            i += 1
        # H3 (before H2 to avoid matching)
        elif stripped.startswith("### "):
            pdf.write_h3(clean_md(stripped[4:]))
            i += 1
        # H2
        elif stripped.startswith("## "):
            pdf.write_h2(clean_md(stripped[3:]))
            i += 1
        # HR
        elif stripped == "---":
            pdf.write_hr()
            i += 1
        # Table
        elif "|" in stripped and i + 1 < len(lines) and "---" in lines[i + 1]:
            headers, rows, end_i = parse_table(lines, i)
            pdf.write_table(headers, rows)
            i = end_i
        # Quote
        elif stripped.startswith(">"):
            pdf.write_quote(clean_md(stripped))
            i += 1
        # Normal text
        else:
            pdf.write_text(clean_md(stripped))
            i += 1


def main():
    pdf = ThaiPDF()
    pdf.alias_nb_pages()

    # Title page
    pdf.add_title_page()

    # Process each file
    for filepath in MD_FILES:
        print(f"Processing: {filepath.split(chr(92))[-1]}")
        process_md_file(pdf, filepath)

    # Save
    pdf.output(OUTPUT_PDF)
    print(f"\n[OK] PDF saved: {OUTPUT_PDF}")
    print(f"   Pages: {pdf.page_no()}")


if __name__ == "__main__":
    main()
