# 上游仓库安全审查笔记

对 `XiaoMi/xiaomi-miloco`(main 分支,审查时点 2026-08)安装链路的安全审查记录。
结论:**官方仓库本体可信,安装路径合法**,但有以下值得注意的点。

## 1. install-guide.md 是"agent 引流"文档

`scripts/install-guide.md` 带 YAML frontmatter,是写给 agent 看的触发式指令
("当用户说【安装 miloco】时激活")。它的动作是:

```bash
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash
```

- **`curl | bash` 模式本身有供应链风险**:脚本内容随 release 更新而变化,
  安装前无法静态审计当次实际执行的代码。
- 它声明只支持 **OpenClaw / Hermes Agent** 两个运行时,其它平台("如需扩展联系用户")——
  这正是本项目(miloco-dsh)存在的理由。

## 2. install.sh / install.py 行为面(已抽样审查)

官方安装器会:
- 安装 `uv` + Python 3.14,写入用户 PATH;
- 安装 miloco 后端服务 + `miloco-cli` + supervisor,并注册开机自启服务;
- 下载 release bundle 与感知模型(数百 MB);
- 生成 webhook bearer、写 `agent.*` 配置、向 OpenClaw/Hermes 注册插件与内置工具;
- 引导绑定**小米账号**(OAuth)与配置 **MiMo API Key**。

均为产品安装所需,未发现窃密/外传行为;但安装 = 给一个远端脚本系统级写权限,
建议在可信网络执行、事后检查自启服务。

## 3. Hermes 路径引用第三方 fork

`scripts/install-guide-hermes.md` 的 metadata 标明:

```yaml
metadata:
  fork: https://github.com/n0tssss/xiaomi-miloco
  branch: pr-hermes
```

即 Hermes 兼容层当时仍处于 **PR 未合并** 状态,指南让用户从第三方 fork
(`n0tssss/xiaomi-miloco`)克隆安装。**这不是官方发布的代码** —— 若走 Hermes 路径,
请确认 PR 已合入官方 main 后再用,或审计该 fork 后再执行。

## 4. 后端鉴权模型

- 后端默认监听 127.0.0.1,`GET /` 会把 `server.token` 注入返回的 HTML:
  **能访问该端口即等于拿到全部 API 权限**(增删规则、解绑账号、读全部感知日志)。
- 官方源码对此有明确警示:私网+单管理员是默认信任模型;共享网络必须反代 + TLS。
- 本适配的 `event_media_url` 同样只在可信局域网内把带 token 的 URL 交给用户。

## 5. 对本适配的影响

- miloco-dsh **只使用官方文档化/前端同款的 `/api/*` 接口 + Bearer token**,不复制 token 到磁盘;
- 不执行上游安装脚本(后端安装由用户按官方途径自行完成);
- 测试全程使用本地 mock 后端,不连接真实设备。
