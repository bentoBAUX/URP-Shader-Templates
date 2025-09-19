# URP Shader Templates

Unity doesn’t provide ready-made shader templates for the Universal Render Pipeline (URP), so I created this repository to fill the gap.
It currently includes:

- [**Unlit Shader**](Templates/URP-Unlit.shader) – with built-in fog support

- [**Lit Shader**](Templates/URP-Lit.shader) – implementing Lambertian lighting with fog and shadow support. This works in Forward+ and Forward Rendering.

- [**Multi Light Lit Shader**](Templates/Multi%20Light/MultiLight.shader) - a lit shader that allows switching between Lambertian, Blinn-Phong and PBR.
  
These templates are a starting point for creating custom URP shaders without having to set up all the boilerplate from scratch. I plan to add more templates as I create them, so the collection will grow over time.

Feel free to use or adapt these templates for your own projects.
