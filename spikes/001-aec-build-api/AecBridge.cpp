#include "AecBridge.h"

#include <algorithm>
#include <array>
#include <new>

#include <api/scoped_refptr.h>
#include <modules/audio_processing/include/audio_processing.h>

struct JottyAEC {
  rtc::scoped_refptr<webrtc::AudioProcessing> processor;
  webrtc::StreamConfig stream_config;
};

JottyAEC *jotty_aec_create(void) {
  auto processor = webrtc::AudioProcessingBuilder().Create();
  if (!processor) {
    return nullptr;
  }

  webrtc::AudioProcessing::Config config;
  config.echo_canceller.enabled = true;
  config.echo_canceller.mobile_mode = false;
  processor->ApplyConfig(config);

  return new (std::nothrow) JottyAEC{
    std::move(processor),
    webrtc::StreamConfig(JOTTY_AEC_SAMPLE_RATE, 1)
  };
}

void jotty_aec_destroy(JottyAEC *aec) {
  delete aec;
}

int jotty_aec_process_render(
  JottyAEC *aec,
  const int16_t *render,
  size_t sample_count
) {
  if (aec == nullptr || render == nullptr) {
    return JOTTY_AEC_INVALID_ARGUMENT;
  }
  if (sample_count != JOTTY_AEC_FRAME_SAMPLES) {
    return JOTTY_AEC_INVALID_FRAME_SIZE;
  }

  std::array<int16_t, JOTTY_AEC_FRAME_SAMPLES> reverse;
  std::copy_n(render, sample_count, reverse.begin());

  return aec->processor->ProcessReverseStream(
    reverse.data(),
    aec->stream_config,
    aec->stream_config,
    reverse.data()
  );
}

int jotty_aec_process_capture(
  JottyAEC *aec,
  const int16_t *capture,
  size_t sample_count,
  int stream_delay_ms,
  int16_t *output
) {
  if (aec == nullptr || capture == nullptr || output == nullptr || stream_delay_ms < 0) {
    return JOTTY_AEC_INVALID_ARGUMENT;
  }
  if (sample_count != JOTTY_AEC_FRAME_SAMPLES) {
    return JOTTY_AEC_INVALID_FRAME_SIZE;
  }

  int result = aec->processor->set_stream_delay_ms(stream_delay_ms);
  if (result != webrtc::AudioProcessing::kNoError) {
    return result;
  }

  return aec->processor->ProcessStream(
    capture,
    aec->stream_config,
    aec->stream_config,
    output
  );
}
