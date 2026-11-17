import os
import re
import json
import sys

# 文件路径
xml_file_path = 'core/META-INF/copilot-core.xml'
json_file_path = 'zh.json'

# 正则表达式，用于匹配 <override-text place="MainMenu" text="xxx"/> 的行
pattern = re.compile(r'<override-text place="MainMenu" text="([^"]+)"/>')

# 检查文件是否存在
if not os.path.exists(xml_file_path):
    sys.exit(f"文件 {xml_file_path} 不存在")

# 读取 JSON 文件
with open(json_file_path, 'r', encoding='utf-8') as json_file:
    values_dict = json.load(json_file)

with open(xml_file_path, 'r', encoding='utf-8') as file:
    lines = file.readlines()

matched = 0
replaced = 0

with open(xml_file_path, 'w', encoding='utf-8') as output_file:
    for line in lines:
        match = pattern.search(line)
        if match:
            matched += 1
            # 提取匹配文本中的 xxx 部分
            text = match.group(1)
            # 查找 JSON 中对应的值
            if text in values_dict:
                new_text = values_dict[text]
                # 替换 xxx 为对应的值
                line = line.replace(f'text="{text}"', f'text="{new_text}"')
                replaced += 1
        # 写入新的 XML 文件
        output_file.write(line)

print(f"已替换 {replaced} 处菜单文本（共匹配 {matched} 处），更新后的文件已覆盖原文件 {xml_file_path}")

if replaced < matched:
    print(f"警告：{matched - replaced} 处菜单在 {json_file_path} 中缺少译文，已保持英文")
