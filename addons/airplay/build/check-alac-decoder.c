#include <libavcodec/avcodec.h>
#include <libavutil/samplefmt.h>

#include <stdio.h>

int main(void) {
    const AVCodec *decoder;

    avcodec_register_all();
    decoder = avcodec_find_decoder(AV_CODEC_ID_ALAC);

    if (decoder == NULL) {
        fprintf(stderr, "ALAC decoder not found in linked libavcodec\n");
        return 1;
    }

    printf("alac_decoder=%s\n", decoder->name);
    printf("alac_decoder_long_name=%s\n",
           decoder->long_name != NULL ? decoder->long_name : "(not provided)");

    if (decoder->sample_fmts == NULL) {
        printf("alac_supported_sample_formats=(not advertised by this FFmpeg version)\n");
    } else {
        const enum AVSampleFormat *format;
        printf("alac_supported_sample_formats=");
        for (format = decoder->sample_fmts; *format != AV_SAMPLE_FMT_NONE; ++format) {
            const char *name = av_get_sample_fmt_name(*format);
            printf("%s%s", format == decoder->sample_fmts ? "" : ",",
                   name != NULL ? name : "unknown");
        }
        printf("\n");
    }

    printf("alac_decoder_verification=passed (decoder is registered)\n");
    return 0;
}
