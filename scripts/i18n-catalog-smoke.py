#!/usr/bin/env python3
"""Validate bundled SwiftUI localization keys without an Xcode project."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
sources = sorted((root / "apps/wsm-native/Sources").glob("*.swift"))
def read_table(language):
    file = root / f"apps/wsm-native/Resources/{language}.lproj/Localizable.strings"
    result = {}
    for line in file.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("/*"):
            continue
        match = re.fullmatch(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");', line)
        assert match, f"Invalid .strings line: {file} {line[:80]}"
        key, value = (json.loads(match.group(i)) for i in (1, 2))
        assert key not in result, f"Duplicate localization key: {key}"
        result[key] = value
    return result

en = read_table("en")
zh = read_table("zh-Hans")
required = set()
for source in sources:
    for match in re.finditer(r'"((?:\\.|[^"\\])*)"', source.read_text(encoding="utf-8")):
        if re.search(r"[\u3400-\u9fff]", match.group(1)):
            required.add(match.group(1))
assert required <= en.keys(), f"Missing English strings: {sorted(required - en.keys())}"
assert required <= zh.keys(), f"Missing Chinese strings: {sorted(required - zh.keys())}"
assert all(en[key] and not re.search(r"[\u3400-\u9fff]", en[key]) for key in required)
assert all(zh[key] == key for key in required)
for label in ("语言", "跟随系统", "简体中文", "基本信息", "连接配置",
              "新建分组", "SSH 认证方式", "快速打开…", "打开主机管理器"):
    assert en.get(label) and zh.get(label)
assert len(required) >= 190
print(f"PASS: English / Simplified Chinese catalogs cover {len(required)} UI strings")
