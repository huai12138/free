from pathlib import Path

# 常量定义
USER_AGENT = 'sing-box'

# 网速配置
UPLOAD_MBPS = 50
DOWNLOAD_MBPS = 300

# 使用 Path 对象处理路径 
BASE_DIR = Path(__file__).parent
OUTPUT_FOLDER = BASE_DIR / 'outputs'

# 添加模板映射
TEMPLATE_MAP = {
    '1': BASE_DIR / 'template' / 'tproxy_1.11.json',  # tproxy模式
    '2': BASE_DIR / 'template' / 'tun_1.11.json'      # tun模式
}

# 默认模板
DEFAULT_TEMPLATE = TEMPLATE_MAP['1']  # 默认使用tproxy模式