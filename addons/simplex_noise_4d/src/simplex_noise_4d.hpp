#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cstdint>

namespace godot {

class SimplexNoise4DNative : public RefCounted {
    GDCLASS(SimplexNoise4DNative, RefCounted)

private:
    uint8_t perm[512];
    float _noise_4d(float x, float y, float z, float w) const;
    float _grad4d(int hash, float x, float y, float z, float w) const;
    static int _fastfloor(float x);

public:
    SimplexNoise4DNative();
    void set_seed(int64_t p_seed);
    float get_noise_4d(float x, float y, float z, float w) const;
    float get_noise_4d_fbm(float x, float y, float z, float w,
                            int octaves, float frequency,
                            float persistence, float lacunarity) const;
    float get_noise_4d_ridged_fbm(float x, float y, float z, float w,
                                    int octaves, float frequency,
                                    float persistence, float lacunarity) const;

protected:
    static void _bind_methods();
};

}
