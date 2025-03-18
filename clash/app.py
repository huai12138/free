from flask import Flask, send_file, after_this_request
from ruamel.yaml import YAML
import requests
from urllib.parse import unquote
import json
from datetime import datetime, timedelta
from filelock import FileLock
import logging
import os
from pathlib import Path
from dotenv import load_dotenv

# 加载.env文件
load_dotenv()

app = Flask(__name__)

# 基础配置
BASE_DIR = Path(os.getenv('BASE_DIR', '.')).absolute()
OUTPUT_FOLDER = BASE_DIR / os.getenv('OUTPUT_FOLDER', 'outputs')
TEMPLATE_PATH = BASE_DIR / os.getenv('TEMPLATE_PATH', 'template/b.yaml')
HEADERS_CACHE_PATH = OUTPUT_FOLDER / os.getenv('HEADERS_CACHE_PATH', 'headers_cache.json').split('/')[-1]
TEMP_YAML_PATH = OUTPUT_FOLDER / os.getenv('TEMP_YAML_PATH', 'temp.yaml').split('/')[-1]
TEMP_YAML_LOCK = OUTPUT_FOLDER / os.getenv('TEMP_YAML_LOCK', 'temp.yaml.lock').split('/')[-1]

USER_AGENT = os.getenv('USER_AGENT', 'clash verge')
CACHE_DURATION = int(os.getenv('CACHE_DURATION', 300))
HYSTERIA2_UP = os.getenv('HYSTERIA2_UP', '50')
HYSTERIA2_DOWN = os.getenv('HYSTERIA2_DOWN', '300')
INCLUDED_HEADERS = set(os.getenv('INCLUDED_HEADERS', 'Subscription-Userinfo').split(','))

# 确保输出目录存在
OUTPUT_FOLDER.mkdir(exist_ok=True)

# 验证必要文件存在
if not TEMPLATE_PATH.exists():
    raise FileNotFoundError(f"模板文件不存在: {TEMPLATE_PATH}")

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
        # 读取输入的YAML
        with open(yaml_path, 'r', encoding='utf-8') as f:
            input_data = yaml.load(f)
        
        if not isinstance(input_data, dict):
            raise ValueError('YAML内容必须是有效的字典格式')
            
        # 读取标准模板
        with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
            template_data = yaml.load(f)

        # 读取ports配置
        ports_path = BASE_DIR / 'template' / 'ports.yaml'
        with open(ports_path, 'r', encoding='utf-8') as f:
            ports_data = yaml.load(f)
            
        ports_config = {proxy['name']: proxy['ports'] 
                       for proxy in ports_data.get('proxies', [])}
        
        proxies = input_data.get('proxies', [])
        if not proxies:
            raise ValueError('YAML文件中未找到有效的proxies配置')
            
        # 处理代理配置
        for proxy in proxies:
            if isinstance(proxy, dict):
                if proxy.get('type') == 'hysteria2':
                    proxy['up'] = HYSTERIA2_UP
                    proxy['down'] = HYSTERIA2_DOWN
                    proxy['skip-cert-verify'] = False
                    # 检查是否存在匹配的端口配置
                    if proxy.get('name') in ports_config:
                        proxy['ports'] = ports_config[proxy['name']]
                        proxy.pop('port', None)
                elif proxy.get('type') == 'vless':
                    proxy['skip-cert-verify'] = False
        
        # 更新模板中的代理列表
        template_data['proxies'] = proxies
        
        # 配置YAML输出格式
        yaml.indent(mapping=2, sequence=4, offset=2)
        yaml.preserve_quotes = True
        yaml.width = 4096  # 避免自动换行
        
        # 保存处理后的YAML
        output_path = OUTPUT_FOLDER / 'config.yaml'
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

def cleanup_response(response, temp_yaml_path, output_path):
    """处理响应后的清理函数"""
    cleanup_files(temp_yaml_path, output_path, HEADERS_CACHE_PATH)
    return response

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
            download_name='config.yaml'
        )
        
        response.headers['Content-Type'] = 'application/yaml; charset=utf-8'
        
        if cached_headers:
            for header, value in cached_headers.items():
                if header.lower() in {h.lower() for h in INCLUDED_HEADERS}:
                    response.headers[header] = value
        
        # 修复：将清理函数定义在外部，通过闭包捕获必要的变量
        temp_path = temp_yaml_path  # 创建闭包变量
        out_path = output_path      # 创建闭包变量
        
        @after_this_request
        def cleanup(response):
            return cleanup_response(response, temp_path, out_path)
        
        return response
        
    except Exception as e:
        if temp_yaml_path or output_path:
            cleanup_files(temp_yaml_path, output_path, HEADERS_CACHE_PATH)
        logger.error(f"处理请求失败: {str(e)}")
        return str(e), 500

if __name__ == '__main__':
    debug_mode = os.getenv('DEBUG', 'True').lower() in ('true', '1', 'yes')
    port = int(os.getenv('PORT', 5002))
    host = os.getenv('HOST', '0.0.0.0')
    
    app.run(debug=debug_mode, port=port, host=host)


