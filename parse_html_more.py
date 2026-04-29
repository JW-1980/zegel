import re

with open("admin_panel.html", "r") as f:
    content = f.read()

# Also get fonts config
fonts = {
    "label-caps": "Inter",
    "body-lg": "Inter",
    "h1": "Inter",
    "display": "Inter",
    "helper": "Inter",
    "h2": "Inter",
    "body-md": "Inter",
    "body-sm": "Inter",
    "h3": "Inter"
}

sizes = {
    "label-caps": "12px",
    "body-lg": "18px",
    "h1": "30px",
    "display": "36px",
    "helper": "12px",
    "h2": "24px",
    "body-md": "16px",
    "body-sm": "14px",
    "h3": "20px"
}

with open("website/resources/css/app.css", "a") as f:
    f.write("\n@theme {\n")
    for key, val in sizes.items():
        f.write(f"    --font-{key}: {val};\n")
    f.write("}\n")
