Shader "RayMarching/MetaBall"
{

	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	CGINCLUDE		
	#include "UnityCG.cginc"
	#include "Assets/CgIncludes/Util.cginc"
	#include "Assets/CgIncludes/Noise.cginc"
	#include "Assets/CgIncludes/Random.cginc"

	#define PI 3.14159265
	#define GAMMA 0.8
	#define AO_SAMPLES 5
	#define RAY_DEPTH 256
	#define MAX_DEPTH 100.0
	#define SHADOW_RAY_DEPTH 32
	#define DISTANCE_MIN 0.001
	#define ANTIALIAS_SAMPLES 4
	#define SPHERE_COUNT 10

	sampler2D _MainTex;
	float4 _MainTex_ST;
	samplerCUBE _Cube;  
	float4 _CameraForward;
	float4 _CameraUp;
	float4 _CameraRight;

	struct Camera{
		float3 pos;
		float3 up;
		float3 dir; //左手系　x*y=z
		float3 side;
		float fov;
	};

	struct f2o{
		float4 color : SV_Target;
		float depth : SV_Depth;
	};

	float3 RotateY(float3 p, float a)
	{
	   float c,s;
	   float3 q=p;
	   c = cos(a);
	   s = sin(a);
	   p.x = c * q.x + s * q.z;
	   p.z = -s * q.x + c * q.z;
	   return p;
	}

	float3 hash3( float n ) {
		return frac(sin(float3(n,n+1.0,n+2.0))*43758.5453123);
	}

	float smoothMin(float d1, float d2, float k){
    	float h = exp(-k * d1) + exp(-k * d2);
   	 	return -log(h) / k;
	}

	float Sphere( float3 p, float r, float3 center = float3(0, 0, 0))
	{
		//バグ　けどおもしろい
 		//return length(p + float3(0, 0, 0))-r + (snoise(p.xyz*_SinTime.x));

		//表面にnoise
		//view-source:http://www.kevs3d.co.uk/dev/shaders/knot2.html ここのを一部参考にした
		//return length(p + float3(0, 0, 0))-(r+snoise(p*10)*0.01);

		//普通の
		return length(p + center)-r;	
	}

	float Plane(float3 p){
		return dot(p, float3(0, 1, 0)) + 1;
	}

	float3 CheckeredPattern(float3 p)
	{
	   if (frac(p.x*.5)>.5){
	      if (frac(p.z*.5)>.5){
	         return float3(1, 1, 1);
	      }
	      else{
	         return float3(0, 0, 0);
	      }
	   }
	   else{
	      if (frac(p.z*.5)>.5){
	         return float3(0, 0, 0);
	      }
	      else{
	         return float3(1, 1, 1);
	      }
	   }
	}

	float DistFunc(float3 pos){
//		pos = RotateY(pos, _Time.x * 10);
		float s[SPHERE_COUNT];

		for(int i=0; i<SPHERE_COUNT; i++){
			s[i] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1 + (i*100)) * 4);
		}

//		s[0] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1) * 4);
//		s[1] = Sphere(pos, 1.5, snoise3D(_Time.xyz * 0.1 + 100) * 4);
//		s[2] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1 + 200) * 4);
//		s[3] = Sphere(pos, 1.5, snoise3D(_Time.xyz * 0.1 + 300) * 4);
//		s[4] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1 + 400) * 4);
//		s[5] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1 + 500) * 4);
//		s[6] = Sphere(pos, 1, snoise3D(_Time.xyz * 0.1 + 600) * 4);

		float value = s[0];
		for(int i=0; i<SPHERE_COUNT-1; i++){
			value = smoothMin(value, s[i+1], 4);
		}
		return value;
	}

	float3 CalcNormal(float3 p){
		float d = 0.001;

		return normalize(float3(
        	DistFunc(p+float3(d,0.0,0.0))-DistFunc(p+float3(-d,0.0,0.0)),
        	DistFunc(p+float3(0.0,d,0.0))-DistFunc(p+float3(0.0,-d,0.0)),
        	DistFunc(p+float3(0.0,0.0,d))-DistFunc(p+float3(0.0,0.0,-d))
   		));
	}

	float SoftShadow(float3 pos, float3 rd, float k)
	{
	   float res = 1.0;
	   float t = 0.1;          // min-t see http://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
	   for (int i=0; i<SHADOW_RAY_DEPTH; i++)
	   {
	      if (t < 20.0)  // max-t
	      {
	         float h = DistFunc(pos + rd * t);
	         res = min(res, k*h/t);
	         t += h;
	      }
	   }
	   return clamp(res, 0.9, 1.0);
	}

	float CalcAO(float3 pos, float3 normal)
	{
	   float r = 0.0;
	   float w = 1.0;
	   for (int i=1; i<=AO_SAMPLES; i++)
	   {
	      float d0 = float(i) * 0.2; // 1.0/5.0
	      r += w * (d0 - DistFunc(pos + normal * d0));
	      w *= 0.5;
	   }
	   return 1.0 - clamp(r,0.0,1.0);
	}	


	float4 March(float3 cpos, float3 ray, out bool hit)
	{
		float3 pos = cpos;
	   	float dist;
		float sumDist = 0;
		float4 col = float4(0, 0, 0, 1);

		for(int i=0; i<RAY_DEPTH; i++){
			dist = DistFunc(pos);
			sumDist += dist;

			pos = cpos + ray * sumDist;

			if(dist < DISTANCE_MIN){
				hit = true;
				return float4(pos, 1);
			}
		}
		hit = false;
		return float4(pos, 1);;
	}


	float4 Shading(float3 pos, float3 rd, float3 normal, Camera cam)
	{
		float3 lightPos = _WorldSpaceLightPos0;
		float3 lightColor = float3(1, 1, 1);

		float3 diffuse = lightColor * max(0.4, dot(normal, lightPos));
		float occlusion = CalcAO(pos, normal);
		float3 checker = CheckeredPattern(pos);

		float3 I = lightPos;
		float3 R = reflect(I, normal);
		float3 V = pos - cam.pos;
		R = normalize(R);
		V = normalize(V);
		I = normalize(I);
		float Shininess = 100;
		float specularScale = pow(saturate(dot(R, V)), Shininess);
		float4 specular = float4(1, 1, 1, 1) * specularScale;


		//cast shadow
		float softshadow = SoftShadow(pos, I, 16.0);

		float4 reflection = texCUBE(_Cube, reflect(V, normal));

		float3 color;

		color = (specular + occlusion) * diffuse * softshadow;
		return float4(color, 1);
	}

	float3 GetRay(float2 pos){
	    
	    float3 dir = normalize(_CameraForward);
	    float3 right = normalize(_CameraRight);
	    float3 up = normalize(_CameraUp);
	   
	    return dir + right*pos.x + up*pos.y;
	}

//	#define NO_REFLECT
	f2o frag (v2f_img i)
	{
		f2o o;

		Camera cam;
		cam.pos = _WorldSpaceCameraPos;
		cam.up = _CameraUp.xyz;
		cam.dir = _CameraForward.xyz;
		cam.side = _CameraRight.xyz;
		cam.fov = 60 * 0.5 * 3.1415 / 180;

		float2 texcoord = i.pos / _ScreenParams.xy;
		float2 screenPos = float2( (i.pos.x * 2 - _ScreenParams.x)/_ScreenParams.y, ((i.pos.y * 2 - _ScreenParams.y)/_ScreenParams.y) );

		float3 ray = GetRay(screenPos.xy);

		bool hit = false;
		float4 color = float4(0.03, 0.03, 0.03, 1);
		float4 pos = float4(cam.pos, 1);

		#ifdef NO_REFLECT
		//反射なしの処理
		pos = March(cam.pos, ray, hit);
		float3 normal = CalcNormal(pos);
		color = Shading(pos, ray, normal, cam);

		#else
		//反射ありの処理
		float alpha = 1;
		for(int i=0; i<2; i++){

			//このray+0.01が大切！ないと、ループの２回めでmarchを叩いた時にすぐに返ってしまう
			pos = March(pos+ray*0.01, ray, hit);
			if(!hit){
				break;
			}
		      
			float3 normal = CalcNormal(pos);
			color += alpha * Shading(pos, ray, normal, cam);

//			床の反射は無視　床のnormalのy成分は1なので。最初のrayにだけ適応
			if(normal.y == 1 && i == 0){
				break;	
			}
			alpha *= 0.05;
			ray = normalize(reflect(ray, normal));
		}
		#endif


		float depth = Map(pos.z, cam.pos.z+0.3, cam.pos.z+100, 0, 1);



		//post effect
		//https://www.shadertoy.com/view/MsSSWV ここを参考
		color.xyz = pow(color.xyz, float3(0.4545, 0.4545, 0.4545) );
		color *= 0.2 + 0.8 * pow(16.0 * texcoord.x * texcoord.y * (1.0 - texcoord.x)* (1.0 - texcoord.y), 0.15);
		color.xyz += (1.0/255.0) * hash3(texcoord.x + 13.0 * texcoord.y);


	    o.color = color;
	    o.depth = depth;
	    return o;
	}
	ENDCG


	SubShader
	{
		Tags { "RenderType"="Opaque" "Queue" = "Geometry"}
		LOD 100

		Pass
		{
			CGPROGRAM
			#pragma vertex vert_img
			#pragma fragment frag
			ENDCG
		}
	}
}