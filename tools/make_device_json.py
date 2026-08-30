#!/usr/bin/env python3
"""Build Connect IQ device configuration folders without the SDK Manager.

The `monkeyc` compiler resolves `-d <device>` against a folder of per-device
`compiler.json` files, which the graphical SDK Manager normally downloads. That
is awkward in CI or in a headless container, but the SDK jar already ships the
legacy `devices.xml` describing every device, so this script converts the
entries it needs into the JSON layout the compiler expects.

    python3 tools/make_device_json.py --sdk /path/to/connectiq-sdk \\
        --out build/devices venu2 venu2s venu2plus

Then build with:

    monkeyc --override-devices-json build/devices -d venu2 ...
"""
import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

DEVICES_XML = "com/garmin/monkeybrains/devices/devices.xml"


def load_devices_xml(sdk_root):
    jar = os.path.join(sdk_root, "bin", "monkeybrains.jar")
    if not os.path.isfile(jar):
        sys.exit("no monkeybrains.jar under %s/bin" % sdk_root)
    with zipfile.ZipFile(jar) as zf:
        with zf.open(DEVICES_XML) as fh:
            return ET.parse(fh).getroot()


def text_of(node, tag, default=None):
    child = node.find(tag)
    return default if child is None or child.text is None else child.text.strip()


def flag(node, tag):
    return (text_of(node, tag, "FALSE") or "FALSE").upper() == "TRUE"


def part_numbers(device):
    out = []
    for pn in device.iterfind("./part_numbers/part_number"):
        languages = [
            {"code": lang.text.strip(), "fontSet": lang.get("font_set", "ww")}
            for lang in pn.iterfind("./languages/language")
            if lang.text
        ]
        out.append({
            "number": pn.get("number"),
            "firmwareVersion": int(pn.get("firmwareVersion", "0")),
            "connectIQVersion": pn.get("connectIQVersion"),
            "languages": languages,
        })
    return out


# devices.xml names app types in kebab-case; the JSON reader wants camelCase.
APP_TYPE_NAMES = {
    "audio-content-provider-app": "audioContentProvider",
    "watch-app": "watchApp",
    "watchface": "watchFace",
    "datafield": "datafield",
    "background": "background",
    "glance": "glance",
    "widget": "widget",
    "barrel": "barrel",
}


def app_types(device):
    out = []
    for app in device.iterfind("./app_types/app"):
        name = APP_TYPE_NAMES.get(app.get("id"))
        if name is None:
            continue
        out.append({
            "type": name,
            "memoryLimit": int(app.get("memory_limit", "0")),
        })
    return out


def convert(device):
    icon = device.find("launcher_icon")
    res = device.find("resolution")
    formats = [f.get("name") for f in device.iterfind("./imageFormats/format")]

    config = {
        "deviceId": device.get("id"),
        "displayName": device.get("name"),
        "deviceFamily": device.get("family"),
        "worldWidePartNumber": device.get("part_number"),
        "partNumbers": part_numbers(device),
        "appTypes": app_types(device),
        "resolution": {
            "width": int(res.get("width")),
            "height": int(res.get("height")),
        },
        "launcherIcon": {
            "width": int(icon.get("width")),
            "height": int(icon.get("height")),
        },
        "bitsPerPixel": int(text_of(device, "bpp", "16")),
        "orientation": text_of(device, "orientation", "GFX_ORNTN_0"),
        "imageFormats": formats or ["png"],
        "alphaBlendingSupport": flag(device, "alpha_blending_support"),
        "gpuSupport": flag(device, "gpu_support"),
        "antiAliasedFontSupport": flag(device, "anti_aliased_font_support"),
    }

    palette = [c.text.strip() for c in device.iterfind("./palette/color") if c.text]
    if palette:
        config["palette"] = {"colors": palette, "isResourcePalette": True}
    return config


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sdk", required=True, help="unpacked Connect IQ SDK root")
    ap.add_argument("--out", required=True, help="folder to write device configs into")
    ap.add_argument("devices", nargs="+", help="device ids, e.g. venu2 venu2s")
    args = ap.parse_args()

    root = load_devices_xml(args.sdk)
    by_id = {d.get("id"): d for d in root.iter("device")}

    for device_id in args.devices:
        device = by_id.get(device_id)
        if device is None:
            sys.exit("unknown device id: %s" % device_id)
        folder = os.path.join(args.out, device_id)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "compiler.json")
        with open(path, "w") as fh:
            json.dump(convert(device), fh, indent=2)
        print("wrote", path)


if __name__ == "__main__":
    main()
