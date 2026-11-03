#include <libavcodec/avcodec.h>
#include <libavutil/samplefmt.h>

#include <stdio.h>

int main(void) {
    avcodec_register_all();
    const AVCodec *decoder = avcodec_find_decoder(AV_CODEC_ID_AAC);
    const enum AVSampleFormat *format;
    int supports_fltp = 0;

    if (decoder == NULL) {
        fprintf(stderr, "AAC decoder not found in linked libavcodec\\n");
        return 1;
    }

    printf("aac_decoder=%s\\n", decoder->name);
    printf("aac_decoder_long_name=%s\\n",
           decoder->long_name != NULL ? decoder->long_name : "(not provided)");
    printf("aac_supported_sample_formats=");

    if (decoder->sample_fmts == NULL) {
        printf("(not advertised)\\n");
        fprintf(stderr, "AAC decoder does not advertise supported sample formats\\n");
        return 1;
    }

    for (format = decoder->sample_fmts; *format != AV_SAMPLE_FMT_NONE; ++format) {
        const char *name = av_get_sample_fmt_name(*format);
        printf("%s%s", format == decoder->sample_fmts ? "" : ",",
               name != NULL ? name : "unknown");
        if (*format == AV_SAMPLE_FMT_FLTP) {
            supports_fltp = 1;
        }
    }
    printf("\\n");

    printf("aac_supports_fltp=%s\\n", supports_fltp ? "yes" : "no");

    if (!supports_fltp) {
        fprintf(stderr,
                "The linked AAC decoder does not advertise AV_SAMPLE_FMT_FLTP\\n");
        return 1;
    }

    return 0;
}
