#!/usr/bin/env python3
"""Create editable concept SVGs. All names and content are fictional."""
from pathlib import Path
from html import escape

ROOT = Path(__file__).parent / "wireframes"
INK = "#302A3C"
MUTED = "#787180"
PURPLE = "#8260AB"
LINE = "#E8E2ED"
WHITE = "#FFFFFF"

ICONS = {
    "folder": '<path d="M3 6h6l2 2h10v11H3z"/>',
    "file": '<path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6M9 16h6"/>',
    "text": '<path d="M4 6h16M4 10h13M4 14h16M4 18h10"/>',
    "link": '<path d="m10 14 4-4M9 16l-1 1a3 3 0 0 1-4-4l4-4a3 3 0 0 1 4 0m3-1 1-1a3 3 0 0 1 4 4l-4 4a3 3 0 0 1-4 0"/>',
    "media": '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="8" cy="9" r="1.5"/><path d="m5 18 5-5 3 3 3-5 4 7"/>',
    "task": '<path d="m5 12 4 4L19 6"/>',
    "grid": '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    "search": '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
    "plus": '<path d="M12 4v16M4 12h16"/>',
    "down": '<path d="m7 10 5 5 5-5"/>',
    "copy": '<rect x="8" y="7" width="12" height="14" rx="2"/><path d="M15 7V3H3v14h5"/>',
    "clock": '<circle cx="12" cy="12" r="8"/><path d="M12 7v6l4 2"/>',
    "comment": '<path d="M4 4h16v12H10l-6 4zM8 8h8M8 12h5"/>',
    "close": '<path d="m6 6 12 12M6 18 18 6"/>',
    "more": '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    "calendar": '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M7 3v4M17 3v4M7 14h3M14 14h3M7 18h3"/>',
    "arrow": '<path d="M5 12h14m-5-5 5 5-5 5"/>',
    "settings": '<circle cx="12" cy="12" r="3"/><path d="m10 3 4 0 1 3 3 1 3 3 0 4-3 1-1 3-3 3h-4l-1-3-3-1-3-3v-4l3-1 1-3z"/>',
}

class Sheet:
    def __init__(self, w, h, title):
        self.w, self.h = w, h
        self.parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(title)}">', f'<title>{escape(title)}</title>', '<style>text{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif} .muted{fill:#787180}</style>']
        self.box(0, 0, w, h, "#F4F1F7", 0)
    def box(self,x,y,w,h,fill=WHITE,r=12,stroke=None):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')
    def text(self,x,y,t,size=13,color=INK,weight=400):
        self.parts.append(f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" font-weight="{weight}">{escape(t)}</text>')
    def icon(self,name,x,y,size=20,color=PURPLE):
        self.parts.append(f'<g transform="translate({x},{y}) scale({size/24})" stroke="{color}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" fill="none">{ICONS[name]}</g>')
    def line(self,x1,y1,x2,y2):
        self.parts.append(f'<path d="M{x1} {y1}H{x2}" stroke="{LINE}"/>' if y1==y2 else f'<path d="M{x1} {y1}L{x2} {y2}" stroke="{LINE}"/>')
    def pill(self,x,y,w,label,active=False):
        self.box(x,y,w,28,"#ECE4F5" if active else "#F7F5F9",8)
        self.text(x+10,y+18,label,11,PURPLE if active else MUTED,600 if active else 400)
    def row(self,y,w,title,detail,icon,selected=False,task=False):
        self.box(24,y,w,66,"#F0EAF7" if selected else WHITE,10,"#B99CCD" if selected else LINE)
        self.box(34,y+13,38,38,"#F6F2FA",8)
        self.icon(icon,43,y+22)
        self.text(83,y+26,title,13,INK,600)
        self.text(83,y+47,detail,11,MUTED)
        if task:self.icon("task",w-3,y+10,14,"#A64D58")
    def save(self,name):
        (ROOT/name).write_text("\n".join(self.parts+['</svg>'])+"\n")

def header(s,w):
    s.box(8,8,w-16,s.h-43,WHITE,18,LINE)
    # Stylized outline for the existing bin identity, intentionally low fidelity.
    s.box(23,26,20,24,"#DED0ED",5)
    s.box(25,22,16,5,"#A084BE",2)
    s.box(27,33,12,7,"#665078",3)
    s.text(51,45,"DaBin",21,INK,700)
    s.icon("settings",w-65,27,18,MUTED)
    s.icon("close",w-36,27,18,MUTED)
    s.line(24,61,w-24,61)
    for x,width,label,active in [(24,79,"Explorer",True),(107,81,"Clipboard",False),(192,61,"Shelf",False),(257,64,"Notes",False)]:
        s.pill(x,77,width,label,active)

def compact():
    s=Sheet(380,680,"DaBin Explorer compact concept. Fictional project and data. Not an app screenshot.")
    header(s,380)
    s.icon("folder",24,122)
    s.text(52,138,"Northstar",15,INK,600)
    s.icon("down",145,121,18)
    s.pill(193,118,78,"By type",True)
    s.pill(275,118,78,"By date")
    s.box(24,158,278,32,"#F7F5F9",9,LINE)
    s.icon("search",33,166,17,MUTED)
    s.text(59,179,"Search this project",12,MUTED)
    s.box(311,158,42,32,"#ECE4F5",9)
    s.icon("plus",322,164,20)
    for i,name in enumerate(["grid","text","link","file","media","task"]):
        x=28+i*55
        if i==0:s.box(x-4,203,36,32,"#ECE4F5",10)
        s.icon(name,x+4,209,20)
    s.text(24,261,"Files",12,MUTED,600)
    s.row(272,332,"Proposal.pdf","PDF · 30 Sep, 09:14","file")
    s.row(345,332,"Brand guide.pdf","PDF · 29 Sep, 16:20","file")
    s.text(24,438,"Media",12,MUTED,600)
    s.row(449,332,"Landing reference.png","Image · Follow up tomorrow","media",task=True)
    s.text(24,542,"Daily documents",12,MUTED,600)
    s.row(553,332,"30 September 2026","Captures and links · 5 entries","calendar")
    s.text(24,666,"CONCEPT · Fictional content · No permanent sidebar",10,MUTED)
    s.save("compact.svg")

def expanded():
    s=Sheet(1120,780,"DaBin Explorer expanded concept with a list and large selected image preview. Fictional data. Not an app screenshot.")
    header(s,1120)
    s.icon("folder",24,144)
    s.text(52,160,"Northstar",15,INK,600)
    s.icon("down",145,143,18)
    s.box(215,139,408,32,"#F7F5F9",9,LINE)
    s.icon("search",225,147,17,MUTED)
    s.text(251,160,"Search this project",12,MUTED)
    s.pill(646,141,74,"By type",True)
    s.pill(724,141,76,"By date")
    for i,name in enumerate(["grid","text","link","file","media","task"]):
        s.icon(name,826+i*41,147,19)
    s.line(24,184,1096,184)
    s.text(24,211,"Northstar / September 2026",12,MUTED)
    s.text(24,245,"Files",12,MUTED,600)
    s.row(257,309,"Proposal.pdf","PDF · 30 Sep, 09:14","file")
    s.row(330,309,"Brand guide.pdf","PDF · 29 Sep, 16:20","file")
    s.text(24,425,"Media",12,MUTED,600)
    s.row(437,309,"Landing reference.png","Image · 30 Sep, 10:42","media",True)
    s.text(24,532,"Daily documents",12,MUTED,600)
    s.row(544,309,"30 September 2026","Captures and links · 5 entries","calendar")
    s.line(354,199,354,712)
    s.text(380,224,"Landing reference.png",20,INK,600)
    s.text(380,247,"Image · 30 Sep 2026, 10:42 · Source: Browser",12,MUTED)
    s.icon("copy",1023,207,21)
    s.icon("more",1065,208,21)
    s.box(379,269,707,322,"#F4F1F8",14,LINE)
    # Fictional portrait-free design image, drawn as editable vector.
    s.box(450,291,564,279,WHITE,8)
    s.box(471,309,40,8,"#9278B0",3)
    s.box(878,309,49,6,"#E4DEEC",3)
    s.box(940,309,49,6,"#E4DEEC",3)
    s.text(477,380,"A calmer workday.",29,"#514164",600)
    s.text(477,410,"Make room for the next good idea.",13,MUTED)
    s.box(477,432,122,32,"#B49DCC",8)
    s.text(492,453,"Explore the project",11,WHITE,600)
    s.box(477,499,151,42,"#ECE5F5",6)
    s.box(644,499,151,42,"#E6EEEB",6)
    s.box(811,499,151,42,"#F4EBD8",6)
    s.text(380,617,"Saved file",11,MUTED,600)
    s.text(380,640,"Northstar / 2026 / 09 September / 30 Wednesday… / Media",11,INK)
    s.pill(380,655,128,"Open full details",True)
    s.pill(516,655,119,"Reveal in Finder")
    s.pill(643,655,83,"Copy path")
    s.pill(734,655,113,"Make a task")
    s.text(380,710,"Drag the selected saved file into Finder or an accepting app.",11,MUTED)
    s.text(24,763,"CONCEPT · Fictional content · Proposed split preview, native actions, and responsive sizing",11,MUTED)
    s.save("expanded.svg")

if __name__ == "__main__":
    ROOT.mkdir(exist_ok=True)
    compact()
    expanded()
