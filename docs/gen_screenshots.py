#!/usr/bin/env python3
"""Generate simulated UI screenshots for GuardianPlay README"""
from PIL import Image, ImageDraw
import os

SCREEN_W, SCREEN_H = 640, 480
OUT_DIR = os.path.join(os.path.dirname(__file__), "screenshots")
os.makedirs(OUT_DIR, exist_ok=True)

BG      = (18, 22, 38)
HEADER  = (35, 45, 80)
ACCENT  = (90, 160, 255)
WHITE   = (255, 255, 255)
GREY    = (140, 150, 180)
GREEN   = (80, 210, 120)
RED_C   = (230, 80, 80)
YELLOW  = (255, 200, 50)
DARK    = (12, 16, 30)
SEL_BG  = (50, 70, 130)

def make_base(title, subtitle=""):
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, SCREEN_W, 60], fill=HEADER)
    d.line([0, 60, SCREEN_W, 60], fill=ACCENT, width=2)
    d.text((20, 15), title, fill=WHITE)
    if subtitle:
        d.text((20, 40), subtitle, fill=GREY)
    d.rectangle([0, SCREEN_H - 30, SCREEN_W, SCREEN_H], fill=DARK)
    d.text((20, SCREEN_H - 22), "A: Select   B: Back   Start: Menu", fill=GREY)
    return img, d

def draw_item(d, y, text, sel=False, val=""):
    if sel:
        d.rectangle([10, y-2, SCREEN_W-10, y+24], fill=SEL_BG)
        d.line([10, y-2, 10, y+24], fill=ACCENT, width=3)
    d.text((24, y), text, fill=WHITE if sel else GREY)
    if val:
        d.text((SCREEN_W-180, y), val, fill=ACCENT if sel else GREY)

def draw_status(d, enabled, time_str):
    y = 70
    d.rectangle([10, y, SCREEN_W-10, y+30], fill=(25, 32, 56))
    sc = GREEN if enabled else RED_C
    d.text((20, y+8), "ACTIF" if enabled else "INACTIF", fill=sc)
    d.text((300, y+8), "Temps restant: " + time_str, fill=YELLOW)

# 1 — Main menu
img, d = make_base("GuardianPlay v1.0", "Controle Parental — Onion OS")
draw_status(d, True, "1h 30min")
for i, (t, s) in enumerate([("Parametres",True),("Statistiques",False),("Historique",False),("A propos",False)]):
    draw_item(d, 115+i*50, t, s)
img.save(os.path.join(OUT_DIR, "01_main_menu.png"))
print("01_main_menu.png")

# 2 — Settings
img, d = make_base("Parametres", "GuardianPlay v1.0")
draw_status(d, True, "1h 30min")
items = [("Desactiver le controle parental",True,""),("Modifier le code PIN",False,""),
         ("Ajouter du temps",False,"+10m / +1h"),("Retirer du temps",False,"-10m / -1h"),("Retour",False,"")]
for i, (t, s, v) in enumerate(items):
    draw_item(d, 115+i*48, t, s, v)
img.save(os.path.join(OUT_DIR, "02_settings.png"))
print("02_settings.png")

# 3 — PIN entry
img, d = make_base("Code PIN GuardianPlay", "Entrez votre code PIN parent")
bx0 = 180
by0 = 150
for i in range(4):
    bx = bx0 + i * 80
    col = ACCENT if i == 0 else (40, 55, 100)
    d.rectangle([bx, by0, bx+60, by0+60], fill=col, outline=WHITE, width=2)
    d.text((bx+22, by0+18), "?" if i > 0 else "*", fill=WHITE)
d.text((150, by0+80), "Chiffre 1/4  —  Appuyez sur B pour timer normal", fill=GREY)
for i, n in enumerate("0123456789"):
    nx = 90 + (i % 5)*105
    ny = by0+120 + (i//5)*58
    d.rectangle([nx, ny, nx+90, ny+46], fill=SEL_BG if n=="0" else (30,40,75), outline=(60,80,140))
    d.text((nx+32, ny+14), n, fill=WHITE)
img.save(os.path.join(OUT_DIR, "03_pin_entry.png"))
print("03_pin_entry.png")

# 4 — Statistics
img, d = make_base("Statistiques de jeu", "Temps total : 12h 34min")
draw_status(d, True, "1h 30min")
games = [("Super Mario World","3h 15min"),("Sonic the Hedgehog","2h 40min"),
         ("Pokemon Red","1h 55min"),("Zelda Link Awakening","1h 22min"),
         ("Mega Man X","0h 58min"),("Castlevania SOTN","0h 45min")]
for i, (name, time) in enumerate(games):
    y = 115 + i*44
    bw = int((6-i)/6*280)
    d.rectangle([20, y+16, 20+bw, y+24], fill=(50,80,160))
    d.text((20, y), f"{i+1}. {name}", fill=WHITE if i==0 else GREY)
    d.text((SCREEN_W-130, y), time, fill=ACCENT)
img.save(os.path.join(OUT_DIR, "04_statistics.png"))
print("04_statistics.png")

# 5 — History
img, d = make_base("Historique  (Page 1/5)", "50 derniers lancements")
draw_status(d, True, "1h 30min")
entries = [("2024-01-15 18:32","Super Mario World"),("2024-01-15 17:10","Sonic the Hedgehog"),
           ("2024-01-14 20:05","Pokemon Red"),("2024-01-14 19:00","Zelda"),
           ("2024-01-13 15:30","Mega Man X"),("2024-01-13 14:00","Castlevania")]
for i, (ts, game) in enumerate(entries):
    y = 115 + i*42
    if i == 0:
        d.rectangle([10, y-2, SCREEN_W-10, y+28], fill=SEL_BG)
    d.text((20, y+5), "["+ts+"]", fill=ACCENT if i==0 else GREY)
    d.text((280, y+5), game, fill=WHITE if i==0 else GREY)
img.save(os.path.join(OUT_DIR, "05_history.png"))
print("05_history.png")

# 6 — Overlay notification
img, d = make_base("","")
d.rectangle([0,0,SCREEN_W,SCREEN_H], fill=(20,30,20))
d.text((210, 220), "GAME RUNNING...", fill=(100,200,100))
pw, ph = 430, 100
px = (SCREEN_W-pw)//2
py = 25
d.rectangle([px, py, px+pw, py+ph], fill=(15,20,45), outline=YELLOW, width=3)
d.rectangle([px, py, px+pw, py+32], fill=(60,45,0))
d.text((px+12, py+9), "GuardianPlay", fill=YELLOW)
d.text((px+12, py+40), "Attention : plus que 5 minutes !", fill=WHITE)
d.text((px+12, py+68), "Sauvegardez votre progression...", fill=GREY)
img.save(os.path.join(OUT_DIR, "06_overlay_warning.png"))
print("06_overlay_warning.png")

# 7 — Blocked launch
img, d = make_base("","")
d.rectangle([0,0,SCREEN_W,SCREEN_H], fill=(10,8,20))
pw, ph = 460, 160
px = (SCREEN_W-pw)//2
py = (SCREEN_H-ph)//2
d.rectangle([px-3, py-3, px+pw+3, py+ph+3], fill=RED_C)
d.rectangle([px, py, px+pw, py+ph], fill=(20,10,10))
d.rectangle([px, py, px+pw, py+38], fill=(80,20,20))
d.text((px+12, py+10), "Temps de jeu epuise", fill=WHITE)
d.text((px+12, py+55), "Plus de temps de jeu disponible.", fill=GREY)
d.text((px+12, py+80), "Demandez l autorisation a un parent.", fill=GREY)
d.rectangle([px+30, py+115, px+pw-30, py+148], fill=(50,15,15), outline=RED_C)
d.text((px+158, py+124), "[ OK ]", fill=RED_C)
img.save(os.path.join(OUT_DIR, "07_blocked.png"))
print("07_blocked.png")

# 8 — PIN bypass at game launch
img, d = make_base("GuardianPlay — Lancement ROM", "")
d.text((20, 80), "Entrez le code PIN parent pour jouer sans limite.", fill=WHITE)
d.text((20, 105), "(Appuyez sur B pour jouer avec le timer)", fill=GREY)
bx0, by0 = 180, 160
for i in range(4):
    col = ACCENT if i == 0 else (40, 55, 100)
    bx = bx0 + i*80
    d.rectangle([bx, by0, bx+60, by0+60], fill=col, outline=WHITE, width=2)
    d.text((bx+20, by0+18), "?" if i>0 else "*", fill=WHITE)
d.text((140, by0+80), "Meme code PIN que dans les parametres", fill=(100,120,180))
for i, n in enumerate("0123456789"):
    nx = 90 + (i%5)*105
    ny = by0+120 + (i//5)*58
    d.rectangle([nx, ny, nx+90, ny+46], fill=SEL_BG if n=="0" else (30,40,75), outline=(60,80,140))
    d.text((nx+32, ny+14), n, fill=WHITE)
img.save(os.path.join(OUT_DIR, "08_pin_bypass_launch.png"))
print("08_pin_bypass_launch.png")

# Banner
img = Image.new("RGB", (900, 200), (18, 22, 38))
d = ImageDraw.Draw(img)
d.rectangle([0, 0, 900, 200], fill=(18,22,38))
for y in range(0, 200, 3):
    alpha = int(30 * (1 - y/200))
    d.line([0, y, 900, y], fill=(30, 50, 100))
d.rectangle([0, 0, 6, 200], fill=ACCENT)
d.text((40, 40), "GuardianPlay", fill=WHITE)
d.text((40, 80), "Parental Control Add-on for Onion OS", fill=ACCENT)
d.text((40, 115), "Miyoo Mini / Mini+  |  FR / EN / ES  |  v1.0", fill=GREY)
d.text((40, 145), "PIN bypass • Timer daemon • Game history • Statistics", fill=(100,120,180))
# Shield icon area
d.polygon([(800,30),(870,30),(870,90),(835,120),(800,90)], fill=(35,55,110), outline=ACCENT)
d.ellipse([815,50,855,90], fill=WHITE)
d.text((823, 62), "GP", fill=(18,22,38))
img.save(os.path.join(OUT_DIR, "banner.png"))
print("banner.png")

print("\nAll screenshots OK!")
