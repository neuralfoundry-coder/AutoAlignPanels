"""
AutoAlignPanels — Screenshot Generator
Produces 3 × 2880×1800 px PNG screenshots for README / marketing use.
Dependencies: Pillow only.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os, math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
W, H = 2880, 1800
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# Colours
C_BG0        = (13,  13,  26)
C_BG1        = (30,  15,  42)
C_WIN        = (30,  32,  46)
C_TITLEBAR   = (22,  24,  36)
C_TEXT       = (255, 255, 255)
C_TEXT2      = (150, 155, 175)
C_TEXT3      = (100, 105, 130)
C_BLUE       = (74,  144, 226)
C_GREEN      = (48,  209,  88)
C_PURPLE     = (191,  90, 242)
C_RED_TL     = (255,  95,  87)
C_YEL_TL     = (255, 189,  46)
C_GRN_TL     = (40,  200,  64)
C_BORDER     = (55,  58,  80)
C_SHADOW     = (0,    0,   0, 120)

# ---------------------------------------------------------------------------
# Font helpers
# ---------------------------------------------------------------------------
FONT_SFNS      = "/System/Library/Fonts/SFNS.ttf"
FONT_BOLD_FB   = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REG_FB    = "/System/Library/Fonts/Supplemental/Arial.ttf"

def _load(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return None

def font(size, bold=False):
    f = _load(FONT_SFNS, size)
    if f:
        return f
    fb = FONT_BOLD_FB if bold else FONT_REG_FB
    f = _load(fb, size)
    return f or ImageFont.load_default()

# ---------------------------------------------------------------------------
# Drawing primitives
# ---------------------------------------------------------------------------

def draw_gradient(img, c0, c1, direction="diagonal"):
    """Fill img with a smooth gradient."""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            if direction == "diagonal":
                t = (x / w * 0.5 + y / h * 0.5)
            elif direction == "vertical":
                t = y / h
            else:
                t = x / w
            r = int(c0[0] + (c1[0] - c0[0]) * t)
            g = int(c0[1] + (c1[1] - c0[1]) * t)
            b = int(c0[2] + (c1[2] - c0[2]) * t)
            px[x, y] = (r, g, b, 255)


def draw_gradient_fast(img, c0, c1, direction="diagonal"):
    """Faster gradient using horizontal scanlines."""
    from PIL import Image as PILImage
    w, h = img.size
    draw = ImageDraw.Draw(img)
    steps = h if direction in ("vertical", "diagonal") else w
    for i in range(steps):
        t = i / max(steps - 1, 1)
        if direction == "diagonal":
            t2 = (t * 0.5)  # simplified diagonal via vertical bands
        else:
            t2 = t
        r = int(c0[0] + (c1[0] - c0[0]) * t2)
        g = int(c0[1] + (c1[1] - c0[1]) * t2)
        b = int(c0[2] + (c1[2] - c0[2]) * t2)
        if direction in ("vertical", "diagonal"):
            draw.line([(0, i), (w, i)], fill=(r, g, b, 255))
        else:
            draw.line([(i, 0), (i, h)], fill=(r, g, b, 255))


def add_noise_layer(img, strength=6):
    """Very subtle grain to add depth."""
    import random
    rng = random.Random(42)
    px = img.load()
    w, h = img.size
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            n = rng.randint(-strength, strength)
            c = px[x, y]
            px[x, y] = (
                max(0, min(255, c[0] + n)),
                max(0, min(255, c[1] + n)),
                max(0, min(255, c[2] + n)),
                c[3],
            )


def draw_shadow(draw, rect, radius=24, offset=(8, 12), blur_expand=30, alpha=110):
    """Draw a blurred drop-shadow rectangle on a layer then composite."""
    # We'll just draw a slightly larger, darker, semi-transparent rounded rect
    x1, y1, x2, y2 = rect
    ox, oy = offset
    expand = blur_expand // 2
    sx1, sy1 = x1 + ox - expand, y1 + oy - expand
    sx2, sy2 = x2 + ox + expand, y2 + oy + expand
    for i in range(8, 0, -1):
        a = int(alpha * (i / 8) ** 1.5)
        e = (8 - i) * 4
        draw.rounded_rectangle(
            [sx1 + e, sy1 + e, sx2 - e, sy2 - e],
            radius=radius + (8 - i) * 2,
            fill=(0, 0, 0, a),
        )


def draw_window(img, rect, title="App", content_fn=None, radius=14, border_color=None):
    """
    Draw a macOS-style dark window.
    rect = (x1, y1, x2, y2)
    content_fn(draw, content_rect) — optional callback to draw inside the body
    """
    draw = ImageDraw.Draw(img, "RGBA")
    x1, y1, x2, y2 = rect
    w_w = x2 - x1
    titlebar_h = 52

    bc = border_color or C_BORDER

    # Shadow
    draw_shadow(draw, rect, radius=radius + 4, offset=(10, 16), alpha=100)

    # Window background
    draw.rounded_rectangle([x1, y1, x2, y2], radius=radius, fill=C_WIN + (255,))

    # Border glow
    draw.rounded_rectangle([x1, y1, x2, y2], radius=radius,
                            outline=bc + (180,), width=2)

    # Title bar
    draw.rounded_rectangle(
        [x1, y1, x2, y1 + titlebar_h + radius],
        radius=radius,
        fill=C_TITLEBAR + (255,),
    )
    # Cover lower-rounded corners of title bar
    draw.rectangle([x1, y1 + titlebar_h, x2, y1 + titlebar_h + radius],
                   fill=C_TITLEBAR + (255,))

    # Traffic lights
    tl_y = y1 + titlebar_h // 2
    tl_r = 11
    tl_x = x1 + 24
    for col in (C_RED_TL, C_YEL_TL, C_GRN_TL):
        draw.ellipse([tl_x - tl_r, tl_y - tl_r, tl_x + tl_r, tl_y + tl_r],
                     fill=col + (255,))
        tl_x += tl_r * 2 + 10

    # Title text
    f = font(24)
    bbox = draw.textbbox((0, 0), title, font=f)
    tw = bbox[2] - bbox[0]
    tx = x1 + (w_w - tw) // 2
    ty = y1 + (titlebar_h - (bbox[3] - bbox[1])) // 2
    draw.text((tx, ty), title, font=f, fill=C_TEXT2 + (220,))

    # Divider line under title bar
    draw.line([(x1, y1 + titlebar_h), (x2, y1 + titlebar_h)],
              fill=C_BORDER + (180,), width=1)

    # Content area
    content_rect = (x1 + 1, y1 + titlebar_h + 1, x2 - 1, y2 - 1)
    if content_fn:
        content_fn(draw, content_rect)

    return draw


# ---------------------------------------------------------------------------
# Window content painters
# ---------------------------------------------------------------------------

def content_code(draw, rect, accent=C_BLUE):
    x1, y1, x2, y2 = rect
    f_small = font(20)
    lines = [
        ("func ", C_TEXT2, "alignWindows", accent, "() {", C_TEXT2),
        ("  let ", C_TEXT2, "windows", C_TEXT, " = ", C_TEXT2),
        ("    getOnscreenWindows", accent, "()", C_TEXT2, "", C_TEXT2),
        ("  layout", C_TEXT2, ".apply", accent, "(to: windows)", C_TEXT2),
        ("}", C_TEXT2, "", C_TEXT, "", C_TEXT2),
        ("", C_TEXT, "", C_TEXT, "", C_TEXT),
        ("// Grid layout", C_TEXT3, "", C_TEXT, "", C_TEXT),
        ("let grid = GridLayout", C_TEXT2, "(cols: 2)", accent),
        ("grid.arrange", accent, "(windows)", C_TEXT2),
    ]
    cy = y1 + 18
    lh = 34
    for parts in lines:
        cx = x1 + 22
        for i in range(0, len(parts), 2):
            txt = parts[i]
            col = parts[i + 1]
            if txt:
                draw.text((cx, cy), txt, font=f_small, fill=col + (220,))
                bb = draw.textbbox((0, 0), txt, font=f_small)
                cx += bb[2] - bb[0]
        cy += lh
        if cy > y2 - 10:
            break


def content_safari(draw, rect, accent=C_BLUE):
    x1, y1, x2, y2 = rect
    # Address bar
    bar_h = 38
    draw.rounded_rectangle([x1 + 14, y1 + 10, x2 - 14, y1 + 10 + bar_h],
                            radius=10, fill=(40, 42, 58, 255))
    f_s = font(20)
    draw.text((x1 + 28, y1 + 18), "https://apple.com", font=f_s, fill=C_TEXT3 + (200,))
    # Fake page blocks
    bx = x1 + 14
    by = y1 + 60
    bw = x2 - x1 - 28
    draw.rounded_rectangle([bx, by, bx + bw, by + 100],
                            radius=8, fill=(40, 42, 58, 160))
    for row_y in (by + 120, by + 150, by + 180, by + 210):
        w_block = int(bw * (0.5 + 0.35 * math.sin(row_y)))
        draw.rounded_rectangle([bx, row_y, bx + w_block, row_y + 16],
                                radius=4, fill=(55, 58, 80, 180))


def content_terminal(draw, rect, accent=C_GREEN):
    x1, y1, x2, y2 = rect
    draw.rectangle([x1, y1, x2, y2], fill=(18, 20, 28, 255))
    f_s = font(20)
    lines = [
        ("$ ", C_GRN_TL, "swift build", C_TEXT),
        ("Build complete!", C_GREEN, "", C_TEXT),
        ("$ ", C_GRN_TL, "swift run", C_TEXT),
        ("AutoAlignPanels running…", C_TEXT2, "", C_TEXT),
        ("$ ", C_GRN_TL, "▌", C_TEXT),
    ]
    cy = y1 + 16
    lh = 32
    for parts in lines:
        cx = x1 + 18
        for i in range(0, len(parts), 2):
            txt = parts[i]
            col = parts[i + 1]
            if txt:
                draw.text((cx, cy), txt, font=f_s, fill=col + (230,))
                bb = draw.textbbox((0, 0), txt, font=f_s)
                cx += bb[2] - bb[0]
        cy += lh


def content_finder(draw, rect, accent=C_BLUE):
    x1, y1, x2, y2 = rect
    sidebar_w = 90
    # Sidebar
    draw.rectangle([x1, y1, x1 + sidebar_w, y2],
                   fill=(24, 26, 38, 255))
    f_s = font(18)
    items = ["Recents", "Desktop", "Documents", "Downloads", "Projects"]
    for i, item in enumerate(items):
        iy = y1 + 16 + i * 30
        col = C_BLUE if i == 0 else C_TEXT3
        draw.text((x1 + 10, iy), item, font=f_s, fill=col + (200,))
    # File grid
    cols_f, rows_f = 4, 3
    cell_w = (x2 - x1 - sidebar_w - 20) // cols_f
    cell_h = (y2 - y1 - 20) // rows_f
    file_names = ["main.swift", "AppDelegate", "README", "Assets", "project.yml",
                  "Package.swift", "build", "Sources", "Resources", "Tests", "Docs", "scripts"]
    for idx in range(min(12, cols_f * rows_f)):
        col_i = idx % cols_f
        row_i = idx // cols_f
        fx = x1 + sidebar_w + 10 + col_i * cell_w
        fy = y1 + 10 + row_i * cell_h
        draw.rounded_rectangle([fx + 6, fy + 4, fx + cell_w - 6, fy + cell_h - 14],
                                radius=6, fill=(40, 42, 58, 160))
        name = file_names[idx] if idx < len(file_names) else ""
        bb = draw.textbbox((0, 0), name, font=f_s)
        nw = bb[2] - bb[0]
        nx = fx + (cell_w - nw) // 2
        draw.text((nx, fy + cell_h - 24), name, font=f_s, fill=C_TEXT3 + (180,))


# ---------------------------------------------------------------------------
# Keyboard badge
# ---------------------------------------------------------------------------

def draw_kbd_badge(draw, center_x, y, keys, accent=C_BLUE, big=False):
    f_sz = 36 if big else 28
    f_b = font(f_sz, bold=True)
    pad_x = 28 if big else 22
    pad_y = 12 if big else 10
    gap = 10

    # Measure total width
    parts = []
    total_w = 0
    for k in keys:
        bb = draw.textbbox((0, 0), k, font=f_b)
        kw = bb[2] - bb[0]
        kh = bb[3] - bb[1]
        parts.append((k, kw, kh))
        total_w += kw + pad_x * 2
    total_w += gap * (len(keys) - 1)

    x = center_x - total_w // 2
    max_h = max(kh for _, _, kh in parts) + pad_y * 2

    for k, kw, kh in parts:
        bx1, by1 = x, y
        bx2, by2 = x + kw + pad_x * 2, y + max_h
        # Shadow
        draw.rounded_rectangle([bx1 + 3, by1 + 4, bx2 + 3, by2 + 4],
                                radius=14, fill=(0, 0, 0, 80))
        # Key background
        draw.rounded_rectangle([bx1, by1, bx2, by2],
                                radius=14, fill=accent + (230,))
        # Key border highlight
        draw.rounded_rectangle([bx1, by1, bx2, by2],
                                radius=14, outline=(255, 255, 255, 40), width=2)
        # Key text
        tx = bx1 + pad_x
        ty = by1 + (max_h - kh) // 2 - 1
        draw.text((tx, ty), k, font=f_b, fill=(255, 255, 255, 255))
        x += kw + pad_x * 2 + gap

    return max_h


# ---------------------------------------------------------------------------
# Shared: background & glows
# ---------------------------------------------------------------------------

def make_base_image():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    draw_gradient_fast(img, C_BG0, C_BG1, "diagonal")
    # Radial glow overlay
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(700, 0, -20):
        alpha = int(18 * (1 - r / 700))
        gd.ellipse([W // 2 - r, H // 2 - r, W // 2 + r, H // 2 + r],
                   fill=(74, 100, 200, alpha))
    img = Image.alpha_composite(img, glow)
    return img


def draw_title(draw, y, title, subtitle, accent=C_BLUE):
    f_title = font(96, bold=True)
    f_sub   = font(48)

    # Title shadow
    bb = draw.textbbox((0, 0), title, font=f_title)
    tw = bb[2] - bb[0]
    tx = (W - tw) // 2
    draw.text((tx + 4, y + 4), title, font=f_title, fill=(0, 0, 0, 100))
    draw.text((tx, y), title, font=f_title, fill=C_TEXT + (255,))

    # Subtitle
    bb2 = draw.textbbox((0, 0), subtitle, font=f_sub)
    sw = bb2[2] - bb2[0]
    sy = y + (bb[3] - bb[1]) + 22
    draw.text(((W - sw) // 2, sy), subtitle, font=f_sub, fill=C_TEXT2 + (200,))

    return sy + (bb2[3] - bb2[1]) + 20


# ---------------------------------------------------------------------------
# Screenshot 1 — "One Hotkey. Perfect Grid."
# ---------------------------------------------------------------------------

def make_screenshot_1():
    img = make_base_image()
    draw = ImageDraw.Draw(img, "RGBA")

    # Title
    title_bottom = draw_title(
        draw, 90,
        "One Hotkey. Perfect Grid.",
        "Align all your windows instantly with  \u2303\u21e7P",
        accent=C_BLUE,
    )

    # 2×2 window grid
    margin = 130
    gap = 24
    area_top = title_bottom + 40
    area_bot = H - 180
    total_w = W - margin * 2
    total_h = area_bot - area_top

    win_w = (total_w - gap) // 2
    win_h = (total_h - gap) // 2

    windows = [
        ("Xcode — MyProject.swift", content_code,    C_BLUE,   C_BORDER),
        ("Safari",                   content_safari,  C_BLUE,   C_BORDER),
        ("Terminal",                 content_terminal,C_GREEN,  (55, 80, 58)),
        ("Finder",                   content_finder,  C_BLUE,   C_BORDER),
    ]

    positions = [
        (margin,            area_top),
        (margin + win_w + gap, area_top),
        (margin,            area_top + win_h + gap),
        (margin + win_w + gap, area_top + win_h + gap),
    ]

    for (title, cfn, accent, border), (wx, wy) in zip(windows, positions):
        draw_window(
            img,
            (wx, wy, wx + win_w, wy + win_h),
            title=title,
            content_fn=cfn,
            border_color=border,
        )

    # Redraw draw handle (after window drawing modified the image)
    draw = ImageDraw.Draw(img, "RGBA")

    # Decorative gap indicators (thin lines between windows)
    mid_x = margin + win_w + gap // 2
    mid_y = area_top + win_h + gap // 2
    draw.line([(mid_x, area_top + 30), (mid_x, area_bot - 30)],
              fill=C_BLUE + (60,), width=2)
    draw.line([(margin + 30, mid_y), (W - margin - 30, mid_y)],
              fill=C_BLUE + (60,), width=2)

    # Keyboard badge at bottom
    badge_y = area_bot + 30
    draw_kbd_badge(draw, W // 2, badge_y, ["\u2303", "\u21e7", "P"],
                   accent=C_BLUE, big=True)

    # Bottom label
    f_hint = font(34)
    hint = "AutoAlignPanels"
    bb = draw.textbbox((0, 0), hint, font=f_hint)
    draw.text(((W - (bb[2] - bb[0])) // 2, H - 52), hint,
              font=f_hint, fill=C_TEXT3 + (160,))

    img = img.convert("RGB")
    path = os.path.join(OUT_DIR, "screenshot_1.png")
    img.save(path, "PNG", optimize=False)
    print(f"  Saved {path}")


# ---------------------------------------------------------------------------
# Screenshot 2 — "Three Powerful Layouts"
# ---------------------------------------------------------------------------

def make_screenshot_2():
    img = make_base_image()
    draw = ImageDraw.Draw(img, "RGBA")

    title_bottom = draw_title(
        draw, 80,
        "Grid. Horizontal. Vertical.",
        "Three layouts for every workflow",
    )

    col_margin = 80
    col_gap = 56
    area_top = title_bottom + 60
    area_bot = H - 160
    col_w = (W - col_margin * 2 - col_gap * 2) // 3

    # App name → header color mapping (for title bar accent)
    APP_COLORS = [
        ((86, 156, 214), "Xcode"),      # blue
        ((206, 145, 120), "Safari"),     # salmon
        ((78, 201, 176), "Terminal"),    # teal
        ((220, 220, 170), "Finder"),     # yellow
    ]

    layouts = [
        ("Grid",       ["\u2303", "\u21e7", "P"], C_BLUE,   "grid"),
        ("Horizontal", ["\u2303", "\u21e7", "H"], C_GREEN,  "horizontal"),
        ("Vertical",   ["\u2303", "\u21e7", "V"], C_PURPLE, "vertical"),
    ]

    for col_i, (label, keys, accent, mode) in enumerate(layouts):
        col_x = col_margin + col_i * (col_w + col_gap)
        card_y1 = area_top
        card_y2 = area_bot

        # Column card
        draw.rounded_rectangle(
            [col_x - 24, card_y1 - 20, col_x + col_w + 24, card_y2 + 20],
            radius=28, fill=(18, 20, 32, 210),
        )
        draw.rounded_rectangle(
            [col_x - 24, card_y1 - 20, col_x + col_w + 24, card_y2 + 20],
            radius=28, outline=accent + (80,), width=2,
        )

        # Top glow
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gcx = col_x + col_w // 2
        for r in range(280, 0, -14):
            a = int(12 * (1 - r / 280))
            gd.ellipse([gcx - r, card_y1 - r, gcx + r, card_y1 + r], fill=accent + (a,))
        img = Image.alpha_composite(img, glow)
        draw = ImageDraw.Draw(img, "RGBA")

        # Column label
        f_label = font(56, bold=True)
        bb = draw.textbbox((0, 0), label, font=f_label)
        lx = col_x + (col_w - (bb[2] - bb[0])) // 2
        draw.text((lx, card_y1 + 18), label, font=f_label, fill=accent + (255,))
        label_h = bb[3] - bb[1]

        mock_top = card_y1 + label_h + 60
        mock_bot = card_y2 - 110
        mock_h = mock_bot - mock_top
        mock_gap = 16
        mini_r = 12
        tb_h = 36

        def mini_win(mx1, my1, mx2, my2, app_idx=0):
            hdr_col, app_name = APP_COLORS[app_idx % len(APP_COLORS)]
            mw = mx2 - mx1
            # Shadow
            draw.rounded_rectangle([mx1 + 4, my1 + 6, mx2 + 4, my2 + 6],
                                    radius=mini_r, fill=(0, 0, 0, 60))
            # Window body
            draw.rounded_rectangle([mx1, my1, mx2, my2],
                                    radius=mini_r, fill=C_WIN + (255,))
            # Colored title bar accent (top strip)
            strip_h = 5
            draw.rounded_rectangle([mx1, my1, mx2, my1 + strip_h + mini_r],
                                    radius=mini_r, fill=hdr_col + (200,))
            draw.rectangle([mx1, my1 + strip_h, mx2, my1 + strip_h + mini_r],
                           fill=hdr_col + (200,))
            # Title bar
            draw.rectangle([mx1, my1 + strip_h, mx2, my1 + tb_h],
                           fill=C_TITLEBAR + (255,))
            # Traffic lights
            tlx = mx1 + 12
            tly = my1 + strip_h + (tb_h - strip_h) // 2
            for tlc in (C_RED_TL, C_YEL_TL, C_GRN_TL):
                r2 = 6
                draw.ellipse([tlx - r2, tly - r2, tlx + r2, tly + r2], fill=tlc + (255,))
                tlx += r2 * 2 + 8
            # App name in title
            fn = font(max(14, min(20, mw // 10)))
            bb2 = draw.textbbox((0, 0), app_name, font=fn)
            tw2 = bb2[2] - bb2[0]
            if tw2 < mw - 80:
                draw.text((mx1 + (mw - tw2) // 2, my1 + strip_h + (tb_h - strip_h - (bb2[3] - bb2[1])) // 2),
                          app_name, font=fn, fill=C_TEXT2 + (180,))
            # Divider
            draw.line([(mx1, my1 + tb_h), (mx2, my1 + tb_h)],
                      fill=C_BORDER + (140,), width=1)
            # Content: a few clean lines in accent color
            cy2 = my1 + tb_h + 14
            line_h = 10
            line_gap = 18
            widths = [0.75, 0.55, 0.68, 0.42, 0.62, 0.50, 0.72, 0.38, 0.58]
            for wi_idx, wi in enumerate(widths):
                if cy2 + line_h > my2 - 10:
                    break
                lw2 = int((mw - 24) * wi)
                draw.rounded_rectangle([mx1 + 12, cy2, mx1 + 12 + lw2, cy2 + line_h],
                                        radius=3, fill=accent + (50,))
                cy2 += line_gap
            # Border
            draw.rounded_rectangle([mx1, my1, mx2, my2],
                                    radius=mini_r, outline=accent + (60,), width=1)

        if mode == "grid":
            hw = (col_w - mock_gap) // 2
            hh = (mock_h - mock_gap) // 2
            mini_win(col_x, mock_top, col_x + hw, mock_top + hh, 0)
            mini_win(col_x + hw + mock_gap, mock_top, col_x + col_w, mock_top + hh, 1)
            mini_win(col_x, mock_top + hh + mock_gap, col_x + hw, mock_bot, 2)
            mini_win(col_x + hw + mock_gap, mock_top + hh + mock_gap, col_x + col_w, mock_bot, 3)
        elif mode == "horizontal":
            pw2 = (col_w - mock_gap * 2) // 3
            for pi in range(3):
                mini_win(col_x + pi * (pw2 + mock_gap), mock_top,
                         col_x + pi * (pw2 + mock_gap) + pw2, mock_bot, pi)
        else:  # vertical
            ph2 = (mock_h - mock_gap * 2) // 3
            for pi in range(3):
                mini_win(col_x, mock_top + pi * (ph2 + mock_gap),
                         col_x + col_w, mock_top + pi * (ph2 + mock_gap) + ph2, pi)

        # Shortcut badge
        badge_y = card_y2 - 88
        draw_kbd_badge(draw, col_x + col_w // 2, badge_y, keys, accent=accent, big=False)

    # Bottom watermark
    f_hint = font(34)
    hint = "AutoAlignPanels"
    bb = draw.textbbox((0, 0), hint, font=f_hint)
    draw.text(((W - (bb[2] - bb[0])) // 2, H - 52), hint,
              font=f_hint, fill=C_TEXT3 + (160,))

    img = img.convert("RGB")
    path = os.path.join(OUT_DIR, "screenshot_2.png")
    img.save(path, "PNG")
    print(f"  Saved {path}")


# ---------------------------------------------------------------------------
# Screenshot 3 — "Lives in Your Menu Bar"
# ---------------------------------------------------------------------------

def make_screenshot_3():
    img = make_base_image()
    draw = ImageDraw.Draw(img, "RGBA")

    # Title
    title_bottom = draw_title(
        draw, 80,
        "Always Ready in Your Menu Bar",
        "One click or one shortcut — your call",
        accent=C_BLUE,
    )

    # ----------------------------------------------------------------
    # Simulated macOS menu bar
    # ----------------------------------------------------------------
    mb_h = 52
    mb_y = title_bottom + 50

    # Menu bar background (dark frosted glass style)
    draw.rectangle([0, mb_y, W, mb_y + mb_h],
                   fill=(18, 20, 30, 230))
    draw.line([(0, mb_y + mb_h), (W, mb_y + mb_h)],
              fill=C_BORDER + (120,), width=1)

    # Apple menu & app menus on left
    f_mb = font(26)
    left_items = [" ", "Finder", "File", "Edit", "View", "Window", "Help"]
    lx = 24
    for item in left_items:
        draw.text((lx, mb_y + 14), item, font=f_mb, fill=C_TEXT + (200,))
        bb = draw.textbbox((0, 0), item, font=f_mb)
        lx += (bb[2] - bb[0]) + 24

    # Right side system icons (simplified)
    right_items = ["Wi-Fi", "Bt", "Snd", "Batt", "Thu 16:42"]
    rx = W - 20
    for item in reversed(right_items):
        bb = draw.textbbox((0, 0), item, font=f_mb)
        iw = bb[2] - bb[0]
        rx -= iw + 20
        draw.text((rx, mb_y + 14), item, font=f_mb, fill=C_TEXT2 + (180,))

    # AutoAlignPanels icon in menu bar (highlighted with glow)
    icon_size = 32
    icon_x = W // 2 - icon_size // 2 - 40  # slightly left of center
    icon_y = mb_y + (mb_h - icon_size) // 2

    # Highlight background
    hl_pad = 10
    draw.rounded_rectangle(
        [icon_x - hl_pad, mb_y + 4,
         icon_x + icon_size + hl_pad, mb_y + mb_h - 4],
        radius=8,
        fill=C_BLUE + (50,),
    )
    # Glow
    for r in range(60, 0, -5):
        a = int(12 * (1 - r / 60))
        cx = icon_x + icon_size // 2
        cy = mb_y + mb_h // 2
        draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                     fill=C_BLUE + (a,))

    # Draw a mini grid icon (4 squares)
    sq = icon_size // 2 - 3
    sq_gap = 4
    offsets = [(0, 0), (sq + sq_gap, 0), (0, sq + sq_gap), (sq + sq_gap, sq + sq_gap)]
    for ox, oy in offsets:
        draw.rounded_rectangle(
            [icon_x + ox, icon_y + oy,
             icon_x + ox + sq, icon_y + oy + sq],
            radius=3,
            fill=C_BLUE + (255,),
        )

    # ----------------------------------------------------------------
    # Simulated desktop: blurred windows in background
    # ----------------------------------------------------------------
    desk_wins = [
        (160, mb_y + mb_h + 30, 1100, mb_y + mb_h + 780, "Xcode"),
        (1180, mb_y + mb_h + 30, 2720, mb_y + mb_h + 780, "Safari"),
        (160, mb_y + mb_h + 820, 1100, H - 60, "Terminal"),
        (1180, mb_y + mb_h + 820, 2720, H - 60, "Finder"),
    ]
    for dx1, dy1, dx2, dy2, dtitle in desk_wins:
        # Dim background windows
        draw.rounded_rectangle([dx1, dy1, dx2, dy2], radius=14,
                               fill=(25, 27, 40, 180))
        draw.rounded_rectangle([dx1, dy1, dx2, dy2], radius=14,
                               outline=C_BORDER + (80,), width=1)
        # Title bar
        draw.rounded_rectangle([dx1, dy1, dx2, dy1 + 44 + 14], radius=14,
                               fill=(18, 20, 30, 180))
        draw.rectangle([dx1, dy1 + 44, dx2, dy1 + 58], fill=(18, 20, 30, 180))
        draw.line([(dx1, dy1 + 44), (dx2, dy1 + 44)], fill=C_BORDER + (80,), width=1)
        tlx2 = dx1 + 22
        tly2 = dy1 + 22
        for tlc in (C_RED_TL, C_YEL_TL, C_GRN_TL):
            draw.ellipse([tlx2 - 9, tly2 - 9, tlx2 + 9, tly2 + 9],
                         fill=tlc + (120,))
            tlx2 += 28
        fn2 = font(22)
        bb2 = draw.textbbox((0, 0), dtitle, font=fn2)
        draw.text((dx1 + (dx2-dx1-(bb2[2]-bb2[0]))//2, dy1 + 12), dtitle,
                  font=fn2, fill=C_TEXT3 + (120,))

    # ----------------------------------------------------------------
    # Popover  (large, centered, 2× scale)
    # ----------------------------------------------------------------
    pop_w = 980
    pop_h = 1080

    pop_x = (W - pop_w) // 2
    pop_y = mb_y + mb_h + 30

    # Shadow
    draw_shadow(draw, (pop_x, pop_y, pop_x + pop_w, pop_y + pop_h),
                radius=28, offset=(12, 18), alpha=150)

    # Popover body
    draw.rounded_rectangle([pop_x, pop_y, pop_x + pop_w, pop_y + pop_h],
                            radius=28, fill=(22, 24, 36, 250))
    draw.rounded_rectangle([pop_x, pop_y, pop_x + pop_w, pop_y + pop_h],
                            radius=28, outline=C_BORDER + (200,), width=2)

    # Popover arrow pointing up
    arrow_cx = icon_x + icon_size // 2
    arrow_tip_y = pop_y
    arr_w, arr_h = 28, 18
    draw.polygon(
        [(arrow_cx, arrow_tip_y - arr_h),
         (arrow_cx - arr_w, arrow_tip_y),
         (arrow_cx + arr_w, arrow_tip_y)],
        fill=(22, 24, 36, 250),
    )
    draw.line(
        [(arrow_cx - arr_w - 1, arrow_tip_y),
         (arrow_cx, arrow_tip_y - arr_h - 1),
         (arrow_cx + arr_w + 1, arrow_tip_y)],
        fill=C_BORDER + (200,), width=2,
    )

    # ----- Popover contents -----
    py = pop_y + 48
    px_inner = pop_x + 56
    inner_w = pop_w - 112

    # Header: icon + title
    icon_hdr_sz = 72
    draw.rounded_rectangle(
        [px_inner, py, px_inner + icon_hdr_sz, py + icon_hdr_sz],
        radius=16, fill=C_BLUE + (50,),
    )
    sq2 = icon_hdr_sz // 2 - 8
    sq2g = 6
    for ox2, oy2 in [(0, 0), (sq2 + sq2g, 0), (0, sq2 + sq2g), (sq2 + sq2g, sq2 + sq2g)]:
        draw.rounded_rectangle(
            [px_inner + 10 + ox2, py + 10 + oy2,
             px_inner + 10 + ox2 + sq2, py + 10 + oy2 + sq2],
            radius=4, fill=C_BLUE + (255,),
        )

    f_hdr = font(54, bold=True)
    f_sec = font(38)
    f_row = font(44)
    f_sec_lbl = font(34)

    hdr_text = "AutoAlignPanels"
    draw.text((px_inner + icon_hdr_sz + 24, py + 6), hdr_text,
              font=f_hdr, fill=C_TEXT + (255,))
    sub_text = "Window Alignment Utility"
    draw.text((px_inner + icon_hdr_sz + 24, py + 66), sub_text,
              font=f_sec, fill=C_TEXT2 + (180,))

    py += icon_hdr_sz + 40

    # Divider
    draw.line([(pop_x + 30, py), (pop_x + pop_w - 30, py)],
              fill=C_BORDER + (140,), width=1)
    py += 28

    # Section label
    draw.text((px_inner, py), "SHORTCUTS", font=f_sec_lbl, fill=C_TEXT3 + (200,))
    py += 48

    # Shortcut rows
    shortcut_rows = [
        ("Grid",       ["\u2303", "\u21e7", "P"], C_BLUE),
        ("Horizontal", ["\u2303", "\u21e7", "H"], C_GREEN),
        ("Vertical",   ["\u2303", "\u21e7", "V"], C_PURPLE),
    ]
    for row_label, keys, row_accent in shortcut_rows:
        draw.text((px_inner, py + 6), row_label, font=f_row, fill=C_TEXT + (230,))
        # Kbd badges on right
        bx = pop_x + pop_w - 56
        f_k = font(34, bold=True)
        for k in reversed(keys):
            bb_k = draw.textbbox((0, 0), k, font=f_k)
            kw = bb_k[2] - bb_k[0] + 26
            kh = bb_k[3] - bb_k[1] + 16
            bx -= kw + 8
            draw.rounded_rectangle([bx, py + 2, bx + kw, py + 2 + kh + 4],
                                    radius=10, fill=row_accent + (210,))
            draw.rounded_rectangle([bx, py + 2, bx + kw, py + 2 + kh + 4],
                                    radius=10, outline=(255, 255, 255, 50), width=1)
            draw.text((bx + 13, py + 8), k, font=f_k, fill=(255, 255, 255, 255))
        py += 68

    py += 8
    # Divider
    draw.line([(pop_x + 30, py), (pop_x + pop_w - 30, py)],
              fill=C_BORDER + (140,), width=1)
    py += 28

    # Window gap row
    draw.text((px_inner, py + 6), "Window gap", font=f_row, fill=C_TEXT + (230,))
    sl_x1 = pop_x + pop_w // 2 + 20
    sl_x2 = pop_x + pop_w - 120
    sl_y = py + 22
    sl_h = 8
    draw.rounded_rectangle([sl_x1, sl_y, sl_x2, sl_y + sl_h],
                            radius=4, fill=C_BORDER + (200,))
    thumb_x = sl_x1 + int((sl_x2 - sl_x1) * 0.3)
    draw.rounded_rectangle([sl_x1, sl_y, thumb_x, sl_y + sl_h],
                            radius=4, fill=C_BLUE + (255,))
    draw.ellipse([thumb_x - 14, sl_y - 10, thumb_x + 14, sl_y + sl_h + 10],
                 fill=C_TEXT + (255,))
    draw.text((sl_x2 + 16, py + 4), "8 pt", font=f_sec, fill=C_TEXT2 + (200,))
    py += 72

    # Toggle: Launch at login
    draw.text((px_inner, py + 6), "Launch at login", font=f_row, fill=C_TEXT + (230,))
    tog_w2, tog_h2 = 96, 52
    tog_x = pop_x + pop_w - 56 - tog_w2
    tog_y = py
    draw.rounded_rectangle([tog_x, tog_y, tog_x + tog_w2, tog_y + tog_h2],
                            radius=26, fill=C_BLUE + (240,))
    draw.ellipse([tog_x + tog_w2 - tog_h2 + 6, tog_y + 6,
                  tog_x + tog_w2 - 6, tog_y + tog_h2 - 6],
                 fill=C_TEXT + (255,))
    py += 80

    py += 8
    # Divider
    draw.line([(pop_x + 30, py), (pop_x + pop_w - 30, py)],
              fill=C_BORDER + (140,), width=1)
    py += 28

    # Action buttons
    btn_h = 80
    btn_gap = 24
    btn_w = (inner_w - btn_gap) // 2

    # Align Now button (blue)
    bx1 = px_inner
    draw.rounded_rectangle([bx1, py, bx1 + btn_w, py + btn_h],
                            radius=20, fill=C_BLUE + (240,))
    draw.rounded_rectangle([bx1, py, bx1 + btn_w, py + btn_h],
                            radius=20, outline=(255, 255, 255, 40), width=1)
    f_btn = font(42, bold=True)
    align_txt = "Align Now"
    bb_a = draw.textbbox((0, 0), align_txt, font=f_btn)
    atw = bb_a[2] - bb_a[0]
    draw.text((bx1 + (btn_w - atw) // 2, py + (btn_h - (bb_a[3] - bb_a[1])) // 2),
              align_txt, font=f_btn, fill=C_TEXT + (255,))

    # Quit button
    bx2 = px_inner + btn_w + btn_gap
    draw.rounded_rectangle([bx2, py, bx2 + btn_w, py + btn_h],
                            radius=20, fill=(38, 40, 55, 220))
    draw.rounded_rectangle([bx2, py, bx2 + btn_w, py + btn_h],
                            radius=20, outline=C_BORDER + (180,), width=1)
    quit_txt = "Quit"
    bb_q = draw.textbbox((0, 0), quit_txt, font=f_btn)
    qtw = bb_q[2] - bb_q[0]
    draw.text((bx2 + (btn_w - qtw) // 2, py + (btn_h - (bb_q[3] - bb_q[1])) // 2),
              quit_txt, font=f_btn, fill=C_TEXT2 + (220,))

    # Bottom watermark
    f_hint = font(34)
    hint = "AutoAlignPanels"
    bb = draw.textbbox((0, 0), hint, font=f_hint)
    draw.text(((W - (bb[2] - bb[0])) // 2, H - 52), hint,
              font=f_hint, fill=C_TEXT3 + (160,))

    img = img.convert("RGB")
    path = os.path.join(OUT_DIR, "screenshot_3.png")
    img.save(path, "PNG")
    print(f"  Saved {path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Generating AutoAlignPanels App Store screenshots…")
    print("  Screenshot 1: One Hotkey. Perfect Grid.")
    make_screenshot_1()
    print("  Screenshot 2: Three Powerful Layouts")
    make_screenshot_2()
    print("  Screenshot 3: Lives in Your Menu Bar")
    make_screenshot_3()
    print("Done.")
