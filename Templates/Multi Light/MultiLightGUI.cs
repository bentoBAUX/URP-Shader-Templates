// Assets/Editor/DynamicLitSSS_GUI.cs

using UnityEditor;
using UnityEngine;

namespace bentoBAUX
{
    public class MultiLightGUI : ShaderGUI
    {
        enum LightingModel
        {
            Lambert = 0,
            BlinnPhong = 1,
            PBR = 2
        }

        // Common
        MaterialProperty _BaseMap;
        MaterialProperty _BaseColor;
        MaterialProperty _NormalMap;
        MaterialProperty _NormalStrength;
        MaterialProperty _LightingModel;

        // Blinn-Phong
        MaterialProperty _k;
        MaterialProperty _SpecularExponent;

        // PBR
        MaterialProperty _Roughness;
        MaterialProperty _USE_ROUGHNESS_MAP;
        MaterialProperty _RoughnessMap;

        MaterialProperty _Metallic;
        MaterialProperty _USE_METALLIC_MAP;
        MaterialProperty _MetallicMap;

        MaterialProperty _AOMap;
        MaterialProperty _AOStrength;
        MaterialProperty _USE_TONEMAPPING;


        public override void OnGUI(MaterialEditor me, MaterialProperty[] props)
        {
            // Cache props
            _BaseMap = FindProperty("_BaseMap", props);
            _BaseColor = FindProperty("_BaseColor", props);
            _NormalMap = FindProperty("_NormalMap", props);
            _NormalStrength = FindProperty("_NormalStrength", props);
            _LightingModel = FindProperty("_LightingModel", props);

            // Blinn Phong
            _k = FindProperty("_k", props);
            _SpecularExponent = FindProperty("_SpecularExponent", props);

            // PBR
            _Roughness = FindProperty("_Roughness", props);
            _USE_ROUGHNESS_MAP = FindProperty("_UseRoughnessMap", props);
            _RoughnessMap = FindProperty("_RoughnessMap", props);
            _Metallic = FindProperty("_Metallic", props);
            _MetallicMap = FindProperty("_MetallicMap", props);
            _AOMap = FindProperty("_AOMap", props);
            _AOStrength = FindProperty("_AOStrength", props);
            _USE_METALLIC_MAP = FindProperty("_UseMetallicMap", props);
            _USE_TONEMAPPING = FindProperty("_UseToneMapping", props);

            // --- General ---
            EditorGUILayout.LabelField("General Settings", EditorStyles.boldLabel);
            me.TexturePropertySingleLine(new GUIContent("Base Map"), _BaseMap, _BaseColor);
            me.TexturePropertySingleLine(new GUIContent("Normal Map"), _NormalMap, _NormalStrength);
            EditorGUILayout.Space();

            // --- Lighting model dropdown + per-model controls ---
            EditorGUILayout.LabelField("Lighting Models", EditorStyles.boldLabel);

            EditorGUI.BeginChangeCheck();
            var selected = (LightingModel)(int)_LightingModel.floatValue;
            selected = (LightingModel)EditorGUILayout.EnumPopup("Model", selected);
            if (EditorGUI.EndChangeCheck())
            {
                _LightingModel.floatValue = (float)selected;
                foreach (var t in _LightingModel.targets)
                {
                    var mat = (Material)t;
                    ApplyKeywords(mat, selected);
                }
            }

            switch (selected)
            {
                case LightingModel.Lambert:
                    EditorGUILayout.HelpBox("Lambert: diffuse only.", MessageType.None);
                    break;

                case LightingModel.BlinnPhong:
                    if (_k != null)
                    {
                        Vector4 k4 = _k.vectorValue;
                        Vector3 k3 = new Vector3(k4.x, k4.y, k4.z);
                        EditorGUI.BeginChangeCheck();
                        k3 = EditorGUILayout.Vector3Field("K Factors (ambient, diffuse, spec)", k3);
                        if (EditorGUI.EndChangeCheck())
                        {
                            _k.vectorValue = new Vector4(k3.x, k3.y, k3.z, 0); // clamp to 3D
                        }
                    }

                    if (_SpecularExponent != null)
                        me.ShaderProperty(_SpecularExponent, _SpecularExponent.displayName);
                    break;

                case LightingModel.PBR:
                    // --- Roughness ---
                    if (_RoughnessMap != null)
                    {
                        EditorGUI.BeginChangeCheck();
                        if (_RoughnessMap.textureValue != null)
                            me.TexturePropertySingleLine(new GUIContent("Roughness Map (R)"), _RoughnessMap);
                        else
                            me.TexturePropertySingleLine(new GUIContent("Roughness Map (R)"), _RoughnessMap, _Roughness);
                        if (EditorGUI.EndChangeCheck())
                        {
                            foreach (var t in _RoughnessMap.targets)
                            {
                                var m = (Material)t;
                                var modelNow = (LightingModel)Mathf.RoundToInt(m.GetFloat("_LightingModel"));
                                ApplyKeywords(m, modelNow); // updates _USE_ROUGHNESS_MAP based on presence
                            }
                        }
                    }

                    // --- Metallic ---
                    if (_MetallicMap != null)
                    {
                        EditorGUI.BeginChangeCheck();
                        if (_MetallicMap.textureValue != null)
                            me.TexturePropertySingleLine(new GUIContent("Metallic Map (R)"), _MetallicMap);
                        else
                            me.TexturePropertySingleLine(new GUIContent("Metallic Map (R)"), _MetallicMap, _Metallic);
                        if (EditorGUI.EndChangeCheck())
                        {
                            foreach (var t in _MetallicMap.targets)
                            {
                                var m = (Material)t;
                                var modelNow = (LightingModel)Mathf.RoundToInt(m.GetFloat("_LightingModel"));
                                ApplyKeywords(m, modelNow);
                            }
                        }
                    }

                    if(_AOMap != null)
                        me.TexturePropertySingleLine(new GUIContent("AO Map (R)"), _AOMap, _AOStrength);

                    break;
            }

            bool toneOn = _USE_TONEMAPPING.floatValue > 0.5f;
            EditorGUI.BeginChangeCheck();
            toneOn = EditorGUILayout.Toggle("Tone Map (Gamma Correction)", toneOn);
            if (EditorGUI.EndChangeCheck())
            {
                _USE_TONEMAPPING.floatValue = toneOn ? 1f : 0f;

                // Update keywords for all selected materials
                foreach (var t in _USE_TONEMAPPING.targets)
                {
                    var m = (Material)t;
                    var modelNow = (LightingModel)Mathf.RoundToInt(m.GetFloat("_LightingModel"));
                    ApplyKeywords(m, modelNow);
                }
            }

            EditorGUILayout.Space();

            EditorGUILayout.LabelField("Texture Scale Offset", EditorStyles.boldLabel);
            me.TextureScaleOffsetProperty(_BaseMap);
        }

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            base.AssignNewShaderToMaterial(material, oldShader, newShader);
            var selected = (LightingModel)Mathf.RoundToInt(material.GetFloat("_LightingModel"));
            ApplyKeywords(material, selected);
        }

        static void ApplyKeywords(Material mat, LightingModel model)
        {
            mat.DisableKeyword("_LM_LAMBERT");
            mat.DisableKeyword("_LM_BLINNPHONG");
            mat.DisableKeyword("_LM_PBR");

            switch (model)
            {
                case LightingModel.Lambert: mat.EnableKeyword("_LM_LAMBERT"); break;
                case LightingModel.BlinnPhong: mat.EnableKeyword("_LM_BLINNPHONG"); break;
                case LightingModel.PBR: mat.EnableKeyword("_LM_PBR"); break;
            }

            // --- Map presence keywords (set these up in your shader if you want stripping)
            bool hasRoughness = mat.GetTexture("_RoughnessMap") != null;
            bool hasMetallic = mat.GetTexture("_MetallicMap") != null;

            if (hasRoughness) mat.EnableKeyword("_USE_ROUGHNESS_MAP");
            else mat.DisableKeyword("_USE_ROUGHNESS_MAP");
            if (hasMetallic) mat.EnableKeyword("_USE_METALLIC_MAP");
            else mat.DisableKeyword("_USE_METALLIC_MAP");

            bool toneOn = mat.GetFloat("_UseToneMapping") > 0.5f;
            if (toneOn) mat.EnableKeyword("_USE_TONEMAPPING"); else mat.DisableKeyword("_USE_TONEMAPPING");

            EditorUtility.SetDirty(mat);
        }
    }
}