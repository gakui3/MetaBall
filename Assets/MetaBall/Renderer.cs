using UnityEngine;
using System.Collections;

namespace RayMarching
{

	public class Renderer : MonoBehaviour
	{
		[SerializeField] RenderTexture m_colorTex;
		[SerializeField] RenderTexture m_depthTex;
		[SerializeField] Shader raymarchingShader;
		[SerializeField] Shader renderShader;

		Material drawMat;
		Material renderMat;
		Camera cam;

		// Use this for initialization
		void Start ()
		{
			cam = Camera.main;
			cam.depthTextureMode = DepthTextureMode.Depth;

			// カラーバッファ用 RenderTexture
			m_colorTex = new RenderTexture (Screen.width, Screen.height, 0, RenderTextureFormat.ARGB32);
			m_colorTex.Create ();

			// デプスバッファ用 RenderTexture
			m_depthTex = new RenderTexture (Screen.width, Screen.height, 24, RenderTextureFormat.Depth);
			m_depthTex.Create ();


			cam.SetTargetBuffers (m_colorTex.colorBuffer, m_depthTex.depthBuffer);
		}


			
		void OnPostRender ()
		{
			if (drawMat == null) {
				drawMat = new Material (raymarchingShader);
			}
			
			drawMat.SetVector ("_CameraForward", cam.transform.forward);
			drawMat.SetVector ("_CameraUp", cam.transform.up);
			drawMat.SetVector ("_CameraRight", cam.transform.right);

			Graphics.Blit (m_colorTex, drawMat);



			if (renderMat == null) {
				renderMat = new Material (renderShader);
			}

			Graphics.SetRenderTarget (null);
			Graphics.Blit (m_colorTex, renderMat);
		}
	}
}