#pragma once
#include <stdint.h>
typedef struct { float x, y; } REPoint;
typedef struct { REPoint position, velocity; } REVector;
typedef struct {
    int32_t frame; double timestamp;
    int32_t identifier, state, fingerID, handID;
    REVector normalized;
    float size; int32_t reserved;
    float angle, majorAxis, minorAxis;
    REVector absolute;
    int32_t reserved2, reserved3; float density;
} RETouch;
