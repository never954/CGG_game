/* assetgen.cpp — builds every sprite sheet and texture the game uses.
 *
 * The art is produced with the same rasterizer written for the course
 * assignments: polygons are transformed with affine matrices, filled with the
 * scan-line algorithm (convex and concave), and outlined with a one-pixel dark
 * silhouette. The output is plain PNG files that Godot imports.
 *
 *   assets/sprites/<name>.png        sprite sheets  (one row per animation)
 *   assets/sprites/<name>.json       sheet layout   (cell size, rows, frames, fps)
 *   assets/sprites/props/<name>.png  single props   (trees, lanterns, keys, ...)
 *   assets/textures/<name>.png       64x64 tileable textures
 *
 * build & run (from game_play/):
 *   c++ -O2 -std=c++17 tools/assetgen.cpp -o tools/assetgen && ./tools/assetgen
 */

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <functional>
#include <initializer_list>
#include <sys/stat.h>

static const float PI_F = 3.14159265f;

// ------------------------------------------------------------------ colour + canvas
struct C3 { float r, g, b; };
static inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
static inline C3 mix(C3 a, C3 b, float t) { return { a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t }; }
static inline C3 mul(C3 a, float k) { return { a.r * k, a.g * k, a.b * k }; }

struct Canvas {
    int w = 0, h = 0;
    std::vector<uint8_t> px;                       // RGBA
    Canvas(int W, int H) : w(W), h(H), px((size_t)W * H * 4, 0) {}
    void blend(int x, int y, C3 c, float a) {
        if (x < 0 || y < 0 || x >= w || y >= h || a <= 0) return;
        uint8_t* p = &px[((size_t)y * w + x) * 4];
        float da = p[3] / 255.f, oa = a + da * (1 - a);
        if (oa <= 0) return;
        auto ch = [&](int i, float s) { p[i] = (uint8_t)clampf((s * a + p[i] * da * (1 - a)) / oa, 0, 255); };
        ch(0, c.r); ch(1, c.g); ch(2, c.b);
        p[3] = (uint8_t)clampf(oa * 255.f, 0, 255);
    }
    void set(int x, int y, C3 c) {
        if (x < 0 || y < 0 || x >= w || y >= h) return;
        uint8_t* p = &px[((size_t)y * w + x) * 4];
        p[0] = (uint8_t)clampf(c.r, 0, 255); p[1] = (uint8_t)clampf(c.g, 0, 255); p[2] = (uint8_t)clampf(c.b, 0, 255); p[3] = 255;
    }
};

// ------------------------------------------------------------------ PNG writer (stored deflate)
static uint32_t crc_table[256];
static void crc_init() {
    for (uint32_t n = 0; n < 256; ++n) { uint32_t c = n; for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1; crc_table[n] = c; }
}
static uint32_t crc(const uint8_t* b, size_t n, uint32_t c = 0xFFFFFFFFu) { for (size_t i = 0; i < n; ++i) c = crc_table[(c ^ b[i]) & 255] ^ (c >> 8); return c; }
static void be32(std::vector<uint8_t>& v, uint32_t x) { v.push_back(x >> 24); v.push_back(x >> 16); v.push_back(x >> 8); v.push_back(x); }
static void chunk(FILE* f, const char* type, const std::vector<uint8_t>& data) {
    std::vector<uint8_t> b; be32(b, (uint32_t)data.size()); b.insert(b.end(), type, type + 4); b.insert(b.end(), data.begin(), data.end());
    uint32_t c = crc(b.data() + 4, b.size() - 4) ^ 0xFFFFFFFFu; be32(b, c);
    fwrite(b.data(), 1, b.size(), f);
}
static void write_png(const std::string& path, const Canvas& cv) {
    std::vector<uint8_t> raw;
    for (int y = 0; y < cv.h; ++y) { raw.push_back(0); raw.insert(raw.end(), cv.px.begin() + (size_t)y * cv.w * 4, cv.px.begin() + (size_t)(y + 1) * cv.w * 4); }
    std::vector<uint8_t> z = { 0x78, 0x01 };
    size_t pos = 0;
    while (pos < raw.size() || raw.empty()) {
        size_t n = std::min<size_t>(65535, raw.size() - pos);
        bool last = pos + n >= raw.size();
        z.push_back(last ? 1 : 0); z.push_back(n & 255); z.push_back(n >> 8); z.push_back(~n & 255); z.push_back((~n >> 8) & 255);
        z.insert(z.end(), raw.begin() + pos, raw.begin() + pos + n);
        pos += n; if (last) break;
    }
    uint32_t a = 1, b = 0; for (uint8_t v : raw) { a = (a + v) % 65521; b = (b + a) % 65521; }
    be32(z, (b << 16) | a);
    FILE* f = fopen(path.c_str(), "wb"); if (!f) { fprintf(stderr, "cannot write %s\n", path.c_str()); return; }
    const uint8_t sig[8] = { 137,80,78,71,13,10,26,10 }; fwrite(sig, 1, 8, f);
    std::vector<uint8_t> ihdr; be32(ihdr, cv.w); be32(ihdr, cv.h); ihdr.insert(ihdr.end(), { 8, 6, 0, 0, 0 });
    chunk(f, "IHDR", ihdr); chunk(f, "IDAT", z); chunk(f, "IEND", {});
    fclose(f);
}

// ------------------------------------------------------------------ scan-line fill (convex + concave)
struct V2 { float x, y; };
static void scan_fill(const std::vector<V2>& v, int W, int H, const std::function<void(int, int)>& plot) {
    int n = (int)v.size(); if (n < 3) return;
    float ymin = v[0].y, ymax = v[0].y;
    for (auto& p : v) { ymin = std::min(ymin, p.y); ymax = std::max(ymax, p.y); }
    int y0 = std::max(0, (int)std::ceil(ymin - 0.5f)), y1 = std::min(H - 1, (int)std::ceil(ymax - 0.5f) - 1);
    std::vector<float> xs;
    for (int y = y0; y <= y1; ++y) {
        float yc = y + 0.5f; xs.clear();
        for (int i = 0; i < n; ++i) {
            const V2& p = v[i]; const V2& q = v[(i + 1) % n];
            if ((p.y <= yc && yc < q.y) || (q.y <= yc && yc < p.y)) xs.push_back(p.x + (yc - p.y) * (q.x - p.x) / (q.y - p.y));
        }
        std::sort(xs.begin(), xs.end());
        for (size_t k = 0; k + 1 < xs.size(); k += 2) {
            int xa = std::max(0, (int)std::ceil(xs[k] - 0.5f)), xb = std::min(W, (int)std::ceil(xs[k + 1] - 0.5f));
            for (int x = xa; x < xb; ++x) plot(x, y);
        }
    }
}

// ------------------------------------------------------------------ 2D affine matrices (local y points UP)
struct A2 {
    float a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;      // [a c tx; b d ty]
    A2 operator*(const A2& o) const {
        return { a * o.a + c * o.b, b * o.a + d * o.b, a * o.c + c * o.d, b * o.c + d * o.d, a * o.tx + c * o.ty + tx, b * o.tx + d * o.ty + ty };
    }
    V2 xf(V2 p) const { return { a * p.x + c * p.y + tx, b * p.x + d * p.y + ty }; }
    static A2 T(float x, float y) { A2 m; m.tx = x; m.ty = y; return m; }
    static A2 S(float x, float y) { A2 m; m.a = x; m.d = y; return m; }
    static A2 R(float t) { A2 m; m.a = cosf(t); m.b = sinf(t); m.c = -sinf(t); m.d = cosf(t); return m; }   // CCW
};

using Poly = std::vector<V2>;
static Poly P_rect(float x0, float y0, float x1, float y1) { return { {x0,y0},{x1,y0},{x1,y1},{x0,y1} }; }
static Poly P_ell(float cx, float cy, float rx, float ry, int seg = 14) {
    Poly p; for (int i = 0; i < seg; ++i) { float a = i * 2 * PI_F / seg; p.push_back({ cx + rx * cosf(a), cy + ry * sinf(a) }); } return p;
}
static Poly P(std::initializer_list<float> v) { Poly p; auto it = v.begin(); while (it != v.end()) { float a = *it++; if (it == v.end()) break; p.push_back({ a, *it++ }); } return p; }
static Poly P_seg(V2 a, V2 b, float w) {                     // thick segment (quad)
    float dx = b.x - a.x, dy = b.y - a.y, L = sqrtf(dx * dx + dy * dy); if (L < 1e-4f) L = 1e-4f;
    float nx = -dy / L * w * 0.5f, ny = dx / L * w * 0.5f;
    return { {a.x + nx, a.y + ny}, {b.x + nx, b.y + ny}, {b.x - nx, b.y - ny}, {a.x - nx, a.y - ny} };
}

// ------------------------------------------------------------------ painter: local polygons -> one cell
// Mode OUTLINE draws every part in the outline colour nudged 1px in 4 directions;
// mode NORMAL then paints the real colours on top -> crisp 1px pixel-art outline.
struct Painter {
    Canvas* cv; int ox, oy, cw, ch;                         // cell origin (local 0,0 = feet) + cell size
    int cellX, cellY;
    bool outline = false; float ddx = 0, ddy = 0; C3 outC{ 20, 16, 22 };
    void poly(const A2& M, const Poly& p, C3 c, float alpha = 1.f, bool noOutline = false) {
        if (outline && (noOutline || alpha < 0.99f)) return;
        std::vector<V2> v;
        for (auto& q : p) { V2 w = M.xf(q); v.push_back({ ox + w.x + ddx, oy - w.y + ddy }); }
        C3 col = outline ? outC : c;
        int X0 = cellX, Y0 = cellY;
        scan_fill(v, cv->w, cv->h, [&](int x, int y) {
            if (x < X0 || y < Y0 || x >= X0 + cw || y >= Y0 + ch) return;   // clip to this cell
            if (alpha >= 0.99f) cv->set(x, y, col); else cv->blend(x, y, col, alpha);
        });
    }
};
// render a figure with its pixel outline into one sheet cell
static void draw_cell(Canvas& cv, int cellX, int cellY, int cw, int ch, int footX, int footY,
                      const std::function<void(Painter&)>& draw) {
    Painter pt{ &cv, cellX + footX, cellY + footY, cw, ch, cellX, cellY };
    const float off[4][2] = { {1,0}, {-1,0}, {0,1}, {0,-1} };
    pt.outline = true;
    for (auto& o : off) { pt.ddx = o[0]; pt.ddy = o[1]; draw(pt); }
    pt.outline = false; pt.ddx = pt.ddy = 0;
    draw(pt);
}

// ------------------------------------------------------------------ helpers
static inline uint32_t hsh(uint32_t x) { x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16; return x; }
static inline float h01(int i) { return (hsh((uint32_t)i) & 0xFFFFFF) / 16777215.f; }
static inline float h2(int x, int y) { return h01((int)(hsh((uint32_t)x * 0x9E3779B1u) ^ ((uint32_t)y * 0x85EBCA77u))); }
static float pnoise(float x, float y, int P) {                // periodic value noise (tileable)
    int ix = (int)floorf(x), iy = (int)floorf(y); float fx = x - ix, fy = y - iy;
    auto g = [&](int a, int b) { a %= P; if (a < 0) a += P; b %= P; if (b < 0) b += P; return h2(a, b); };
    float sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    float a = g(ix, iy), b = g(ix + 1, iy), c = g(ix, iy + 1), d = g(ix + 1, iy + 1);
    float top = a + (b - a) * sx, bot = c + (d - c) * sx;
    return top + (bot - top) * sy;
}
static const float BAYER[4][4] = { {0,8,2,10}, {12,4,14,6}, {3,11,1,9}, {15,7,13,5} };
static inline C3 tone4(C3 a, C3 b, float n, int x, int y) {   // 4 dithered tones = pixel-art texture
    int l = (int)floorf(n * 3.f + (BAYER[y & 3][x & 3] + 0.5f) / 16.f); l = std::clamp(l, 0, 3);
    return mix(a, b, l / 3.f);
}

// two-bone IK: rotation (CCW, 0 = pointing down) of upper and lower segment so the
// chain from `sh` reaches `t` (both in the same local frame)
static void ik2(V2 sh, V2 t, float l1, float l2, bool elbowBack, float& upper, float& lower) {
    float dx = t.x - sh.x, dy = t.y - sh.y, d = sqrtf(dx * dx + dy * dy);
    d = clampf(d, 0.5f, l1 + l2 - 0.05f);
    float phi = atan2f(dy, dx);
    float ca = clampf((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1);
    float al = acosf(ca) * (elbowBack ? 1.f : -1.f);
    float th1 = phi + al;
    V2 e{ sh.x + l1 * cosf(th1), sh.y + l1 * sinf(th1) };
    float th2 = atan2f(t.y - e.y, t.x - e.x);
    upper = th1 + PI_F / 2;          // our limbs point down (-y) at rotation 0
    lower = th2 - th1;
}

// ------------------------------------------------------------------ sheet layout bookkeeping
struct AnimInfo { std::string name; int frames; float fps; bool loop; };
static void write_sheet_json(const std::string& path, int cw, int ch, int footX, int footY, const std::vector<AnimInfo>& anims) {
    FILE* f = fopen(path.c_str(), "w"); if (!f) return;
    fprintf(f, "{\n \"cell\": [%d, %d],\n \"foot\": [%d, %d],\n \"animations\": [\n", cw, ch, footX, footY);
    for (size_t i = 0; i < anims.size(); ++i)
        fprintf(f, "  {\"name\": \"%s\", \"row\": %zu, \"frames\": %d, \"fps\": %.1f, \"loop\": %s}%s\n", anims[i].name.c_str(), i,
                anims[i].frames, anims[i].fps, anims[i].loop ? "true" : "false", i + 1 < anims.size() ? "," : "");
    fprintf(f, " ]\n}\n");
    fclose(f);
}

// anime motion smear: a crescent swept between two angles around a pivot
static Poly smear_arc(V2 c, float a0, float a1, float r, float thick, int seg = 18) {
    Poly p;
    for (int i = 0; i <= seg; ++i) { float t = (float)i / seg, a = a0 + (a1 - a0) * t; p.push_back({ c.x + r * cosf(a), c.y + r * sinf(a) }); }
    for (int i = seg; i >= 0; --i) {
        float t = (float)i / seg, a = a0 + (a1 - a0) * t, rr = r - thick * sinf(PI_F * t);
        p.push_back({ c.x + rr * cosf(a), c.y + rr * sinf(a) });
    }
    return p;
}

// ================================================================== THE HUNTER (player)
struct Pose {
    float bob = 0, lean = 0, rot = 0, sqx = 1, sqy = 1;
    float legF = 0, legB = 0, kneeF = 0.1f, kneeB = 0.1f;
    V2 staffC{ 10, 30 }; float staffA = 1.45f;            // staff centre + direction (0 = forward, pi/2 = up)
    float gripF = 2, gripB = -9;                           // hand positions along the staff
    bool twoHand = true; float armB = -0.3f, elbowB = 0.3f;
    float scarf = 0, trail = 4, hat = 0;
    bool smear = false; V2 smC{ 4, 34 }; float smA0 = 0, smA1 = 0, smR = 40, smT = 9; C3 smCol{ 255, 250, 236 };
};

static void draw_hunter(Painter& pt, const Pose& ps) {
    const C3 coat{ 52,86,84 }, coatSh{ 34,58,60 }, coatHi{ 88,126,112 }, trim{ 196,164,96 },
        pants{ 54,52,64 }, pantsSh{ 40,38,50 }, boots{ 62,44,34 }, wraps{ 176,166,146 },
        skin{ 226,180,146 }, skinSh{ 168,122,100 }, straw{ 210,176,104 }, strawSh{ 150,118,64 }, band{ 140,40,36 },
        scarf{ 176,48,40 }, scarfSh{ 118,32,30 }, wood{ 134,92,54 }, woodSh{ 92,62,38 }, metal{ 204,196,176 }, glint{ 246,240,206 };
    A2 base = A2::T(0, ps.bob) * A2::T(0, 22) * A2::R(ps.rot) * A2::T(0, -22) * A2::S(ps.sqx, ps.sqy);
    A2 body = base * A2::T(0, 21) * A2::R(-ps.lean) * A2::T(0, -21);

    if (ps.smear) pt.poly(body, smear_arc(ps.smC, ps.smA0, ps.smA1, ps.smR, ps.smT), ps.smCol, 0.85f);

    // staff geometry (in body space)
    V2 d{ cosf(ps.staffA), sinf(ps.staffA) };
    const float L = 54.f;
    V2 s0{ ps.staffC.x - d.x * L * 0.5f, ps.staffC.y - d.y * L * 0.5f }, s1{ ps.staffC.x + d.x * L * 0.5f, ps.staffC.y + d.y * L * 0.5f };
    V2 handF{ ps.staffC.x + d.x * ps.gripF, ps.staffC.y + d.y * ps.gripF };
    V2 handB{ ps.staffC.x + d.x * ps.gripB, ps.staffC.y + d.y * ps.gripB };
    V2 shF{ 3.5f, 36 }, shB{ -3.5f, 36.5f };
    float uaF, laF, uaB = ps.armB, laB = ps.elbowB;
    ik2(shF, handF, 6.f, 7.f, false, uaF, laF);
    if (ps.twoHand) ik2(shB, handB, 6.f, 7.f, false, uaB, laB);

    auto arm = [&](V2 sh, float ua, float la, float dk) {
        A2 A = body * A2::T(sh.x, sh.y) * A2::R(ua);
        pt.poly(A, P_rect(-2.1f, -6, 2.1f, 0.5f), mul(coat, dk));
        A2 E = A * A2::T(0, -6) * A2::R(la);
        pt.poly(E, P_rect(-1.8f, -5.6f, 1.8f, 0.4f), mul(wraps, dk));
        pt.poly(E, P_ell(0, -6.6f, 2.2f, 2.2f, 8), mul(skin, dk));
    };
    auto leg = [&](float hx, float th, float kn, float dk) {
        A2 Lg = base * A2::T(hx, 21) * A2::R(th);
        pt.poly(Lg, P_rect(-2.7f, -9.5f, 2.7f, 0.5f), mul(pants, dk));
        pt.poly(Lg, P_rect(0.7f, -9.5f, 2.7f, 0.5f), mul(pantsSh, dk), 1, true);
        A2 Sh = Lg * A2::T(0, -9) * A2::R(-kn);
        pt.poly(Sh, P_rect(-2.4f, -8, 2.4f, 0.5f), mul(wraps, dk * 0.92f));
        pt.poly(Sh, P({ -2.8f,-7.5f, 2.8f,-7.5f, 2.8f,-10.2f, 5.6f,-11.f, 5.6f,-12.5f, -2.8f,-12.5f }), mul(boots, dk));
    };
    auto staff = [&]() {
        pt.poly(body, P_seg(s0, s1, 2.6f), wood);
        V2 n{ -d.y * 0.7f, d.x * 0.7f };                                            // shaded underside
        pt.poly(body, P_seg({ s0.x - n.x, s0.y - n.y }, { s1.x - n.x, s1.y - n.y }, 0.9f), woodSh, 1, true);
        pt.poly(body, P_seg({ s1.x - d.x * 4, s1.y - d.y * 4 }, s1, 3.4f), metal);   // iron-shod tip
        pt.poly(body, P_seg(s0, { s0.x + d.x * 3, s0.y + d.y * 3 }, 3.2f), metal);
        pt.poly(body, P_seg({ s1.x - d.x * 8, s1.y - d.y * 8 }, { s1.x - d.x * 6, s1.y - d.y * 6 }, 3.6f), band, 1, true);
    };
    // scarf tails stream behind
    float w1 = sinf(ps.scarf) * 1.6f, w2 = sinf(ps.scarf + 1.3f) * 1.8f;
    pt.poly(body, P({ -2,39.5f, -4.5f,37, -9 - ps.trail,34 + w1, -14 - ps.trail * 1.4f,35.5f + w2, -12 - ps.trail * 1.3f,37.5f + w2, -6 - ps.trail * 0.5f,38.5f + w1 }), scarfSh);
    pt.poly(body, P({ -2,38.5f, -4,36.5f, -8 - ps.trail * 0.8f,32 + w2, -11 - ps.trail,31 + w1, -9 - ps.trail,33.5f + w1 }), scarf);

    if (!ps.twoHand) arm(shB, uaB, laB, 0.8f);
    leg(-1.4f, ps.legB, ps.kneeB, 0.82f);
    if (ps.twoHand) arm(shB, uaB, laB, 0.8f);
    // coat with swaying tails, sash, trim
    pt.poly(body, P({ -7.8f,10, 7.6f,10.5f, 6.4f,26, 6.8f,37, 3,39.6f, -3,39.6f, -6.8f,37, -6.6f,26 }), coat);
    pt.poly(body, P({ 1.8f,10.5f, 7.6f,10.5f, 6.4f,26, 6.8f,37, 3,39.6f, 1.8f,39.6f }), coatSh, 1, true);
    pt.poly(body, P({ -7.8f,10, -5.8f,10, -4.8f,26, -5.2f,36.4f, -6.8f,37, -6.6f,26 }), coatHi, 1, true);
    pt.poly(body, P_rect(-7, 22.6f, 7, 25.4f), band);
    pt.poly(body, P({ 0.5f,39.6f, 3,39.6f, 0.8f,26, -0.6f,26 }), trim, 1, true);
    leg(1.4f, ps.legF, ps.kneeF, 1.f);
    staff();
    arm(shF, uaF, laF, 1.f);
    // head: face in the shade of the hat, one glinting eye
    A2 head = body * A2::T(0.6f, 45.5f) * A2::R(-ps.hat * 0.5f) * A2::T(-0.6f, -45.5f);
    pt.poly(head, P_ell(0.8f, 45.2f, 5.6f, 6.0f, 16), skin);
    pt.poly(head, P_ell(0.8f, 48.6f, 6.0f, 3.2f, 14), skinSh, 1, true);
    pt.poly(head, P_rect(3.6f, 45.4f, 5.2f, 46.6f), glint, 1, true);
    // scarf wrapped at the neck
    pt.poly(body, P({ -5,36.4f, 5.4f,36.4f, 4.8f,40.6f, -4.4f,40.6f }), scarf);
    pt.poly(body, P_rect(1.4f, 36.4f, 5.4f, 37.6f), scarfSh, 1, true);
    // conical straw hat (concave brim + cone)
    A2 hatM = head * A2::T(0.6f, 50.5f) * A2::R(ps.hat) * A2::T(-0.6f, -50.5f);
    pt.poly(hatM, P({ -14,49.6f, -6,50.6f, 7,50.8f, 15,50.2f, 11.5f,52.2f, 1,52.6f, -11,52 }), strawSh);
    pt.poly(hatM, P({ -9,51.6f, 9.6f,51.8f, 1.8f,60.8f, -1.4f,60.8f }), straw);
    pt.poly(hatM, P({ 1.6f,51.8f, 9.6f,51.8f, 1.8f,60.8f }), strawSh, 1, true);
    pt.poly(hatM, P({ -8.6f,51.6f, 9.2f,51.8f, 8.6f,53.6f, -8,53.4f }), band, 1, true);
}

static void build_hunter(const std::string& dir) {
    const int CW = 128, CH = 100, FX = 64, FY = 86;
    std::vector<AnimInfo> anims;
    std::vector<std::vector<Pose>> rows;
    auto add = [&](const char* nm, float fps, bool loop, std::vector<Pose> fr) { anims.push_back({ nm, (int)fr.size(), fps, loop }); rows.push_back(fr); };

    // idle: staff planted beside him, breathing, scarf drifting
    { std::vector<Pose> f; for (int i = 0; i < 4; ++i) { Pose p; float s = sinf(i * PI_F / 2);
        p.bob = -0.5f + 0.5f * s; p.legF = 0.12f; p.legB = -0.1f; p.staffC = { 11, 26 }; p.staffA = 1.42f; p.gripF = 9; p.gripB = 3;
        p.scarf = i * 1.57f; p.trail = 3; p.lean = 0.03f; f.push_back(p); } add("idle", 5, true, f); }
    // run: staff carried low and trailing, scarf streaming
    { std::vector<Pose> f; for (int i = 0; i < 6; ++i) { Pose p; float ph = i * 2 * PI_F / 6, s = sinf(ph);
        p.lean = 0.2f; p.bob = fabsf(cosf(ph)) * 1.6f - 0.8f; p.legF = s * 0.75f; p.legB = -s * 0.75f;
        p.kneeF = 0.2f + 0.7f * std::max(0.f, -s); p.kneeB = 0.2f + 0.7f * std::max(0.f, s);
        p.staffC = { -4, 27 }; p.staffA = PI_F - 0.28f; p.gripF = -10; p.gripB = -16; p.twoHand = false; p.armB = -s * 0.6f;
        p.scarf = ph * 2; p.trail = 9; p.hat = -0.05f; f.push_back(p); } add("run", 12, true, f); }
    // jump (rising) and fall
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.legF = 0.9f; p.kneeF = 1.6f; p.legB = -0.2f; p.kneeB = 1.0f;
        p.staffC = { 6, 44 }; p.staffA = 0.5f; p.gripF = 4; p.gripB = -6; p.scarf = i * 2.f; p.trail = 7; p.sqy = 1.04f; p.lean = 0.05f; f.push_back(p); }
      add("jump", 8, true, f); }
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.legF = 0.35f; p.kneeF = 0.4f; p.legB = -0.3f; p.kneeB = 0.7f;
        p.staffC = { 4, 36 }; p.staffA = 0.15f + i * 0.05f; p.gripF = 6; p.gripB = -4; p.scarf = i * 2.5f + 1; p.trail = 8; p.hat = 0.1f; f.push_back(p); }
      add("fall", 8, true, f); }
    // attack 1: horizontal sweep (crowd control) with a big crescent smear
    { std::vector<Pose> f;
      Pose a; a.lean = -0.15f; a.legF = 0.4f; a.legB = -0.5f; a.staffC = { -6, 34 }; a.staffA = PI_F - 0.05f; a.gripF = -4; a.gripB = -10; a.trail = 5; f.push_back(a);
      Pose b = a; b.lean = 0.12f; b.staffC = { 10, 34 }; b.staffA = 0.45f; b.gripF = -12; b.gripB = -18;
      b.smear = true; b.smC = { 2, 34 }; b.smA0 = PI_F * 0.95f; b.smA1 = 0.45f; b.smR = 46; b.smT = 10; f.push_back(b);
      Pose c = b; c.lean = 0.22f; c.staffC = { 22, 32 }; c.staffA = -0.08f; c.gripF = -20; c.gripB = -26; c.smA0 = 1.2f; c.smA1 = -0.1f; c.smT = 7; f.push_back(c);
      Pose d = c; d.smear = false; d.lean = 0.18f; d.staffC = { 18, 26 }; d.staffA = -0.55f; f.push_back(d);
      Pose e = d; e.lean = 0.08f; e.staffC = { 12, 26 }; e.staffA = -1.0f; e.gripF = -14; e.gripB = -20; f.push_back(e);
      add("attack1", 16, false, f); }
    // attack 2: rising reverse sweep
    { std::vector<Pose> f;
      Pose a; a.lean = 0.1f; a.legF = 0.5f; a.legB = -0.4f; a.staffC = { 14, 22 }; a.staffA = -0.7f; a.gripF = -12; a.gripB = -18; f.push_back(a);
      Pose b = a; b.staffC = { 12, 40 }; b.staffA = 0.9f; b.smear = true; b.smC = { 2, 30 }; b.smA0 = -0.7f; b.smA1 = 1.6f; b.smR = 44; b.smT = 9; f.push_back(b);
      Pose c = b; c.lean = -0.05f; c.staffC = { 2, 46 }; c.staffA = 1.9f; c.gripF = -6; c.gripB = -12; c.smA0 = 0.4f; c.smA1 = 2.1f; c.smT = 6; f.push_back(c);
      Pose d = c; d.smear = false; d.staffC = { -2, 44 }; d.staffA = 2.3f; f.push_back(d);
      Pose e = d; e.staffC = { 4, 34 }; e.staffA = 1.6f; e.gripF = 4; e.gripB = -4; f.push_back(e);
      add("attack2", 16, false, f); }
    // heavy: vertical overhead smash (single target), long windup, impact squash
    { std::vector<Pose> f;
      Pose a; a.lean = -0.18f; a.bob = -1; a.legF = 0.5f; a.legB = -0.6f; a.kneeF = 0.5f; a.staffC = { -4, 50 }; a.staffA = 2.5f; a.gripF = -12; a.gripB = -18; a.hat = -0.12f; f.push_back(a);
      Pose b = a; b.lean = -0.25f; b.staffC = { -8, 52 }; b.staffA = 2.75f; f.push_back(b);
      Pose c = b; c.lean = 0.25f; c.bob = -2; c.staffC = { 16, 40 }; c.staffA = 0.6f; c.smear = true; c.smC = { 2, 30 }; c.smA0 = 2.6f; c.smA1 = 0.2f; c.smR = 50; c.smT = 12; c.hat = 0.1f; f.push_back(c);
      Pose d = c; d.lean = 0.35f; d.bob = -4; d.sqx = 1.08f; d.sqy = 0.9f; d.kneeF = 1.0f; d.kneeB = 0.8f; d.staffC = { 26, 14 }; d.staffA = -0.75f; d.gripF = -22; d.gripB = -28;
      d.smA0 = 1.0f; d.smA1 = -0.7f; d.smT = 8; f.push_back(d);
      Pose e = d; e.smear = false; e.sqx = 1.04f; e.sqy = 0.96f; f.push_back(e);
      Pose g = e; g.lean = 0.15f; g.bob = -1.5f; g.sqx = g.sqy = 1; g.staffC = { 18, 18 }; g.staffA = -0.9f; f.push_back(g);
      add("heavy", 14, false, f); }
    // air attack: spinning staff, full-circle smear
    { std::vector<Pose> f; for (int i = 0; i < 4; ++i) { Pose p; float a = -i * PI_F / 2;
        p.legF = 0.8f; p.kneeF = 1.4f; p.legB = -0.1f; p.kneeB = 1.2f; p.staffC = { 4, 32 }; p.staffA = a; p.gripF = 2; p.gripB = -4;
        p.smear = true; p.smC = { 4, 32 }; p.smA0 = a + 1.6f; p.smA1 = a; p.smR = 28; p.smT = 8; p.trail = 8; p.scarf = i * 1.6f; f.push_back(p); }
      add("air", 18, true, f); }
    // dodge roll: tucked body rotating forward
    { std::vector<Pose> f; for (int i = 0; i < 5; ++i) { Pose p; p.rot = -i * 2 * PI_F / 5; p.bob = -8;
        p.legF = 1.4f; p.kneeF = 2.2f; p.legB = 1.0f; p.kneeB = 2.2f; p.lean = 0.7f; p.staffC = { 0, 26 }; p.staffA = 0.1f; p.gripF = 2; p.gripB = -3;
        p.trail = 2; p.scarf = i * 1.2f; f.push_back(p); } add("dodge", 14, false, f); }
    // block: staff braced diagonally in front
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.lean = -0.08f; p.legF = 0.45f; p.legB = -0.5f; p.kneeF = 0.5f; p.bob = -1.5f - i * 0.5f;
        p.staffC = { 12, 36 }; p.staffA = 1.15f; p.gripF = 9; p.gripB = -5; p.trail = 3; p.scarf = i * 2.f; f.push_back(p); } add("block", 6, true, f); }
    // hurt: recoil
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.lean = -0.35f - i * 0.05f; p.legF = 0.4f; p.legB = -0.3f; p.staffC = { -4, 34 }; p.staffA = 2.1f; p.gripF = -6; p.gripB = -12;
        p.hat = -0.25f; p.trail = 6; f.push_back(p); } add("hurt", 8, false, f); }
    // death: crumples backward
    { std::vector<Pose> f; for (int i = 0; i < 4; ++i) { Pose p; float t = i / 3.f; p.rot = t * 1.45f; p.bob = -t * 12; p.lean = -0.2f;
        p.legF = 0.5f * t; p.legB = 0.2f; p.staffC = { -10 - 8 * t, 26 - 10 * t }; p.staffA = 2.4f + t * 0.6f; p.twoHand = false; p.armB = 1.2f * t; p.hat = -0.4f * t;
        p.trail = 2; f.push_back(p); } add("death", 7, false, f); }
    // launch: rising uppercut that throws the enemy into the air (vertical crescent)
    { std::vector<Pose> f;
      Pose a; a.lean = -0.1f; a.bob = -3; a.legF = 0.5f; a.legB = -0.5f; a.kneeF = 1.0f; a.kneeB = 0.9f; a.staffC = { 14, 16 }; a.staffA = -0.9f; a.gripF = -12; a.gripB = -18; a.trail = 4; f.push_back(a);
      Pose b = a; b.lean = 0.0f; b.bob = 0; b.kneeF = 0.6f; b.staffC = { 16, 30 }; b.staffA = 0.3f;
      b.smear = true; b.smC = { 2, 30 }; b.smA0 = -0.9f; b.smA1 = 0.6f; b.smR = 46; b.smT = 10; f.push_back(b);
      Pose c = b; c.bob = 3; c.lean = -0.1f; c.legF = 0.6f; c.kneeF = 1.2f; c.legB = -0.3f; c.staffC = { 10, 46 }; c.staffA = 1.3f; c.smA0 = -0.3f; c.smA1 = 1.5f; c.smT = 8; c.hat = -0.1f; f.push_back(c);
      Pose d = c; d.smear = false; d.bob = 4; d.staffC = { 6, 50 }; d.staffA = 1.75f; f.push_back(d);
      Pose e = d; e.bob = 2; e.staffC = { 6, 46 }; e.staffA = 1.6f; e.gripF = 4; e.gripB = -4; f.push_back(e);
      add("launch", 16, false, f); }
    // dive: plunging downward strike, staff pointing at the ground
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.lean = 0.3f; p.legF = 1.0f; p.kneeF = 1.8f; p.legB = 0.6f; p.kneeB = 1.6f;
        p.staffC = { 6, 10 }; p.staffA = -1.45f; p.gripF = -14; p.gripB = -20; p.trail = 12; p.scarf = i * 2.f; p.hat = 0.15f;
        p.smear = true; p.smC = { 6, 22 }; p.smA0 = -1.25f - 0.1f * i; p.smA1 = -1.85f; p.smR = 26; p.smT = 6; f.push_back(p); }
      add("dive", 12, true, f); }
    // air dash: horizontal burst, body stretched forward, staff trailing
    { std::vector<Pose> f; for (int i = 0; i < 2; ++i) { Pose p; p.lean = 0.55f; p.bob = 2; p.legF = -0.2f; p.kneeF = 1.2f; p.legB = -0.9f; p.kneeB = 0.6f;
        p.staffC = { -6, 30 }; p.staffA = PI_F - 0.15f; p.twoHand = false; p.gripF = -10; p.gripB = -16; p.armB = -1.0f;
        p.trail = 16; p.scarf = i * 2.2f; p.hat = -0.15f; p.sqx = 1.06f; p.sqy = 0.95f; f.push_back(p); }
      add("airdash", 14, true, f); }
    // staff vault: plants the staff in thin air and springs off it (double jump)
    { std::vector<Pose> f;
      Pose a; a.bob = 6; a.lean = 0.1f; a.legF = 1.1f; a.kneeF = 1.8f; a.legB = 0.6f; a.kneeB = 1.5f; a.staffC = { 14, 10 }; a.staffA = -1.2f; a.gripF = -16; a.gripB = -22; a.trail = 6; f.push_back(a);
      Pose b = a; b.bob = 10; b.legF = 1.3f; b.kneeF = 0.4f; b.staffC = { 2, 8 }; b.staffA = -1.75f; b.scarf = 1.5f; f.push_back(b);
      Pose c; c.bob = 6; c.legF = 0.9f; c.kneeF = 1.4f; c.legB = -0.2f; c.kneeB = 1.0f; c.staffC = { 6, 40 }; c.staffA = 0.6f; c.gripF = 4; c.gripB = -6; c.trail = 9; c.scarf = 3; f.push_back(c);
      add("vault", 14, false, f); }
    // parry: a quick flick of the staff that knocks the attack aside
    { std::vector<Pose> f;
      Pose a; a.lean = -0.05f; a.legF = 0.45f; a.legB = -0.5f; a.kneeF = 0.5f; a.staffC = { 14, 34 }; a.staffA = 1.3f; a.gripF = 9; a.gripB = -5; f.push_back(a);
      Pose b = a; b.lean = 0.12f; b.staffC = { 18, 34 }; b.staffA = 0.2f; b.smear = true; b.smC = { 8, 34 }; b.smA0 = 1.3f; b.smA1 = 0.1f; b.smR = 30; b.smT = 7;
      b.smCol = { 160, 240, 255 }; f.push_back(b);
      Pose c = b; c.smear = false; c.staffC = { 16, 32 }; c.staffA = 0.5f; f.push_back(c);
      add("parry", 18, false, f); }
    // special: staff spun overhead, gathering spirit light (Moon Breaker wind-up)
    { std::vector<Pose> f; for (int i = 0; i < 4; ++i) { Pose p; float a = i * PI_F / 2;
        p.lean = -0.05f; p.bob = -1; p.legF = 0.5f; p.legB = -0.5f; p.kneeF = 0.4f; p.staffC = { 3, 48 }; p.staffA = a; p.gripF = 0; p.gripB = -3;
        p.smear = true; p.smC = { 3, 48 }; p.smA0 = a + 2.6f; p.smA1 = a; p.smR = 28; p.smT = 10; p.smCol = { 255, 222, 120 };
        p.trail = 10; p.scarf = i * 1.6f; p.hat = -0.1f; f.push_back(p); }
      add("special", 16, true, f); }

    int maxF = 0; for (auto& r : rows) maxF = std::max(maxF, (int)r.size());
    Canvas cv(CW * maxF, CH * (int)rows.size());
    for (size_t r = 0; r < rows.size(); ++r)
        for (size_t i = 0; i < rows[r].size(); ++i) {
            const Pose& ps = rows[r][i];
            draw_cell(cv, (int)i * CW, (int)r * CH, CW, CH, FX, FY, [&](Painter& pt) { draw_hunter(pt, ps); });
        }
    write_png(dir + "/hunter.png", cv);
    write_sheet_json(dir + "/hunter.json", CW, CH, FX, FY, anims);
    printf("hunter: %zu animations\n", anims.size());
}

// ================================================================== HOPPER FROG (small enemy)
static void draw_hopper(Painter& pt, float sqx, float sqy, bool air, float tongue, bool hurt, bool dead, int seed) {
    C3 base{ 98,114,58 }, dk{ 66,80,42 }, hi{ 134,146,80 }, belly{ 176,164,108 }, wart{ 74,88,44 };
    const C3 iris{ 214,182,70 }, pupil{ 20,20,16 }, mouth{ 38,44,28 }, tong{ 214,104,124 };
    if (hurt) { base = { 230,230,220 }; dk = { 200,200,190 }; hi = { 255,255,250 }; belly = { 255,250,240 }; }
    A2 M = A2::S(1.45f * sqx, 1.45f * sqy) * (dead ? A2::T(0, 18) * A2::R(PI_F) * A2::T(0, -18) : A2());
    if (tongue > 0) {
        pt.poly(M, P_seg({ 10, 9 }, { 10 + tongue, 9.5f }, 2.6f), tong);
        pt.poly(M, P_ell(10 + tongue, 9.5f, 2.8f, 2.6f, 10), tong);
    }
    if (air) pt.poly(M, P({ -3,6, -19,-2, -17,-5, -1,2 }), dk);
    else { pt.poly(M, P_ell(-7, 5, 8, 5.5f, 12), dk); pt.poly(M, P_ell(-9.5f, 0.9f, 6.5f, 1.9f, 10), mul(dk, 0.85f)); }
    pt.poly(M, P_ell(1, 8, 12.6f, 8.8f, 18), dk);
    pt.poly(M, P_ell(-0.6f, 9.3f, 11.6f, 7.9f, 18), base);
    pt.poly(M, P_ell(-5, 13, 4.6f, 2.2f, 10), hi, 1, true);
    for (int i = 0; i < 5; ++i) pt.poly(M, P_ell(-8 + h01(seed + i) * 13, 8 + h01(seed + 10 + i) * 6, 1.3f, 1.f, 6), wart, 1, true);
    pt.poly(M, P_ell(5.5f, 5.2f, 5.8f, 3.6f, 12), belly);
    pt.poly(M, P_ell(7.8f, 1.4f, 3.6f, 1.8f, 8), base);
    for (float ex : { -2.2f, 5.2f }) {
        pt.poly(M, P_ell(ex, 16.2f, 3.9f, 3.9f, 12), dk);
        if (dead) pt.poly(M, P_rect(ex - 2, 15.8f, ex + 2, 16.8f), pupil, 1, true);
        else { pt.poly(M, P_ell(ex + 0.3f, 16.5f, 2.5f, 2.5f, 10), iris, 1, true); pt.poly(M, P_rect(ex + 0.7f, 15.2f, ex + 1.7f, 17.8f), pupil, 1, true); }
    }
    pt.poly(M, P({ 4.5f,8.2f, 12.6f,9.4f, 12.6f,10.2f, 4.5f,9.f }), mouth, 1, true);
}

static void build_hopper(const std::string& dir) {
    const int CW = 160, CH = 56, FX = 80, FY = 52;
    std::vector<AnimInfo> anims;
    std::vector<std::vector<std::function<void(Painter&)>>> rows;
    auto add = [&](const char* nm, float fps, bool loop, std::vector<std::function<void(Painter&)>> fr) { anims.push_back({ nm, (int)fr.size(), fps, loop }); rows.push_back(fr); };
    add("idle", 3, true, { [](Painter& p) { draw_hopper(p, 1, 1, false, 0, false, false, 7); }, [](Painter& p) { draw_hopper(p, 1.04f, 0.96f, false, 0, false, false, 7); } });
    add("hop", 10, false, { [](Painter& p) { draw_hopper(p, 1.2f, 0.8f, false, 0, false, false, 7); }, [](Painter& p) { draw_hopper(p, 0.85f, 1.2f, true, 0, false, false, 7); },
                            [](Painter& p) { draw_hopper(p, 0.95f, 1.05f, true, 0, false, false, 7); } });
    add("tongue", 14, false, { [](Painter& p) { draw_hopper(p, 1.15f, 0.85f, false, 0, false, false, 7); }, [](Painter& p) { draw_hopper(p, 0.95f, 1.05f, false, 26, false, false, 7); },
                               [](Painter& p) { draw_hopper(p, 0.95f, 1.05f, false, 38, false, false, 7); }, [](Painter& p) { draw_hopper(p, 1, 1, false, 14, false, false, 7); } });
    add("hurt", 8, false, { [](Painter& p) { draw_hopper(p, 1.15f, 0.85f, false, 0, true, false, 7); } });
    add("death", 6, false, { [](Painter& p) { draw_hopper(p, 1.3f, 0.6f, false, 0, false, true, 7); }, [](Painter& p) { draw_hopper(p, 1.5f, 0.35f, false, 0, false, true, 7); } });
    int maxF = 0; for (auto& r : rows) maxF = std::max(maxF, (int)r.size());
    Canvas cv(CW * maxF, CH * (int)rows.size());
    for (size_t r = 0; r < rows.size(); ++r) for (size_t i = 0; i < rows[r].size(); ++i) draw_cell(cv, (int)i * CW, (int)r * CH, CW, CH, FX, FY, rows[r][i]);
    write_png(dir + "/hopper.png", cv);
    write_sheet_json(dir + "/hopper.json", CW, CH, FX, FY, anims);
    printf("hopper: %zu animations\n", anims.size());
}

// ================================================================== BRUTE FROG (big brawler, Brekekex's buff frogs)
struct BPose { float bob = 0, lean = 0, armF = -0.3f, elbowF = 1.2f, armB = 0.4f, elbowB = 1.0f, legF = 0.1f, legB = -0.1f, sqx = 1, sqy = 1, rot = 0;
               bool smear = false; float smA0 = 0, smA1 = 0; bool hurt = false, dead = false; };
static void draw_brute(Painter& pt, const BPose& b) {
    C3 skin{ 82,108,60 }, skinSh{ 56,76,44 }, skinHi{ 124,146,80 }, belly{ 204,192,140 }, bellySh{ 164,152,108 }, wart{ 62,84,46 };
    const C3 iris{ 226,170,60 }, pupil{ 18,14,12 }, mouth{ 40,30,26 }, paint{ 168,40,40 }, wrapC{ 150,140,120 };
    if (b.hurt) { skin = { 236,236,228 }; skinSh = { 210,210,200 }; skinHi = { 255,255,250 }; belly = { 255,252,244 }; bellySh = { 230,226,214 }; }
    A2 base = A2::T(0, b.bob) * A2::T(0, 26) * A2::R(b.rot) * A2::T(0, -26) * A2::S(b.sqx, b.sqy);
    A2 body = base * A2::T(0, 20) * A2::R(-b.lean) * A2::T(0, -20);
    if (b.smear) pt.poly(body, smear_arc({ 6, 40 }, b.smA0, b.smA1, 40, 11), { 255,248,230 }, 0.85f);
    auto arm = [&](V2 sh, float ua, float el, float dk) {
        A2 A = body * A2::T(sh.x, sh.y) * A2::R(ua);
        pt.poly(A, P_ell(0, -6, 6.4f, 8.5f, 14), mul(skin, dk));
        A2 E = A * A2::T(0, -12) * A2::R(el);
        pt.poly(E, P_ell(0, -5, 5.2f, 7.2f, 14), mul(skin, dk));
        pt.poly(E, P_rect(-4.6f, -9, 4.6f, -6), mul(wrapC, dk));
        pt.poly(E, P_ell(0, -12.5f, 6.4f, 5.6f, 14), mul(skinHi, dk));                   // fist
    };
    auto leg = [&](float hx, float th, float dk) {
        A2 Lg = base * A2::T(hx, 20) * A2::R(th);
        pt.poly(Lg, P_ell(0, -6, 7.4f, 8.6f, 14), mul(skin, dk));
        pt.poly(Lg, P_ell(0, -15, 5.4f, 6, 12), mul(skinSh, dk));
        pt.poly(Lg, P_ell(4, -19.6f, 8.6f, 2.6f, 12), mul(skinSh, dk));                 // webbed foot
    };
    arm({ -14, 48 }, b.armB, b.elbowB, 0.78f);
    leg(-7, b.legB, 0.82f);
    leg(7, b.legF, 1.f);
    pt.poly(body, P({ -17,18, 17,18, 20,32, 19,48, 12,56, -12,56, -19,48, -20,32 }), skin);   // barrel torso
    pt.poly(body, P({ 4,18, 17,18, 20,32, 19,48, 12,56, 4,56 }), skinSh, 1, true);
    pt.poly(body, P({ -10,19, 10,19, 12,32, 10,46, -10,46, -12,32 }), belly, 1, true);
    for (float y : { 26.f, 33.f, 40.f }) pt.poly(body, P_rect(-8, y, 8, y + 1.2f), bellySh, 1, true);   // abs
    pt.poly(body, P_rect(-0.6f, 21, 0.6f, 45), bellySh, 1, true);
    for (int i = 0; i < 7; ++i) pt.poly(body, P_ell(-16 + h01(i + 3) * 8, 24 + h01(i + 9) * 28, 1.4f, 1.1f, 6), wart, 1, true);
    pt.poly(body, P({ -18,40, -12,44, -12,46, -18,43 }), paint, 1, true);                 // war paint
    pt.poly(body, P_ell(-14, 50, 8.5f, 7.5f, 14), skinSh);                               // shoulders
    pt.poly(body, P_ell(14, 50, 8.5f, 7.5f, 14), skin);
    // head: wide and flat, eyes on top
    A2 head = body * A2::T(2, 58);
    pt.poly(head, P_ell(0, 0, 16, 9.5f, 20), skin);
    pt.poly(head, P_ell(3, -3, 12, 5, 16), skinSh, 1, true);
    pt.poly(head, P({ -6,-3.5f, 16,-2.5f, 16,-1.2f, -6,-2.2f }), mouth, 1, true);
    pt.poly(head, P_rect(-8, 2.5f, 8, 4.2f), paint, 1, true);
    for (float ex : { -5.f, 7.f }) {
        pt.poly(head, P_ell(ex, 8.5f, 5.2f, 5, 14), skin);
        if (b.dead) pt.poly(head, P_rect(ex - 3, 8, ex + 3, 9.4f), pupil, 1, true);
        else { pt.poly(head, P_ell(ex + 0.5f, 8.8f, 3.4f, 3.2f, 12), iris, 1, true); pt.poly(head, P_rect(ex - 1.6f, 8.2f, ex + 2.6f, 9.6f), pupil, 1, true); }
    }
    arm({ 14, 48 }, b.armF, b.elbowF, 1.f);
}
static void build_brute(const std::string& dir) {
    const int CW = 128, CH = 112, FX = 64, FY = 102;
    std::vector<AnimInfo> anims; std::vector<std::vector<BPose>> rows;
    auto add = [&](const char* nm, float fps, bool loop, std::vector<BPose> fr) { anims.push_back({ nm, (int)fr.size(), fps, loop }); rows.push_back(fr); };
    { std::vector<BPose> f; for (int i = 0; i < 2; ++i) { BPose p; p.sqy = 1 + 0.025f * i; p.sqx = 1 - 0.015f * i; f.push_back(p); } add("idle", 3, true, f); }
    { std::vector<BPose> f; for (int i = 0; i < 4; ++i) { BPose p; float s = sinf(i * PI_F / 2); p.legF = s * 0.45f; p.legB = -s * 0.45f; p.bob = fabsf(cosf(i * PI_F / 2)) * 2 - 1;
        p.lean = 0.08f; p.armF = -0.3f - s * 0.25f; p.armB = 0.4f + s * 0.25f; f.push_back(p); } add("walk", 7, true, f); }
    { std::vector<BPose> f;
      BPose a; a.lean = -0.15f; a.armF = -1.6f; a.elbowF = 2.0f; a.legF = 0.3f; a.legB = -0.4f; f.push_back(a);
      BPose b = a; b.lean = 0.25f; b.armF = 1.55f; b.elbowF = 0.05f; b.smear = true; b.smA0 = 2.2f; b.smA1 = 0.05f; f.push_back(b);
      BPose c = b; c.smear = false; c.lean = 0.12f; c.armF = 1.2f; c.elbowF = 0.4f; f.push_back(c);
      add("punch", 10, false, f); }
    { std::vector<BPose> f;
      BPose a; a.bob = -4; a.sqx = 1.1f; a.sqy = 0.9f; a.armF = 2.4f; a.armB = -2.4f; a.elbowF = a.elbowB = 0.3f; f.push_back(a);
      BPose b; b.bob = 10; b.armF = 2.9f; b.armB = -2.9f; b.legF = 0.6f; b.legB = -0.6f; f.push_back(b);
      BPose c; c.bob = -6; c.sqx = 1.18f; c.sqy = 0.82f; c.armF = 0.9f; c.elbowF = 1.4f; c.armB = -0.9f; c.elbowB = -1.4f; c.smear = true; c.smA0 = 3.0f; c.smA1 = -0.2f; f.push_back(c);
      add("slam", 8, false, f); }
    { BPose p; p.hurt = true; p.lean = -0.3f; add("hurt", 8, false, { p }); }
    { std::vector<BPose> f; for (int i = 0; i < 3; ++i) { BPose p; p.dead = i > 0; p.rot = i * 0.7f; p.bob = -i * 10.f; p.lean = -0.2f; f.push_back(p); } add("death", 6, false, f); }
    int maxF = 0; for (auto& r : rows) maxF = std::max(maxF, (int)r.size());
    Canvas cv(CW * maxF, CH * (int)rows.size());
    for (size_t r = 0; r < rows.size(); ++r) for (size_t i = 0; i < rows[r].size(); ++i) { const BPose& ps = rows[r][i];
        draw_cell(cv, (int)i * CW, (int)r * CH, CW, CH, FX, FY, [&](Painter& pt) { draw_brute(pt, ps); }); }
    write_png(dir + "/brute.png", cv);
    write_sheet_json(dir + "/brute.json", CW, CH, FX, FY, anims);
    printf("brute: %zu animations\n", anims.size());
}

// ================================================================== CULTIST (frog-masked)
struct KPose { float bob = 0, lean = 0, hem = 0, armF = 0.3f, elbowF = 0.4f, armB = -0.2f, legF = 0, legB = 0, bladeA = -0.6f, rot = 0;
               bool smear = false; float smA0 = 0, smA1 = 0; bool hurt = false, dead = false; };
static void draw_cultist(Painter& pt, const KPose& k) {
    C3 robe{ 110,40,52 }, robeSh{ 74,26,36 }, robeHi{ 150,62,70 }, trimC{ 190,150,80 }, mask{ 96,128,70 }, maskSh{ 64,92,50 };
    const C3 eyeC{ 236,214,90 }, pupil{ 16,14,12 }, steel{ 196,200,206 }, steelSh{ 120,126,138 }, grip{ 70,46,34 }, skin{ 196,150,120 };
    if (k.hurt) { robe = { 240,232,232 }; robeSh = { 210,200,200 }; robeHi = { 255,250,250 }; mask = { 240,250,236 }; }
    A2 base = A2::T(0, k.bob) * A2::T(0, 22) * A2::R(k.rot) * A2::T(0, -22);
    A2 body = base * A2::T(0, 20) * A2::R(-k.lean) * A2::T(0, -20);
    if (k.smear) pt.poly(body, smear_arc({ 6, 34 }, k.smA0, k.smA1, 40, 10), { 255,214,200 }, 0.85f);
    auto foot = [&](float x, float th) { A2 F = base * A2::T(x, 12) * A2::R(th); pt.poly(F, P_rect(-2, -12, 2.2f, 0), { 40,30,32 }); pt.poly(F, P_rect(-2.2f, -12.5f, 4.4f, -10.5f), { 30,22,24 }); };
    foot(-2, k.legB); foot(2.5f, k.legF);
    A2 armB = body * A2::T(-4, 36) * A2::R(k.armB);
    pt.poly(armB, P({ -3,0, 3,0, 4,-11, -4,-11 }), robeSh);
    pt.poly(armB, P_ell(0, -12.5f, 2.2f, 2.2f, 8), skin);
    float hw = k.hem;                                                                   // robe: A-line with swaying hem
    pt.poly(body, P({ -6,38, 6,38, 9,24, 11 + hw,4, 8 + hw * 0.5f,2, -8 + hw * 0.5f,2, -11 + hw,4, -9,24 }), robe);
    pt.poly(body, P({ 1.5f,38, 6,38, 9,24, 11 + hw,4, 8 + hw * 0.5f,2, 1.5f,2 }), robeSh, 1, true);
    pt.poly(body, P({ -6,38, -4,38, -6.5f,24, -9 + hw,4, -11 + hw,4, -9,24 }), robeHi, 1, true);
    pt.poly(body, P_rect(-8.6f, 20, 8.6f, 22.6f), trimC);
    pt.poly(body, P({ -1,20, 1,20, 2,8, -2,8 }), trimC, 1, true);
    // hood + frog mask
    A2 head = body * A2::T(0.5f, 44);
    pt.poly(head, P({ -8,-6, 8,-6, 9,3, 4,9, -4,9, -9,3 }), robeSh);
    pt.poly(head, P_ell(1.5f, 0, 6.6f, 5.8f, 16), mask);
    pt.poly(head, P_ell(2, -2.4f, 5.6f, 3, 14), maskSh, 1, true);
    for (float ex : { -1.6f, 4.6f }) {
        pt.poly(head, P_ell(ex, 3.2f, 2.6f, 2.6f, 10), eyeC, 1, true);
        if (!k.dead) pt.poly(head, P_rect(ex - 0.4f, 2, ex + 0.8f, 4.4f), pupil, 1, true);
    }
    pt.poly(head, P({ -3,-2, 7,-1.6f, 7,-0.8f, -3,-1.2f }), { 140,30,30 }, 1, true);
    // front arm + curved blade
    A2 armF = body * A2::T(4, 36) * A2::R(k.armF);
    pt.poly(armF, P({ -3,0, 3,0, 3.5f,-7, -3.5f,-7 }), robe);
    A2 E = armF * A2::T(0, -7) * A2::R(k.elbowF);
    pt.poly(E, P({ -3,0, 3,0, 3,-6, -3,-6 }), robe);
    pt.poly(E, P_ell(0, -7.5f, 2.3f, 2.3f, 8), skin);
    A2 Bl = E * A2::T(0, -7.5f) * A2::R(k.bladeA);
    pt.poly(Bl, P_rect(-1.2f, -1, 1.2f, 5), grip);
    pt.poly(Bl, P({ -1.4f,-1, 1.4f,-1, 2.6f,-10, 1.2f,-19, -2.8f,-23, -0.6f,-14, -1.6f,-6 }), steel);
    pt.poly(Bl, P({ 1.4f,-1, 2.6f,-10, 1.2f,-19, 0.2f,-11 }), steelSh, 1, true);
}
static void build_cultist(const std::string& dir) {
    const int CW = 112, CH = 88, FX = 56, FY = 82;
    std::vector<AnimInfo> anims; std::vector<std::vector<KPose>> rows;
    auto add = [&](const char* nm, float fps, bool loop, std::vector<KPose> fr) { anims.push_back({ nm, (int)fr.size(), fps, loop }); rows.push_back(fr); };
    { std::vector<KPose> f; for (int i = 0; i < 2; ++i) { KPose p; p.hem = i ? 0.8f : -0.4f; p.bob = i * 0.5f; f.push_back(p); } add("idle", 3, true, f); }
    { std::vector<KPose> f; for (int i = 0; i < 4; ++i) { KPose p; float s = sinf(i * PI_F / 2); p.legF = s * 0.5f; p.legB = -s * 0.5f; p.hem = -1.5f; p.lean = 0.1f;
        p.armF = 0.2f - s * 0.2f; p.armB = -0.2f + s * 0.3f; p.bob = fabsf(cosf(i * PI_F / 2)) - 0.5f; f.push_back(p); } add("walk", 7, true, f); }
    { std::vector<KPose> f;
      KPose a; a.lean = -0.18f; a.armF = 2.6f; a.elbowF = 0.4f; a.bladeA = 0.6f; a.hem = 1; f.push_back(a);
      KPose b = a; b.lean = 0.22f; b.armF = 1.0f; b.elbowF = 0.2f; b.bladeA = -1.2f; b.smear = true; b.smA0 = 2.3f; b.smA1 = 0.0f; b.hem = -2; f.push_back(b);
      KPose c = b; c.smear = false; c.armF = 0.4f; c.bladeA = -1.6f; c.lean = 0.12f; f.push_back(c);
      add("attack", 9, false, f); }
    { KPose p; p.hurt = true; p.lean = -0.3f; add("hurt", 8, false, { p }); }
    { std::vector<KPose> f; for (int i = 0; i < 3; ++i) { KPose p; p.dead = i > 0; p.rot = i * 0.75f; p.bob = -i * 9.f; p.lean = -0.2f; f.push_back(p); } add("death", 6, false, f); }
    int maxF = 0; for (auto& r : rows) maxF = std::max(maxF, (int)r.size());
    Canvas cv(CW * maxF, CH * (int)rows.size());
    for (size_t r = 0; r < rows.size(); ++r) for (size_t i = 0; i < rows[r].size(); ++i) { const KPose& ps = rows[r][i];
        draw_cell(cv, (int)i * CW, (int)r * CH, CW, CH, FX, FY, [&](Painter& pt) { draw_cultist(pt, ps); }); }
    write_png(dir + "/cultist.png", cv);
    write_sheet_json(dir + "/cultist.json", CW, CH, FX, FY, anims);
    printf("cultist: %zu animations\n", anims.size());
}

// ================================================================== PROPS
struct PropInfo { std::string name; int w, h, fx, fy; };
static std::vector<PropInfo> g_props;
static void prop(const std::string& dir, const char* name, int W, int H, int fx, int fy, const std::function<void(Painter&)>& draw) {
    g_props.push_back({ name, W, H, fx, fy });
    Canvas cv(W, H);
    draw_cell(cv, 0, 0, W, H, fx, fy, draw);
    write_png(dir + "/" + name + ".png", cv);
}
static void build_props(const std::string& dir) {
    A2 I;
    prop(dir, "tree", 112, 128, 56, 124, [&](Painter& p) {
        A2 M = A2::S(1.7f, 1.7f);
        p.poly(M, P({ -3.8f,0, 3.8f,0, 2.6f,30, -2.6f,30 }), { 78,58,44 });
        p.poly(M, P({ 0.8f,0, 3.8f,0, 2.6f,30, 0.6f,30 }), { 50,38,32 }, 1, true);
        struct B { float x, y, r; int t; };
        static const B bl[] = { {6,36,14,0},{-10,34,12,0},{12,45,11,0},{0,51,12,0},{-6,40,13,1},{4,42,13,1},{-2,50,10,1},{9,36,10,1},
                                {-8,44,9,2},{-2,46,10,2},{-11,38,7,2},{-10,47,6,3},{-4,50,6,3},{-11,49,2.5f,4},{-5,52,2.5f,4} };
        static const C3 tone[5] = { {34,54,42}, {52,78,52}, {78,104,60}, {110,130,72}, {148,158,92} };
        for (auto& b : bl) p.poly(M, P_ell(b.x, b.y, b.r, b.r * 0.9f, 14), tone[b.t], 1, b.t > 0);
    });
    prop(dir, "willow", 112, 128, 56, 124, [&](Painter& p) {               // swamp willow with hanging fronds
        A2 M = A2::S(1.7f, 1.7f);
        p.poly(M, P({ -4,0, 4,0, 2.4f,26, 6,34, 3,35, 0,29, -4,35, -6,33, -2.4f,26 }), { 70,56,46 });
        p.poly(M, P_ell(0, 44, 22, 12, 18), { 46,70,52 });
        p.poly(M, P_ell(-4, 47, 15, 8, 16), { 70,96,62 }, 1, true);
        for (int i = 0; i < 9; ++i) { float x = -20 + i * 5.f, len = 14 + h01(i + 40) * 12;
            p.poly(M, P({ x - 1.6f,40, x + 1.6f,40, x + 0.6f,40 - len, x - 0.8f,40 - len }), i % 2 ? C3{ 56,84,58 } : C3{ 76,104,66 }); }
    });
    prop(dir, "pine", 96, 128, 48, 124, [&](Painter& p) {
        A2 M = A2::S(1.6f, 1.6f);
        p.poly(M, P_rect(-2.4f, 0, 2.4f, 10), { 60,44,36 });
        for (int k = 0; k < 4; ++k) {
            float by = 8 + k * 11.f, w = 18 - k * 4.f, h = 20 - k * 2.f;
            p.poly(M, P({ -w,by, -w * 0.55f,by + h * 0.3f, -w * 0.75f,by + h * 0.3f, -w * 0.3f,by + h * 0.62f, -w * 0.45f,by + h * 0.62f, 0,by + h,
                          w * 0.45f,by + h * 0.62f, w * 0.3f,by + h * 0.62f, w * 0.75f,by + h * 0.3f, w * 0.55f,by + h * 0.3f, w,by }), { 34,58,54 });
            p.poly(M, P({ 0,by, w,by, w * 0.55f,by + h * 0.3f, w * 0.75f,by + h * 0.3f, w * 0.3f,by + h * 0.62f, w * 0.45f,by + h * 0.62f, 0,by + h }), { 24,42,42 }, 1, true);
            p.poly(M, P({ -w * 0.6f,by + 1.5f, -2,by + 1.5f, -1.5f,by + h * 0.75f }), { 64,94,74 }, 1, true);
        }
    });
    prop(dir, "reeds", 48, 72, 24, 70, [&](Painter& p) {
        A2 M = A2::S(1.6f, 1.6f);
        for (int i = 0; i < 4; ++i) { float bx = -6 + i * 4.f, hh = 26 + h01(i + 60) * 14;
            p.poly(M, P_rect(bx - 0.6f, 0, bx + 0.6f, hh), { 76,98,56 });
            p.poly(M, P_ell(bx, hh - 3, 1.5f, 3.8f, 8), { 92,62,40 });
            p.poly(M, P({ bx,4, bx + 6,14, bx + 1,6 }), { 66,92,52 }); }
    });
    prop(dir, "bush", 64, 40, 32, 38, [&](Painter& p) {
        A2 M = A2::S(1.6f, 1.6f);
        p.poly(M, P_ell(-7, 7, 10, 8, 12), { 34,54,40 }); p.poly(M, P_ell(7, 7, 10, 8, 12), { 30,48,38 });
        p.poly(M, P_ell(0, 11, 11, 9, 14), { 54,80,52 }); p.poly(M, P_ell(-4, 14, 6, 4, 10), { 84,108,62 }, 1, true);
    });
    prop(dir, "rock", 56, 36, 28, 34, [&](Painter& p) {
        A2 M = A2::S(1.6f, 1.6f);
        p.poly(M, P({ -11,0, 11,0, 9,8, 3,13, -6,11, -10,5 }), { 96,94,98 });
        p.poly(M, P({ 3,13, 9,8, 11,0, 2,0 }), { 68,66,74 }, 1, true);
        p.poly(M, P({ -6,11, 3,13, -1,7, -8,5 }), { 136,132,128 }, 1, true);
        p.poly(M, P({ -6,11, 3,13, 1,11.5f, -4,10 }), { 76,98,56 }, 1, true);
    });
    prop(dir, "mushroom", 32, 32, 16, 30, [&](Painter& p) {
        A2 M = A2::S(1.4f, 1.4f);
        p.poly(M, P_rect(-2.2f, 0, 2.2f, 7), { 196,188,170 });
        p.poly(M, P({ -8,6, 8,6, 6,10, 0,13, -6,10 }), { 96,206,220 });
        p.poly(M, P_ell(-3, 9.5f, 1.4f, 1.f, 6), { 210,252,252 }, 1, true);
    });
    prop(dir, "lantern", 32, 80, 16, 78, [&](Painter& p) {
        const C3 iron{ 36,34,40 }, ironHi{ 70,66,72 }; A2 M = A2::S(1.6f, 1.6f);
        p.poly(M, P_rect(-2.8f, 0, 2.8f, 3), iron); p.poly(M, P_rect(-1.1f, 3, 1.1f, 34), iron);
        p.poly(M, P_rect(-1.1f, 3, -0.4f, 34), ironHi, 1, true);
        p.poly(M, P_rect(-3.6f, 33, 3.6f, 34.8f), iron); p.poly(M, P_rect(-3.f, 34.8f, 3.f, 42.f), iron);
        p.poly(M, P_rect(-2.1f, 35.6f, 2.1f, 41.2f), { 255,218,150 }, 1, true);
        p.poly(M, P({ -4.f,42.f, 4.f,42.f, 0,46.f }), iron);
    });
    prop(dir, "ruin", 56, 72, 28, 70, [&](Painter& p) {
        A2 M = A2::S(1.6f, 1.6f);
        p.poly(M, P_rect(-8, 0, 8, 3), { 88,84,82 });
        p.poly(M, P({ -6,3, 6,3, 5.5f,28, 3,31, 1,27, -2,30, -5.5f,26 }), { 128,122,114 });
        p.poly(M, P({ 1.5f,3, 6,3, 5.5f,28, 3,31, 1.5f,28 }), { 92,88,86 }, 1, true);
        p.poly(M, P_rect(-6, 11, 6, 12), { 80,76,74 }, 1, true); p.poly(M, P_rect(-6, 19, 6, 20), { 80,76,74 }, 1, true);
        p.poly(M, P({ -6,3, -1,3, -2,8, -6,10 }), { 70,94,52 }, 1, true);
    });
    // frog-idol shrine (checkpoint): unlit and lit variants
    for (int lit = 0; lit < 2; ++lit)
        prop(dir, lit ? "shrine_lit" : "shrine", 64, 88, 32, 86, [&](Painter& p) {
            A2 M = A2::S(1.6f, 1.6f);
            const C3 stone{ 118,112,104 }, stoneSh{ 84,80,76 }, moss{ 72,96,54 };
            p.poly(M, P_rect(-12, 0, 12, 4), stoneSh);
            p.poly(M, P_rect(-8, 4, 8, 22), stone); p.poly(M, P_rect(2, 4, 8, 22), stoneSh, 1, true);
            p.poly(M, P({ -14,22, 14,22, 10,27, -10,27 }), stone);                       // roof
            p.poly(M, P_ell(0, 33, 7, 6, 14), stone);                                     // frog idol
            for (float ex : { -3.5f, 3.5f }) p.poly(M, P_ell(ex, 38, 2.4f, 2.4f, 10), lit ? C3{ 255,236,150 } : C3{ 70,66,62 });
            p.poly(M, P_rect(-4, 9, 4, 17), lit ? C3{ 255,196,110 } : C3{ 36,32,34 }, 1, true);   // niche flame
            p.poly(M, P({ -8,4, -3,4, -4,9, -8,11 }), moss, 1, true);
        });
    prop(dir, "gate", 64, 104, 32, 102, [&](Painter& p) {                        // locked wooden gate
        A2 M = A2::S(1.6f, 1.6f);
        const C3 wood{ 96,70,48 }, woodSh{ 66,48,34 }, iron{ 52,50,56 };
        for (int i = 0; i < 4; ++i) { float x = -12 + i * 6.f; p.poly(M, P_rect(x, 0, x + 5.4f, 58), i % 2 ? woodSh : wood); }
        p.poly(M, P_rect(-13, 12, 13, 15), iron); p.poly(M, P_rect(-13, 42, 13, 45), iron);
        p.poly(M, P_ell(0, 30, 3.4f, 3.4f, 10), { 176,150,70 }, 1, true);
        p.poly(M, P_rect(-0.8f, 25.5f, 0.8f, 29), { 30,26,24 }, 1, true);
    });
    prop(dir, "key", 24, 24, 12, 22, [&](Painter& p) {
        A2 M = A2::S(1.2f, 1.2f); const C3 gold{ 236,196,90 };
        p.poly(M, P_ell(0, 12, 4.4f, 4.4f, 12), gold); p.poly(M, P_ell(0, 12, 2, 2, 8), { 60,40,20 }, 1, true);
        p.poly(M, P_rect(-0.9f, 0, 0.9f, 8), gold); p.poly(M, P_rect(0.9f, 1, 3.6f, 2.6f), gold); p.poly(M, P_rect(0.9f, 4, 2.8f, 5.4f), gold);
    });
    prop(dir, "orb", 16, 16, 8, 15, [&](Painter& p) {                            // spirit orb (score)
        p.poly(I, P_ell(0, 7, 5.5f, 5.5f, 12), { 140,226,214 });
        p.poly(I, P_ell(-1.4f, 8.6f, 2.2f, 2.2f, 8), { 236,255,250 }, 1, true);
    });
    prop(dir, "eye", 28, 28, 14, 26, [&](Painter& p) {                           // frog eye = a memory fragment
        A2 M = A2::S(1.3f, 1.3f);
        p.poly(M, P_ell(0, 10, 8, 8, 16), { 230,206,96 });
        p.poly(M, P_ell(0, 10, 7.6f, 2.4f, 12), { 28,18,14 }, 1, true);
        p.poly(M, P_ell(-2.6f, 13, 1.8f, 1.6f, 8), { 255,250,220 }, 1, true);
    });
    prop(dir, "peach", 24, 24, 12, 22, [&](Painter& p) {                         // heals one HP
        A2 M = A2::S(1.2f, 1.2f);
        p.poly(M, P_ell(0, 7, 6.4f, 6.6f, 14), { 240,150,120 });
        p.poly(M, P_ell(-2, 8.4f, 3.2f, 3.6f, 10), { 255,196,170 }, 1, true);
        p.poly(M, P({ 0,13, 5,16, 7,14, 2,12.5f }), { 90,140,70 });
    });
    prop(dir, "sign", 40, 48, 20, 46, [&](Painter& p) {
        A2 M = A2::S(1.5f, 1.5f);
        p.poly(M, P_rect(-1.2f, 0, 1.2f, 18), { 80,58,40 });
        p.poly(M, P({ -11,14, 11,14, 12,24, -11,24 }), { 132,98,64 });
        p.poly(M, P_rect(-8, 17, 8, 18), { 70,50,36 }, 1, true); p.poly(M, P_rect(-8, 20, 5, 21), { 70,50,36 }, 1, true);
    });
    // the old hermit who knows who you were (NPC)
    prop(dir, "hermit", 64, 80, 32, 78, [&](Painter& p) {
        A2 M = A2::S(1.0f, 1.0f);
        const C3 robe{ 150,138,112 }, robeSh{ 112,102,82 }, skin{ 214,170,138 }, beard{ 236,232,222 }, hood{ 96,110,84 };
        p.poly(M, P_rect(-1, 0, 1, 50), { 96,70,46 });                                  // walking stick
        p.poly(M, P({ -9,0, 9,0, 7,30, 4,40, -4,40, -7,30 }), robe);
        p.poly(M, P({ 2,0, 9,0, 7,30, 4,40, 2,40 }), robeSh, 1, true);
        p.poly(M, P_ell(1, 45, 6, 6.4f, 14), skin);
        p.poly(M, P({ -3,44, 6,44, 4,32, 1,30, -1,34 }), beard);
        p.poly(M, P({ -8,42, 8,44, 7,52, 1,56, -6,52 }), hood);
        p.poly(M, P_rect(2, 46, 4.2f, 47.2f), { 40,30,30 }, 1, true);
        p.poly(M, P_ell(1, 33, 2, 2, 8), skin);
    });
    prop(dir, "thorns", 48, 28, 24, 26, [&](Painter& p) {                       // hazard: bone-white thorn bramble
        A2 M = A2::S(1.4f, 1.4f);
        p.poly(M, P_rect(-15, 0, 15, 3), { 60,46,40 });
        for (int i = 0; i < 6; ++i) { float x = -13 + i * 5.2f, hh = 9 + h01(i + 70) * 6;
            p.poly(M, P({ x - 2.2f,2, x + 2.2f,2, x + 0.4f,hh }), i % 2 ? C3{ 214,206,186 } : C3{ 178,168,148 }); }
    });
    prop(dir, "grass", 32, 20, 16, 18, [&](Painter& p) {
        A2 M = A2::S(1.3f, 1.3f);
        for (int i = 0; i < 5; ++i) { float bx = -6 + i * 3.f, hh = 6 + h01(i + 40) * 7, lean = (h01(i + 50) - 0.5f) * 5;
            p.poly(M, P({ bx - 1.2f,0, bx + 1.2f,0, bx + lean,hh }), (i & 1) ? C3{ 60,86,46 } : C3{ 92,118,62 }); }
    });
    prop(dir, "flowers", 32, 24, 16, 22, [&](Painter& p) {
        A2 M = A2::S(1.3f, 1.3f);
        static const C3 pc[3] = { {196,84,92}, {226,196,110}, {150,120,186} };
        for (int k = 0; k < 3; ++k) { float x = -6 + k * 6.f, hh = 7 + k % 2 * 3.f;
            p.poly(M, P_rect(x - 0.5f, 0, x + 0.5f, hh), { 54,86,46 });
            for (int i = 0; i < 4; ++i) { float a = i * PI_F / 2 + 0.4f; p.poly(M, P_ell(x + cosf(a) * 1.8f, hh + 1 + sinf(a) * 1.8f, 1.5f, 1.5f, 6), pc[k], 1, true); }
            p.poly(M, P_ell(x, hh + 1, 1.f, 1.f, 6), { 230,200,96 }, 1, true); }
    });
    prop(dir, "exit", 96, 136, 48, 134, [&](Painter& p) {                        // the great frog gate: level exit
        A2 M = A2::S(1.6f, 1.6f);
        const C3 stone{ 112,106,98 }, stoneSh{ 78,74,70 }, glow{ 255,226,150 };
        p.poly(M, P_rect(-26, 0, -18, 64), stone); p.poly(M, P_rect(18, 0, 26, 64), stoneSh);
        p.poly(M, P({ -30,60, 30,60, 26,70, -26,70 }), stone);
        p.poly(M, P_ell(0, 74, 12, 9, 16), stone);
        for (float ex : { -6.f, 6.f }) p.poly(M, P_ell(ex, 80, 4, 4, 12), glow, 1, true);
        p.poly(M, P_rect(-18, 0, 18, 60), { 40,34,46 }, 0.55f);
        p.poly(M, P({ -26,20, -18,24, -18,30, -26,28 }), { 72,96,54 }, 1, true);
    });
    FILE* f = fopen((dir + "/props.json").c_str(), "w");
    fprintf(f, "{\n");
    for (size_t i = 0; i < g_props.size(); ++i)
        fprintf(f, " \"%s\": [%d, %d, %d, %d]%s\n", g_props[i].name.c_str(), g_props[i].w, g_props[i].h, g_props[i].fx, g_props[i].fy, i + 1 < g_props.size() ? "," : "");
    fprintf(f, "}\n");
    fclose(f);
    printf("props: %zu written\n", g_props.size());
}

// ================================================================== TEXTURES (64x64, tileable)
static float tnoise(int x, int y, int seed) {                 // periodic in 64
    float sx = x + seed * 17.f, sy = y + seed * 31.f;
    return clampf(0.5f * pnoise(sx / 16.f, sy / 16.f, 4) + 0.3f * pnoise(sx / 8.f, sy / 8.f, 8) + 0.2f * pnoise(sx / 4.f, sy / 4.f, 16), 0, 1);
}
static void texture(const std::string& dir, const char* name, const std::function<C3(int, int)>& f) {
    Canvas cv(64, 64);
    for (int y = 0; y < 64; ++y) for (int x = 0; x < 64; ++x) cv.set(x, y, f(x, y));
    write_png(dir + "/" + name + ".png", cv);
}
static void build_textures(const std::string& dir) {
    texture(dir, "grass", [](int x, int y) {
        float n = clampf((tnoise(x, y, 1) - 0.5f) * 1.9f + 0.5f, 0, 1), d = h2(x & 63, y & 63);
        C3 c = tone4({ 60,88,50 }, { 118,142,72 }, n, x, y);
        if (d > 0.93f) c = mul(c, 0.8f); else if (d < 0.012f) c = mix(c, { 200,196,120 }, 0.45f);
        return c; });
    texture(dir, "marsh", [](int x, int y) {                     // boggy swamp grass
        float n = clampf((tnoise(x, y, 2) - 0.5f) * 1.9f + 0.5f, 0, 1), d = h2(x + 99, y + 7);
        C3 c = tone4({ 48,70,56 }, { 92,112,74 }, n, x, y);
        if (d > 0.94f) c = mul(c, 0.78f);
        return c; });
    texture(dir, "mud", [](int x, int y) {
        float n = clampf((tnoise(x, y, 3) - 0.5f) * 1.8f + 0.5f, 0, 1), d = h2(x + 5, y + 55);
        C3 c = tone4({ 64,50,40 }, { 112,88,62 }, n, x, y);
        if (d > 0.95f) c = { 150,96,52 }; else if (d < 0.03f) c = mul(c, 0.75f);
        return c; });
    texture(dir, "cliff", [](int x, int y) {                     // layered rock with cracks
        float n = clampf((tnoise(x, y, 4) - 0.5f) * 1.9f + 0.5f, 0, 1), d = h2(x + 3, y + 9);
        C3 c = tone4({ 70,64,62 }, { 120,108,98 }, n, x, y);
        float ledge = fmodf(y + 5.f * pnoise(x / 8.f, 3, 8), 16.f);
        if (ledge < 1.4f) c = mul(c, 0.55f); else if (ledge < 2.8f) c = mul(c, 1.16f);
        if (fabsf(sinf(x * 0.39f + n * 5.f)) < 0.06f) c = mul(c, 0.6f);
        if (d > 0.975f) c = mul(c, 1.2f);
        return c; });
    texture(dir, "planks", [](int x, int y) {                    // boardwalk, planks run along x
        int plank = y / 8; float fr = (y % 8) / 8.f, n = tnoise(x, y, 5);
        C3 c = mix({ 84,60,42 }, { 128,94,62 }, h01(plank * 31 + 7) * 0.6f + n * 0.4f);
        if (fr < 0.13f) c = mul(c, 0.5f);
        if ((x + plank * 23) % 32 == 0) c = mul(c, 0.6f);
        if (((x + plank * 23) % 32 == 3) && (y % 8 == 4)) c = { 150,140,120 };      // nail heads
        return c; });
    texture(dir, "stone", [](int x, int y) {                     // temple bricks
        int row = y / 16, ox = row % 2 ? 16 : 0, bx = (x + ox) / 32;
        float n = tnoise(x, y, 6), e = (float)std::min(std::min((x + ox) % 32, 31 - (x + ox) % 32), std::min(y % 16, 15 - y % 16));
        C3 c = tone4({ 96,92,88 }, { 140,134,124 }, n * 0.8f + h01(bx * 7 + row * 13) * 0.2f, x, y);
        if (e < 1) c = { 52,48,46 };
        else if (e < 2) c = mul(c, 0.82f);
        if (h2(x + 7, y + 3) > 0.96f) c = { 84,108,62 };                            // moss specks
        return c; });
    texture(dir, "cave", [](int x, int y) {
        float n = clampf((tnoise(x, y, 7) - 0.5f) * 1.9f + 0.5f, 0, 1);
        C3 c = tone4({ 30,30,40 }, { 66,62,78 }, n, x, y);
        if (h2(x + 13, y + 1) > 0.985f) c = { 110,200,210 };                        // glowing crystal flecks
        return c; });
    printf("textures: done\n");
}

int main() {
    crc_init();
    mkdir("assets", 0755); mkdir("assets/sprites", 0755); mkdir("assets/sprites/props", 0755); mkdir("assets/textures", 0755);
    build_hunter("assets/sprites");
    build_hopper("assets/sprites");
    build_brute("assets/sprites");
    build_cultist("assets/sprites");
    build_props("assets/sprites/props");
    build_textures("assets/textures");
    return 0;
}
