import json

colors = {
    "on-primary-container": "#fefcff",
    "outline": "#727785",
    "on-primary": "#ffffff",
    "on-surface": "#191c1e",
    "error-container": "#ffdad6",
    "inverse-primary": "#adc6ff",
    "on-secondary-fixed-variant": "#38485d",
    "primary-fixed": "#d8e2ff",
    "error": "#ba1a1a",
    "surface-container-highest": "#e0e3e5",
    "on-tertiary-fixed": "#311400",
    "on-background": "#191c1e",
    "tertiary-fixed-dim": "#ffb786",
    "secondary-fixed": "#d3e4fe",
    "surface-variant": "#e0e3e5",
    "primary-container": "#2170e4",
    "background": "#f7f9fb",
    "tertiary-container": "#b75b00",
    "surface-container": "#eceef0",
    "secondary-fixed-dim": "#b7c8e1",
    "inverse-on-surface": "#eff1f3",
    "primary-fixed-dim": "#adc6ff",
    "on-tertiary-fixed-variant": "#723600",
    "tertiary-fixed": "#ffdcc6",
    "surface-tint": "#005ac2",
    "on-secondary": "#ffffff",
    "surface-container-lowest": "#ffffff",
    "on-error": "#ffffff",
    "surface-dim": "#d8dadc",
    "on-tertiary": "#ffffff",
    "primary": "#0058be",
    "outline-variant": "#c2c6d6",
    "on-surface-variant": "#424754",
    "surface-container-low": "#f2f4f6",
    "on-error-container": "#93000a",
    "on-secondary-container": "#54647a",
    "surface-container-high": "#e6e8ea",
    "surface": "#f7f9fb",
    "surface-bright": "#f7f9fb",
    "inverse-surface": "#2d3133",
    "on-primary-fixed": "#001a42",
    "on-secondary-fixed": "#0b1c30",
    "secondary-container": "#d0e1fb",
    "secondary": "#505f76",
    "tertiary": "#924700",
    "on-tertiary-container": "#fffbff",
    "on-primary-fixed-variant": "#004395"
}

with open("website/resources/css/app.css", "a") as f:
    f.write("\n\n@theme {\n")
    for key, val in colors.items():
        f.write(f"    --color-{key}: {val};\n")
    f.write("}\n")
