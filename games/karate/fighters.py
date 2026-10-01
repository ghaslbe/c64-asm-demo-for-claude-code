"""
Skeleton based pose renderer for the DOJO BRAWL fighters.

Every pose is described by a few joint positions on a 12 x 42 grid (a multicolor C64 sprite
pair: two stacked 12x21 multicolor sprites = 24 x 42 screen pixels). The renderer builds a
karateka from head, shoulders, torso with V-neck and belt, thick arms and legs, bare feet, and
adds a dark outline so the figure stands out in front of any background.
Pixel codes: 0 transparent, 1 skin, 2 gi (the fighter's own colour), 3 dark (hair/belt/outline).
"""
GW, GH = 12, 42


def new_grid():
    return [[0] * GW for _ in range(GH)]


def put(g, x, y, c, overwrite=True):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < GW and 0 <= y < GH and (overwrite or g[y][x] == 0):
        g[y][x] = c


def thick(g, p0, p1, w0, w1, c):
    """Line from p0 to p1 whose width goes from w0 to w1 (across the limb)."""
    (x0, y0), (x1, y1) = p0, p1
    horizontal = abs(x1 - x0) > abs(y1 - y0)
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    steps = int(n * 2) + 1
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        w = w0 + (w1 - w0) * t
        k = max(1, int(round(w)))
        for j in range(k):
            off = j - (k - 1) / 2.0 + 0.0001
            if horizontal:
                put(g, x, y + off, c)
            else:
                put(g, x + off, y, c)


def arm(g, shoulder, elbow, hand):
    thick(g, shoulder, elbow, 2, 2, 2)        # wide gi sleeve
    thick(g, elbow, hand, 2, 1, 2)            # forearm, still in the sleeve
    put(g, hand[0], hand[1], 1)               # fist
    put(g, hand[0] + (1 if hand[0] >= elbow[0] else -1), hand[1], 1)


def leg(g, hip, knee, foot):
    thick(g, hip, knee, 3, 2, 2)              # thigh
    thick(g, knee, foot, 2, 2, 2)             # trousers down to the ankle
    fx, fy = foot
    put(g, fx, fy, 1)                         # bare foot
    put(g, fx + (1 if fx >= knee[0] else -1), fy, 1)


def torso(g, neck, hip):
    nx, ny = neck
    hx, hy = hip
    n = max(int(round(hy - ny)), 1)
    for i in range(n + 1):
        t = i / n
        x = nx + (hx - nx) * t
        y = ny + (hy - ny) * t
        width = 5 if i < 3 else (4 if i < n - 2 else 3)       # broad shoulders, narrow waist
        for k in range(width):
            put(g, x + k - (width - 1) / 2.0 + 0.0001, y, 2)
    # gi opening: a small V of skin in front of the chest
    put(g, nx + 1, ny + 1, 1)
    put(g, nx + 1, ny + 2, 1)
    put(g, nx, ny + 1, 1)


def belt(g, hip):
    hx, hy = hip
    for k in (-2, -1, 0, 1):
        put(g, hx + k, hy, 3)
        put(g, hx + k, hy + 1, 3) if k in (-1, 0) else None
    put(g, hx - 1, hy + 2, 3)                 # loose ends of the belt
    put(g, hx, hy + 3, 3)


def head(g, hx, hy):
    for dy in range(-3, 3):                   # 4 columns x 6 rows
        for dx in (-1, 0, 1, 2):
            put(g, hx + dx, hy + dy, 1)
    for dx in (-1, 0, 1, 2):                  # hair on top
        put(g, hx + dx, hy - 3, 3)
    put(g, hx - 1, hy - 2, 3)                 # hair at the back
    put(g, hx, hy - 2, 3)
    put(g, hx - 1, hy - 1, 3)
    put(g, hx - 1, hy, 3)
    put(g, hx + 2, hy - 1, 3)                 # eye
    put(g, hx + 3, hy, 1)                     # nose


def outline(g):
    out = [row[:] for row in g]
    for y in range(GH):
        for x in range(GW):
            if g[y][x] != 0:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if (dx or dy) and 0 <= xx < GW and 0 <= yy < GH and g[yy][xx] != 0:
                        out[y][x] = 3
    return out


def draw_prone(g):
    """Fighter lying on his back (head to the left, feet to the right)."""
    for y in range(36, 41):                   # torso
        for x in range(3, 8):
            put(g, x, y, 2)
    for x in (5, 6):
        put(g, x, 38, 3)                      # belt
    for y in range(37, 41):                   # legs
        for x in range(8, 11):
            put(g, x, y, 2)
    put(g, 10, 37, 1)
    put(g, 10, 40, 1)                         # feet
    for x in (3, 4):                          # arms along the body
        put(g, x, 40, 1)
    for dy in range(34, 40):                  # head
        for dx in range(0, 3):
            put(g, dx, dy, 1)
    for dy in range(34, 40):
        put(g, 0, dy, 3)
    put(g, 1, 34, 3)
    put(g, 2, 34, 3)
    put(g, 2, 37, 3)
    return outline(g)


def draw(pose):
    g = new_grid()
    if pose.get("prone"):
        return draw_prone(g), pose.get("anchor", 6)
    hx, hy = pose["head"]
    neck, hip = pose["neck"], pose["hip"]
    leg(g, hip, *pose["far_leg"])
    arm(g, neck, *pose["far_arm"])
    torso(g, neck, hip)
    leg(g, hip, *pose["near_leg"])
    belt(g, hip)
    arm(g, neck, *pose["near_arm"])
    head(g, hx, hy)
    return outline(g), pose.get("anchor", hip[0])


# ---------------------------------------------------------------- poses (facing right)
def P(head, neck, hip, far_arm, near_arm, far_leg, near_leg, anchor=None):
    d = dict(head=head, neck=neck, hip=hip, far_arm=far_arm, near_arm=near_arm,
             far_leg=far_leg, near_leg=near_leg)
    if anchor is not None:
        d["anchor"] = anchor
    return d


POSES = {
    "stand":  P((5, 6), (5, 10), (5, 24), ((3, 17), (5, 14)), ((7, 17), (9, 13)),
                ((3, 31), (2, 40)), ((8, 31), (9, 40))),
    "stand2": P((5, 7), (5, 11), (5, 25), ((3, 18), (5, 16)), ((7, 18), (9, 15)),
                ((3, 32), (2, 40)), ((8, 32), (9, 40))),
    "walk1":  P((5, 6), (5, 10), (5, 24), ((3, 17), (4, 15)), ((7, 17), (9, 14)),
                ((3, 31), (1, 40)), ((8, 31), (10, 40))),
    "walk2":  P((5, 6), (5, 10), (5, 24), ((3, 17), (5, 14)), ((7, 17), (9, 13)),
                ((4, 32), (3, 40)), ((6, 32), (7, 40))),
    "crouch": P((5, 15), (5, 19), (5, 31), ((3, 24), (5, 22)), ((7, 24), (9, 20)),
                ((2, 35), (3, 40)), ((8, 34), (8, 40))),
    "jump":   P((5, 11), (5, 15), (5, 27), ((3, 20), (2, 16)), ((7, 20), (9, 16)),
                ((3, 30), (4, 35)), ((8, 28), (7, 34))),
    "punch":  P((4, 6), (4, 10), (4, 24), ((2, 17), (3, 14)), ((7, 13), (11, 13)),
                ((2, 31), (0, 40)), ((7, 31), (9, 40))),
    "kick":   P((3, 7), (3, 11), (3, 24), ((1, 17), (1, 14)), ((5, 16), (6, 13)),
                ((3, 32), (2, 40)), ((7, 20), (11, 15))),
    "sweep":  P((3, 17), (3, 21), (3, 31), ((1, 25), (1, 29)), ((6, 26), (8, 30)),
                ((2, 36), (1, 40)), ((7, 37), (11, 40))),
    "fly":    P((4, 9), (4, 13), (3, 21), ((2, 16), (1, 13)), ((6, 17), (8, 15)),
                ((2, 27), (1, 25)), ((7, 23), (11, 25))),
    "hit":    P((3, 7), (4, 11), (5, 24), ((2, 16), (0, 19)), ((7, 13), (10, 11)),
                ((3, 32), (2, 40)), ((7, 31), (8, 40))),
    "fall":   dict(prone=True, anchor=6),
    "getup":  P((4, 14), (4, 18), (4, 30), ((2, 25), (4, 27)), ((6, 23), (8, 21)),
                ((2, 38), (1, 40)), ((8, 35), (9, 40))),
    "win":    P((5, 6), (5, 10), (5, 24), ((2, 9), (1, 4)), ((8, 9), (9, 4)),
                ((3, 31), (2, 40)), ((8, 31), (9, 40))),
}
POSE_ORDER = ["stand", "stand2", "walk1", "walk2", "crouch", "jump", "punch", "kick",
              "sweep", "fly", "hit", "fall", "getup", "win"]


def mirror(g):
    return [row[::-1] for row in g]


def to_blocks(g):
    """12 x 42 grid -> two 64 byte multicolor sprite blocks (upper, lower)."""
    code = {0: 0b00, 1: 0b01, 2: 0b10, 3: 0b11}
    blocks = []
    for half in range(2):
        data = []
        for y in range(21):
            row = g[half * 21 + y]
            bits = 0
            for x in range(12):
                bits = (bits << 2) | code[row[x]]
            data += [(bits >> 16) & 255, (bits >> 8) & 255, bits & 255]
        blocks.append(data + [0])
    return blocks


def all_blocks():
    """Returns (list of 64 byte blocks, anchors for facing 0, anchors for facing 1).
    Block index = (pose * 2 + facing) * 2 + half."""
    blocks, a0, a1 = [], [], []
    for name in POSE_ORDER:
        g, anchor = draw(POSES[name])
        a0.append(int(round(2 * anchor + 1)))                 # px from the sprite's left edge
        a1.append(24 - int(round(2 * anchor + 1)))
        for facing, grid in ((0, g), (1, mirror(g))):
            blocks += to_blocks(grid)
    return blocks, a0, a1


def preview(path, scale=6):
    """Contact sheet of all poses on a sunset / wooden floor background for a quick visual check."""
    from PIL import Image
    pal = {1: (255, 190, 150), 2: (240, 240, 240), 3: (20, 12, 12)}
    cols = 7
    cell_w, cell_h = 12 * 2 * scale + 8, 42 * scale + 8
    rows = (len(POSE_ORDER) + cols - 1) // cols
    img = Image.new("RGB", (cell_w * cols, cell_h * rows), (60, 60, 90))
    px = img.load()
    for i, name in enumerate(POSE_ORDER):
        g, _ = draw(POSES[name])
        ox, oy = (i % cols) * cell_w + 4, (i // cols) * cell_h + 4
        for y in range(cell_h - 8):                       # background: pink sky above, wood below
            for x in range(cell_w - 8):
                px[ox + x, oy + y] = (237, 125, 150) if y < (cell_h - 8) * 0.7 else (184, 98, 30)
        for y in range(GH):
            for x in range(GW):
                c = g[y][x]
                if c == 0:
                    continue
                for dy in range(scale):
                    for dx in range(scale * 2):
                        px[ox + x * scale * 2 + dx, oy + y * scale + dy] = pal[c]
    img.save(path)


if __name__ == "__main__":
    preview("docs/poses_preview.png")
    print("wrote docs/poses_preview.png")
