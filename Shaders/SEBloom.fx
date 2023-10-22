#include "ReShade.fxh"

// Macros

#ifndef cBlurSize
#define cBlurSize 4
#endif

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
	float2 size = float2(BUFFER_RCP_WIDTH * (cBlurSize * 0.5) * SPREAD * DIV, 0.0); \
	return float4(blur(s##SAMPLER_A, uv, size), 1.0); \
} \
float4 PS_BlurY_##SAMPLER_B##_1( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(0.0, BUFFER_RCP_HEIGHT * (cBlurSize * 0.5) * SPREAD * DIV); \
	return float4(blur(s##SAMPLER_B, uv, size), 1.0); \
} \
float4 PS_BlurX_##SAMPLER_A##_2( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(BUFFER_RCP_WIDTH * (cBlurSize * 0.5 + 1.0) * SPREAD * DIV, 0.0); \
	return float4(blur(s##SAMPLER_A, uv, size), 1.0); \
} \
float4 PS_BlurY_##SAMPLER_B##_2( \
	float4 position : SV_POSITION, \
	float2 uv       : TEXCOORD \
) : SV_TARGET { \
	float2 size = float2(0.0, BUFFER_RCP_HEIGHT * (cBlurSize * 0.5 + 1.0) * SPREAD * DIV); \
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

//static const float cBlurSize = 4.0;

// Uniforms

uniform bool ShowBloom
<
	ui_category = "Debug";
	ui_label = "Show Bloom";
	ui_tooltip =
		"Displays the bloom texture.\n"
		"\nDefault: Off";
> = false;

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
	             "inside the lens uniformly. Increase this "
				 "value for a more drastic bloom.\n"
				 "\nDefault: 0.05";
	ui_type     = "drag";
	ui_min      = 0.0;
	ui_max      = 0.4;
	ui_step     = 0.001;
> = 0.05;

// Textures

sampler2D sBackBuffer {
	Texture     = ReShade::BackBufferTex;
	//SRGBTexture = true;
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

float3 get_curve(int i) {
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

float3 blur(sampler2D sp, float2 uv, float2 dir) {
	float2 coord = uv - dir * 3.0;

	float3 color = 0.0;
	for (int i = 0; i < 7; ++i) {
		float3 pixel = TEX2D(sp, coord).rgb;
		color += pixel * get_curve(i);
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
DEF_BLUR_SHADER(Bloom0B, Bloom0A, 0.5, 2)

DEF_DOWN_SHADER(Bloom0B, 4)
DEF_BLUR_SHADER(Bloom1B, Bloom1A, 1.0, 4)

DEF_DOWN_SHADER(Bloom1B, 8)
DEF_BLUR_SHADER(Bloom2B, Bloom2A, 0.75, 8)

DEF_DOWN_SHADER(Bloom2B, 16)
DEF_BLUR_SHADER(Bloom3B, Bloom3A, 1.0, 16)

DEF_DOWN_SHADER(Bloom3B, 32)
DEF_BLUR_SHADER(Bloom4B, Bloom4A, 1.0, 32)

DEF_DOWN_SHADER(Bloom4B, 64)
DEF_BLUR_SHADER(Bloom5B, Bloom5A, 1.0, 64)

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

	float3 bloom = bloom0 * 0.5
	             + bloom1 * 0.8 * 0.75
				 + bloom2 * 0.6
				 + bloom3 * 0.45
				 + bloom4 * 0.35
				 + bloom5 * 0.23;
	bloom /= 2.2;
	
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
	
	//color = lerp(color, bloom, exp(uBloomIntensity) - 1.0);
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

	pass Blend {
		VertexShader    = PostProcessVS;
		PixelShader     = PS_Blend;
		//SRGBWriteEnable = true;
	}
}
