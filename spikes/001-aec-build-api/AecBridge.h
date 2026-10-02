#ifndef JOTTY_AEC_BRIDGE_H
#define JOTTY_AEC_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JottyAEC JottyAEC;

enum {
  JOTTY_AEC_SAMPLE_RATE = 16000,
  JOTTY_AEC_FRAME_SAMPLES = 160,
  JOTTY_AEC_INVALID_ARGUMENT = -1000,
  JOTTY_AEC_INVALID_FRAME_SIZE = -1001
};

JottyAEC *jotty_aec_create(void);
void jotty_aec_destroy(JottyAEC *aec);

int jotty_aec_process_render(
  JottyAEC *aec,
  const int16_t *render,
  size_t sample_count
);

int jotty_aec_process_capture(
  JottyAEC *aec,
  const int16_t *capture,
  size_t sample_count,
  int stream_delay_ms,
  int16_t *output
);

#ifdef __cplusplus
}
#endif

#endif
