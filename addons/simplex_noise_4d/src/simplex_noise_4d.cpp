#include "simplex_noise_4d.hpp"
#include <cmath>

namespace godot {

const float F4 = 0.30901699437494745850f;
const float G4 = 0.13819660112578017589f;

static constexpr float S = 1.0f / 1.414213562373095f;

static const float GRAD_X[32] = {
    1.0f*S,  -1.0f*S,  1.0f*S,  -1.0f*S,
    1.0f*S,  -1.0f*S,  1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,  -1.0f*S,  1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,  -1.0f*S,  0.0f,     0.0f,
    0.0f,     0.0f,    1.0f*S,  -1.0f*S,
};

static const float GRAD_Y[32] = {
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,  -1.0f*S,  1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,  -1.0f*S,  1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,   1.0f*S,  0.0f,     0.0f,
    1.0f*S,  -1.0f*S,  0.0f,     0.0f,
};

static const float GRAD_Z[32] = {
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    0.0f,     0.0f,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    0.0f,     0.0f,    1.0f*S,  -1.0f*S,
   -1.0f*S,   1.0f*S,  0.0f,     0.0f,
};

static const float GRAD_W[32] = {
    0.0f,     0.0f,    0.0f,     0.0f,
    0.0f,     0.0f,    0.0f,     0.0f,
    0.0f,     0.0f,    0.0f,     0.0f,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    1.0f*S,   1.0f*S, -1.0f*S,  -1.0f*S,
    0.0f,     0.0f,   -1.0f*S,  -1.0f*S,
    0.0f,     0.0f,   -1.0f*S,   1.0f*S,
};

SimplexNoise4DNative::SimplexNoise4DNative() {
    memset(perm, 0, sizeof(perm));
}

void SimplexNoise4DNative::set_seed(int64_t p_seed) {
    uint8_t p[256];
    for (int i = 0; i < 256; i++) {
        p[i] = (uint8_t)i;
    }
    unsigned int state = (unsigned int)p_seed;
    for (int i = 255; i > 0; i--) {
        state = state * 1664525u + 1013904223u;
        unsigned int range = (unsigned int)(i + 1);
        int j = (int)(state % range);
        uint8_t tmp = p[i];
        p[i] = p[j];
        p[j] = tmp;
    }
    for (int i = 0; i < 256; i++) {
        perm[i] = p[i];
        perm[256 + i] = p[i];
    }
}

int SimplexNoise4DNative::_fastfloor(float x) {
    int i = (int)x;
    return (x < (float)i) ? i - 1 : i;
}

float SimplexNoise4DNative::_grad4d(int hash, float x, float y, float z, float w) const {
    int gi = hash & 31;
    return GRAD_X[gi] * x + GRAD_Y[gi] * y + GRAD_Z[gi] * z + GRAD_W[gi] * w;
}

float SimplexNoise4DNative::get_noise_4d(float x, float y, float z, float w) const {
    float s = (x + y + z + w) * F4;
    int i = _fastfloor(x + s);
    int j = _fastfloor(y + s);
    int k = _fastfloor(z + s);
    int l = _fastfloor(w + s);
    float t = (i + j + k + l) * G4;

    float x0 = x - (i - t);
    float y0 = y - (j - t);
    float z0 = z - (k - t);
    float w0 = w - (l - t);

    int rank_x = 0, rank_y = 0, rank_z = 0, rank_w = 0;
    if (x0 > y0) rank_x++; else rank_y++;
    if (x0 > z0) rank_x++; else rank_z++;
    if (x0 > w0) rank_x++; else rank_w++;
    if (y0 > z0) rank_y++; else rank_z++;
    if (y0 > w0) rank_y++; else rank_w++;
    if (z0 > w0) rank_z++; else rank_w++;

    int i1 = (rank_x >= 3) ? 1 : 0;
    int j1 = (rank_y >= 3) ? 1 : 0;
    int k1 = (rank_z >= 3) ? 1 : 0;
    int l1 = (rank_w >= 3) ? 1 : 0;
    int i2 = (rank_x >= 2) ? 1 : 0;
    int j2 = (rank_y >= 2) ? 1 : 0;
    int k2 = (rank_z >= 2) ? 1 : 0;
    int l2 = (rank_w >= 2) ? 1 : 0;
    int i3 = (rank_x >= 1) ? 1 : 0;
    int j3 = (rank_y >= 1) ? 1 : 0;
    int k3 = (rank_z >= 1) ? 1 : 0;
    int l3 = (rank_w >= 1) ? 1 : 0;

    float x1 = x0 - i1 + G4;
    float y1 = y0 - j1 + G4;
    float z1 = z0 - k1 + G4;
    float w1 = w0 - l1 + G4;
    float x2 = x0 - i2 + 2.0f * G4;
    float y2 = y0 - j2 + 2.0f * G4;
    float z2 = z0 - k2 + 2.0f * G4;
    float w2 = w0 - l2 + 2.0f * G4;
    float x3 = x0 - i3 + 3.0f * G4;
    float y3 = y0 - j3 + 3.0f * G4;
    float z3 = z0 - k3 + 3.0f * G4;
    float w3 = w0 - l3 + 3.0f * G4;
    float x4 = x0 - 1.0f + 4.0f * G4;
    float y4 = y0 - 1.0f + 4.0f * G4;
    float z4 = z0 - 1.0f + 4.0f * G4;
    float w4 = w0 - 1.0f + 4.0f * G4;

    int ii = i & 255;
    int jj = j & 255;
    int kk = k & 255;
    int ll = l & 255;

    float n0 = 0.0f, n1 = 0.0f, n2 = 0.0f, n3 = 0.0f, n4 = 0.0f;

    float t0 = 0.6f - x0*x0 - y0*y0 - z0*z0 - w0*w0;
    if (t0 > 0.0f) { t0 *= t0; n0 = t0 * t0 * _grad4d(perm[ii + perm[jj + perm[kk + perm[ll]]]], x0, y0, z0, w0); }

    float t1 = 0.6f - x1*x1 - y1*y1 - z1*z1 - w1*w1;
    if (t1 > 0.0f) { t1 *= t1; n1 = t1 * t1 * _grad4d(perm[ii+i1 + perm[jj+j1 + perm[kk+k1 + perm[ll+l1]]]], x1, y1, z1, w1); }

    float t2 = 0.6f - x2*x2 - y2*y2 - z2*z2 - w2*w2;
    if (t2 > 0.0f) { t2 *= t2; n2 = t2 * t2 * _grad4d(perm[ii+i2 + perm[jj+j2 + perm[kk+k2 + perm[ll+l2]]]], x2, y2, z2, w2); }

    float t3 = 0.6f - x3*x3 - y3*y3 - z3*z3 - w3*w3;
    if (t3 > 0.0f) { t3 *= t3; n3 = t3 * t3 * _grad4d(perm[ii+i3 + perm[jj+j3 + perm[kk+k3 + perm[ll+l3]]]], x3, y3, z3, w3); }

    float t4 = 0.6f - x4*x4 - y4*y4 - z4*z4 - w4*w4;
    if (t4 > 0.0f) { t4 *= t4; n4 = t4 * t4 * _grad4d(perm[ii+1 + perm[jj+1 + perm[kk+1 + perm[ll+1]]]], x4, y4, z4, w4); }

    return 27.0f * (n0 + n1 + n2 + n3 + n4);
}

float SimplexNoise4DNative::get_noise_4d_fbm(float x, float y, float z, float w,
                                               int octaves, float frequency,
                                               float persistence, float lacunarity) const {
    float output = 0.0f;
    float denom = 0.0f;
    float amp = 1.0f;
    float freq = frequency;

    for (int i = 0; i < octaves; i++) {
        output += amp * get_noise_4d(x * freq, y * freq, z * freq, w * freq);
        denom += amp;
        freq *= lacunarity;
        amp *= persistence;
    }

    return output / denom;
}

void SimplexNoise4DNative::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_seed", "seed"), &SimplexNoise4DNative::set_seed);
    ClassDB::bind_method(D_METHOD("get_noise_4d", "x", "y", "z", "w"), &SimplexNoise4DNative::get_noise_4d);
    ClassDB::bind_method(D_METHOD("get_noise_4d_fbm", "x", "y", "z", "w", "octaves", "frequency", "persistence", "lacunarity"),
                         &SimplexNoise4DNative::get_noise_4d_fbm);
}

}
