#include "ReShade.fxh"

// Macros

#define DEF_BLOOM_TEX(NAME, DIV) \
texture2D tSEBloom_##NAME { \
	Width  = BUFFER_WIDTH / DIV; \
	Height = BUFFER_HEIGHT / DIV; \
	Format = RGBA16F; \
}; \
sampler2D s##NAME { \
	Texture = tSEBloom_##NAME; \
	MinFilter = LINEAR; \
	MagFilter = LINEAR; \
}

#define DEF_DOWN_SHADER(SOURCE, DIV) \
float4 PS_DownSample_##SOURCE( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	return float4(downsample(s##SOURCE, uv, DIV), 1.0); \
}

#define DEF_BLUR_SHADER(SAMPLER_A, SAMPLER_B, SPREAD, DIV) \
float4 PS_BlurX_##SAMPLER_A##_1( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(BUFFER_RCP_WIDTH * (1.0) * SPREAD * DIV, 0.0); \
	return float4(blur(s##SAMPLER_A, uv, size), 1.0); \
} \
float4 PS_BlurY_##SAMPLER_B##_1( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(0.0, BUFFER_RCP_HEIGHT * (1.0) * SPREAD * DIV); \
	return float4(blur(s##SAMPLER_B, uv, size), 1.0); \
} \
float4 PS_BlurX_##SAMPLER_A##_2( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(BUFFER_RCP_WIDTH * (1.0 + 1.0) * SPREAD * DIV, 0.0); \
	return float4(blur(s##SAMPLER_A, uv, size), 1.0); \
} \
float4 PS_BlurY_##SAMPLER_B##_2( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(0.0, BUFFER_RCP_HEIGHT * (1.0 + 1.0) * SPREAD * DIV); \
	return float4(blur(s##SAMPLER_B, uv, size), 1.0); \
}

#define DEF_DOWN_PASS(SOURCE, DEST) \
pass DownSample_##SOURCE { \
	VertexShader = PostProcessVS; \
	PixelShader  = PS_DownSample_##SOURCE; \
	RenderTarget = tSEBloom_##DEST; \
}

#define DEF_BLUR_PASS(A, B) \
pass BlurX_##A##_1 { \
	VertexShader = PostProcessVS; \
	PixelShader  = PS_BlurX_##A##_1; \
	RenderTarget = tSEBloom_##B; \
} \
pass BlurY_##B##_1 { \
	VertexShader = PostProcessVS; \
	PixelShader  = PS_BlurY_##B##_1; \
	RenderTarget = tSEBloom_##A; \
} \
pass BlurX_##A##_2 { \
	VertexShader = PostProcessVS; \
	PixelShader  = PS_BlurX_##A##_2; \
	RenderTarget = tSEBloom_##B; \
} \
pass BlurY_##B##_2 { \
	VertexShader = PostProcessVS; \
	PixelShader  = PS_BlurY_##B##_2; \
	RenderTarget = tSEBloom_##A; \
}

#define SCALE(UV, SCALE, CENTER) ((UV - CENTER) * SCALE + CENTER)

#define TEX2D(SP, UV) tex2D(SP, UV)

// Constants

static const int 
	Additive = 0,
	Overlay = 1;

// Uniforms

uniform bool ShowBloom
<
	ui_category = "Debug";
	ui_label = "Show Bloom";
	ui_tooltip =
		"Displays the bloom texture.\n"
		"\nDefault: Off";
> = false;

uniform int uBloomQuality <
	ui_category = "Bloom";
    ui_label = "Bloom Quality";
	ui_tooltip = "Amount of samples used\n"
				"Medium - 7, High - 11, VeryHigh - 13\n"
				"\nDefault: High";
	ui_type = "combo";
	ui_items = "Medium\0High\0VeryHigh\0";

> = 1;

uniform int BlendingType
<
	ui_category = "Bloom";
	ui_label = "Blending Type";
	ui_tooltip =
		"Methods of blending bloom with image.\n"
		"\nDefault: Additive";
	ui_type = "combo";
	ui_items = "Additive\0Overlay\0";
> = Additive;

uniform float uBloomIntensity <
	ui_category = "Bloom";
	ui_label    = "Bloom Intensity";
	ui_tooltip  = "The amount of light that is scattered "
	             "inside the lens uniformly.\n"
				 "Increase this "
				 "value for a more drastic bloom.\n"
				 "\nDefault: 0.05";
	ui_type     = "drag";
	ui_min      = 0.0;
	ui_max      = 2.0;
	ui_step     = 0.001;
> = 0.05;

uniform float uBloomSpread <
	ui_category = "Bloom";
	ui_label    = "Bloom Spread";
	ui_tooltip  = "Size of bloom spreading\n"
				 "\nDefault: 0.75\n"
				 "Neutral: 0.5";
	ui_type     = "drag";
	ui_min      = 0.01;
	ui_max      = 4.0;
	ui_step     = 0.01;
> = 0.75;

// Textures

sampler2D sBackBuffer {
	Texture     = ReShade::BackBufferTex;
};

DEF_BLOOM_TEX(Bloom0A, 2);
DEF_BLOOM_TEX(Bloom0B, 2);
DEF_BLOOM_TEX(Bloom1A, 4);
DEF_BLOOM_TEX(Bloom1B, 4);
DEF_BLOOM_TEX(Bloom2A, 8);
DEF_BLOOM_TEX(Bloom2B, 8);
DEF_BLOOM_TEX(Bloom3A, 16);
DEF_BLOOM_TEX(Bloom3B, 16);
DEF_BLOOM_TEX(Bloom4A, 32);
DEF_BLOOM_TEX(Bloom4B, 32);
DEF_BLOOM_TEX(Bloom5A, 64);
DEF_BLOOM_TEX(Bloom5B, 64);
DEF_BLOOM_TEX(Bloom6A, 128);
DEF_BLOOM_TEX(Bloom6B, 128);

// Functions

float4 tex2D_bilinear(sampler2D sp, float2 uv) {
	float2 res = tex2Dsize(sp, 0);
	float2 ps = 1.0 / res;

	float2 f = frac(uv * res);

	uv += ps * 0.06; // Precision hack

	float4 tl = tex2D(sp, uv);
	float4 tr = tex2D(sp, uv + float2(ps.x, 0.0));
	float4 bl = tex2D(sp, uv + float2(0.0, ps.y));
	float4 br = tex2D(sp, uv + float2(ps.x, ps.y));

	float4 t = lerp(tl, tr, f.x);
	float4 b = lerp(bl, br, f.x);

	return lerp(t, b, f.y);
}

//ORIGINAL CURVE
float3 get_curve_medium(int i) {
    static const float3 curve[7] = {
        (0.0205).xxx,
        (0.0855).xxx,
        (0.232).xxx,
        (0.324).xxx,
        (0.232).xxx,
        (0.0855).xxx,
        (0.0205).xxx
    };
    return curve[i];
}

float3 get_curve_high(int i) {
    static const float3 curve[11] = {
        (0.003).xxx,  
        (0.016).xxx,  
        (0.05).xxx,  
        (0.117).xxx, 
        (0.194).xxx,  
        (0.228).xxx,  
        (0.194).xxx,  
        (0.117).xxx, 
        (0.05).xxx,  
        (0.016).xxx,  
        (0.003).xxx  
    };
    return curve[i];
}

float3 get_curve_veryhigh(int i) {
    static const float3 curve[13] = {
        (0.00135).xxx,
        (0.0087).xxx,
        (0.031).xxx,
        (0.0717).xxx,
        (0.1235).xxx,
        (0.1643).xxx,
        (0.1836).xxx,
        (0.1643).xxx,
        (0.1235).xxx,
        (0.0717).xxx,
        (0.031).xxx,
        (0.0087).xxx,
        (0.00135).xxx
    };
    return curve[i];
}

float3 blur(sampler2D sp, float2 uv, float2 dir) {
	uint SamplesAmount = 0;
	
	if (uBloomQuality == 0)
	{
		SamplesAmount = 7;
	}
	else if (uBloomQuality == 1)
	{
		SamplesAmount = 11;
	}
	else if (uBloomQuality == 2)
	{
		SamplesAmount = 13;
	}

	float2 coord = uv - dir * ((SamplesAmount * 0.5) - 0.5);

	float3 color = 0.0;
	for (int i = 0; i < SamplesAmount; ++i) {
		float3 pixel = TEX2D(sp, coord).rgb;
		if (uBloomQuality == 0)
		{
			color += pixel * get_curve_medium(i);
		}
		else if (uBloomQuality == 1)
		{
			color += pixel * get_curve_high(i);
		}
		else if (uBloomQuality == 2)
		{
			color += pixel * get_curve_veryhigh(i);
		}
		coord += dir;
	}

	return color;
}

float3 downsample(sampler2D sp, float2 uv, float2 scale) {
	const float2 ps = ReShade::PixelSize * scale;

	return max((
		TEX2D(sp, uv + ps).rgb +
		TEX2D(sp, uv + ps * float2(-0.5,-0.5)).rgb +
		TEX2D(sp, uv + ps * float2( 0.5,-0.5)).rgb +
		TEX2D(sp, uv + ps * float2(-0.5, 0.5)).rgb
	) / 4, 0.0);
}

// Shaders

float4 PS_GetHDR(
	float4 position : SV_POSITION,
	float2 uv       : TEXCOORD
) : SV_TARGET {
	float3 color = TEX2D(sBackBuffer, uv).rgb;
	return float4(color, 1.0);
}

DEF_DOWN_SHADER(Bloom0A, 2)
DEF_BLUR_SHADER(Bloom0B, Bloom0A, 1.0 * uBloomSpread, 2)

DEF_DOWN_SHADER(Bloom0B, 4)
DEF_BLUR_SHADER(Bloom1B, Bloom1A, 1.0 * uBloomSpread, 4)

DEF_DOWN_SHADER(Bloom1B, 8)
DEF_BLUR_SHADER(Bloom2B, Bloom2A, 1.0 * uBloomSpread, 8)

DEF_DOWN_SHADER(Bloom2B, 16)
DEF_BLUR_SHADER(Bloom3B, Bloom3A, 1.0 * uBloomSpread, 16)

DEF_DOWN_SHADER(Bloom3B, 32)
DEF_BLUR_SHADER(Bloom4B, Bloom4A, 1.0 * uBloomSpread, 32)

DEF_DOWN_SHADER(Bloom4B, 64)
DEF_BLUR_SHADER(Bloom5B, Bloom5A, 1.0 * uBloomSpread, 64)

DEF_DOWN_SHADER(Bloom5B, 128)
DEF_BLUR_SHADER(Bloom6B, Bloom6A, 1.0 * uBloomSpread, 128)

float4 PS_Blend(
	float4 position : SV_POSITION,
	float2 uv       : TEXCOORD
) : SV_TARGET {
	float3 color = TEX2D(sBackBuffer, uv).rgb;;

	float3 bloom0 = TEX2D(sBloom0B, uv).rgb;
	float3 bloom1 = TEX2D(sBloom1B, uv).rgb;
	float3 bloom2 = TEX2D(sBloom2B, uv).rgb;
	float3 bloom3 = TEX2D(sBloom3B, uv).rgb;
	float3 bloom4 = TEX2D(sBloom4B, uv).rgb;
	float3 bloom5 = TEX2D(sBloom5B, uv).rgb;
	float3 bloom6 = TEX2D(sBloom6B, uv).rgb;

	float3 bloom = bloom0
	             + bloom1
				 + bloom2
				 + bloom3
				 + bloom4
				 + bloom5
				 + bloom6;
	bloom /= 7;
	
	if (BlendingType == Overlay)	
	{
	color.rgb = ShowBloom
		? bloom.rgb
		: lerp(color, bloom, exp(uBloomIntensity) - 1.0);
	}
	
	else if (BlendingType == Additive)	
	{
	color.rgb = ShowBloom
		? bloom.rgb
		: color + (bloom.rgb * uBloomIntensity);
	}
	
	return float4(color, 1.0);
}

// Technique

technique SEBloom {
	pass GetHDR {
		VertexShader = PostProcessVS;
		PixelShader  = PS_GetHDR;
		RenderTarget = tSEBloom_Bloom0A;
	}

	DEF_DOWN_PASS(Bloom0A, Bloom0B)
	DEF_BLUR_PASS(Bloom0B, Bloom0A)
	
	DEF_DOWN_PASS(Bloom0B, Bloom1B)
	DEF_BLUR_PASS(Bloom1B, Bloom1A)
	
	DEF_DOWN_PASS(Bloom1B, Bloom2B)
	DEF_BLUR_PASS(Bloom2B, Bloom2A)

	DEF_DOWN_PASS(Bloom2B, Bloom3B)
	DEF_BLUR_PASS(Bloom3B, Bloom3A)

	DEF_DOWN_PASS(Bloom3B, Bloom4B)
	DEF_BLUR_PASS(Bloom4B, Bloom4A)

	DEF_DOWN_PASS(Bloom4B, Bloom5B)
	DEF_BLUR_PASS(Bloom5B, Bloom5A)
	
	DEF_DOWN_PASS(Bloom5B, Bloom6B)
	DEF_BLUR_PASS(Bloom6B, Bloom6A)

	pass Blend {
		VertexShader    = PostProcessVS;
		PixelShader     = PS_Blend;
	}
}
