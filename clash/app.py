from flask import Flask, send_file, after_this_request
from ruamel.yaml import YAML
import requests
from urllib.parse import unquote
from pathlib import Path
import json
from datetime import datetime, timedelta
from filelock import FileLock
import logging
import os
import functools

app = Flask(__name__)

# 常量定义
USER_AGENT = 'clash verge'
CACHE_DURATION = 300  # 缓存时间5分钟

# 使用 Path 对象处理路径
BASE_DIR = Path(__file__).parent
OUTPUT_FOLDER = BASE_DIR / 'outputs'
TEMPLATE_PATH = BASE_DIR / 'template' / 'b.yaml'
HEADERS_CACHE_PATH = OUTPUT_FOLDER / 'headers_cache.json'
TEMP_YAML_PATH = OUTPUT_FOLDER / 'temp.yaml'  # 临时YAML文件路径
TEMP_YAML_LOCK = OUTPUT_FOLDER / 'temp.yaml.lock'

INCLUDED_HEADERS = {
    'Subscription-Userinfo'  # 只保留这个header
}

# 确保输出目录存在
OUTPUT_FOLDER.mkdir(exist_ok=True)

# YAML 配置
yaml = YAML()
yaml.preserve_quotes = True
yaml.indent(mapping=2, sequence=4, offset=2)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def save_headers_cache(url, headers):
    """保存请求头缓存，仅保存白名单中的header"""
    try:
        if HEADERS_CACHE_PATH.exists():
            with open(HEADERS_CACHE_PATH, 'r', encoding='utf-8') as f:
                cache = json.load(f)
        else:
            cache = {}
        
        filtered_headers = {k: v for k, v in headers.items() 
                          if k.lower() in {h.lower() for h in INCLUDED_HEADERS}}
        
        cache[url] = {
            'headers': filtered_headers,
            'timestamp': datetime.now().isoformat()
        }
        
        with open(HEADERS_CACHE_PATH, 'w', encoding='utf-8') as f:
            json.dump(cache, f, indent=2, ensure_ascii=False)
    except Exception as e:
        logger.error(f"保存headers缓存失败: {e}")

def get_headers_cache(url):
    """获取指定URL的headers缓存，检查是否过期"""
    try:
        if HEADERS_CACHE_PATH.exists():
            with open(HEADERS_CACHE_PATH, 'r', encoding='utf-8') as f:
                cache = json.load(f)
                if url in cache:
                    cache_time = datetime.fromisoformat(cache[url]['timestamp'])
                    if datetime.now() - cache_time < timedelta(seconds=CACHE_DURATION):
                        return cache[url]['headers']
    except Exception as e:
        logger.error(f"读取headers缓存失败: {e}")
    return None

def fetch_yaml(url):
    """获取 YAML 内容并缓存到本地"""
    temp_path = TEMP_YAML_PATH.with_suffix('.tmp')
    
    with FileLock(TEMP_YAML_LOCK):
        try:
            headers = {'User-Agent': USER_AGENT}
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            save_headers_cache(url, response.headers)
            
            with open(temp_path, 'w', encoding='utf-8') as f:
                f.write(response.text)
            
            if not temp_path.exists() or os.path.getsize(temp_path) == 0:
                raise IOError("临时文件写入失败")
                
            if TEMP_YAML_PATH.exists():
                TEMP_YAML_PATH.unlink()
            temp_path.rename(TEMP_YAML_PATH)
            
            logger.info(f"成功缓存YAML文件: {url}")
            return TEMP_YAML_PATH
            
        except Exception as e:
            logger.error(f"获取YAML失败: {str(e)}")
            if temp_path.exists():
                temp_path.unlink()
            raise

def process_yaml_content(yaml_path):
    """处理本地YAML文件"""
    try:
        with open(yaml_path, 'r', encoding='utf-8') as f:
            input_data = yaml.load(f)
        
        if not isinstance(input_data, dict):
            raise ValueError('YAML内容必须是有效的字典格式')
        
        proxies = input_data.get('proxies', [])
        if not proxies:
            raise ValueError('YAML文件中未找到有效的proxies配置')
        
        for proxy in proxies:
            if isinstance(proxy, dict) and proxy.get('type') == 'hysteria2':
                proxy['up'] = '50'
                proxy['down'] = '300'
        
        with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
            template_data = yaml.load(f)
        
        template_data['proxies'] = proxies
        
        output_path = OUTPUT_FOLDER / 'Mitce.yaml'
        with open(output_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f)
        
        return output_path
    except Exception as e:
        logger.error(f"处理YAML内容失败: {str(e)}")
        raise

def cleanup_files(*paths):
    """清理指定的文件"""
    for path in paths:
        try:
            if isinstance(path, (str, Path)) and Path(path).exists():
                Path(path).unlink()
        except Exception as e:
            logger.error(f"清理文件失败 {path}: {str(e)}")

@app.route('/<path:yaml_url>')
def process_yaml(yaml_url):
    temp_yaml_path = None
    output_path = None
    
    try:
        yaml_url = unquote(yaml_url)
        
        if yaml_url.startswith('/http://'):
            yaml_url = yaml_url[1:]
        elif yaml_url.startswith('/https://'):
            yaml_url = yaml_url[1:]
        elif not yaml_url.startswith(('http://', 'https://')):
            yaml_url = 'https://' + yaml_url
            
        temp_yaml_path = fetch_yaml(yaml_url)
        output_path = process_yaml_content(temp_yaml_path)
        cached_headers = get_headers_cache(yaml_url)
        
        response = send_file(
            output_path,
            mimetype='application/yaml',
            as_attachment=True,
            download_name='Mitce'
        )
        
        response.headers['Content-Type'] = 'application/yaml; charset=utf-8'
        
        if cached_headers:
            for header, value in cached_headers.items():
                if header.lower() in {h.lower() for h in INCLUDED_HEADERS}:
                    response.headers[header] = value
        
        # 注册清理回调
        @after_this_request
        def cleanup(response):
            cleanup_files(temp_yaml_path, output_path, HEADERS_CACHE_PATH)
            return response
        
        return response
        
    except Exception as e:
        if temp_yaml_path or output_path:
            cleanup_files(temp_yaml_path, output_path, HEADERS_CACHE_PATH)
        logger.error(f"处理请求失败: {str(e)}")
        return str(e), 500

if __name__ == '__main__':
    app.run(debug=True, port=5002, host='0.0.0.0')
