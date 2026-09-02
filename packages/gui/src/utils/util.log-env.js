// 必须在加载 core/mitmproxy 日志模块之前 import，确保 DEV_SIDECAR_LOG_DISABLED 尽早生效
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

if (process.env.DEV_SIDECAR_LOG_DISABLED !== 'true') {
  const userBase = path.join(process.env.USERPROFILE || process.env.HOME || '/', '.dev-sidecar')
  const configPath = path.join(userBase, 'config.json')

  try {
    if (fs.existsSync(configPath)) {
      const userConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'))
      if (userConfig && userConfig.app && userConfig.app.logDisabled === true) {
        process.env.DEV_SIDECAR_LOG_DISABLED = 'true'
      }
    }
  } catch {
    // 配置文件不存在或格式异常时，按默认（允许日志）处理
  }
}
