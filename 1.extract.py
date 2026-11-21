import os
import json
import re
import sys

# 文件路径
xml_file_path = 'core/META-INF/copilot-core.xml'
json_file_path = 'string.json'

# 正则表达式，用于匹配 <override-text place="MainMenu" text="xxx"/> 的行
pattern = re.compile(r'<override-text place="MainMenu" text="([^"]+)"/>')

# 初始化一个字典，用于存储匹配到的文本
matches = {}

# 检查文件是否存在
if not os.path.exists(xml_file_path):
    sys.exit(f"文件 {xml_file_path} 不存在")

with open(xml_file_path, 'r', encoding='utf-8') as file:
    for line in file:
        match = pattern.search(line)
        if match:
            # 提取匹配文本中的 xxx 部分
            text = match.group(1)
            matches[text] = ""

# 将结果写入 JSON 文件
with open(json_file_path, 'w', encoding='utf-8') as json_file:
    json.dump(matches, json_file, ensure_ascii=False, indent=4)

print(f"提取结果已写入 {json_file_path}")
