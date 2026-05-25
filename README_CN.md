以下是该文档的中文翻译：

# Orbit Multi Researcher

用于 Linux 服务器的基于 tmux 的可复用 Codex 多智能体框架。

Orbit 封装了一个实用的固定三智能体工作流：

* `researcher`（研究员）：分解用户/PI（主要研究人员）的目标，分配工作，检查严谨性，并报告决策。
* `executor`（执行器）：运行代码实现、实验、环境修复以及监控。
* `helper`（助手）：准备验证、分析、审计包、模板以及摘要。

该框架在设计上刻意保持保守。它标准化了通信、持久化的收件箱/发件箱记录、ACK（确认响应）、低频监控以及 Claude 审查策略，而没有将特定项目的实验逻辑硬编码在内。

## 环境要求

* 带有 `bash`、`tmux`、`python3`、`awk`、`sed` 和 `sha256sum` 的 Linux 服务器。
* 在该服务器上已安装并完成身份验证的 Codex CLI。
* 可选但推荐：用于独立审查工作流的 Claude CLI。

Orbit **不会**复制或管理 Codex 身份验证信息。在启动智能体之前，每台服务器都应拥有自己独立可用的 Codex 登录凭据。

## 安装

克隆此仓库：

```bash
git clone https://github.com/yhc98002-bit/Orbit-multi-researcher.git
cd Orbit-multi-researcher

```

直接从代码目录使用 Orbit：

```bash
export PATH="$PWD/bin:$PATH"

```

或者在 `~/.local/bin` 中安装软链接：

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"

```

## 快速开始

为一个项目工作区初始化 Orbit：

```bash
orbit init --workspace /path/to/project

```

运行部署检查：

```bash
orbit doctor

```

预览 tmux 启动情况，但不实际启动任何内容：

```bash
orbit launch --dry-run

```

启动这三个 Codex 会话：

```bash
orbit launch

```

检查会话：

```bash
orbit status

```

发送一个任务：

```bash
orbit send executor "Please ACK and inspect the current failing job."

```

从文件发送一个较长的任务：

```bash
orbit send-file helper /path/to/task.md

```

以 Worker（工作者）的风格向 Researcher 发送返回通知：

```bash
orbit notify researcher --from helper --type task_completion "analysis completed"

```

## 核心命令

```bash
orbit init --workspace PATH [--orbit-home PATH] [--codex-home PATH] [--force]
orbit launch [--dry-run]
orbit status
orbit peek researcher|executor|helper
orbit send executor|helper "message"
orbit send-file executor|helper /path/to/message.md
orbit queue executor|helper "message"
orbit notify researcher --from helper|executor|watcher [--type TYPE] [--severity LEVEL] "message"
orbit doctor
orbit role-prompt researcher|executor|helper

```

## 目录结构

运行 `orbit init` 后，默认的状态目录为：

```text
~/.codex/orbit/
  config.toml
  comm/
    inbox/
      executor/
      helper/
    outbox/
  logs/
  payloads/
  state/
  templates/

```

使用以下方式覆盖状态目录：

```bash
export ORBIT_HOME=/path/to/orbit-state

```

## 消息传递模型

Orbit 是围绕持久化通信设计的，因为终端 UI 传递可能会失败，或者把文本卡在输入框（composer）中。

* 简短的单行消息可以直接发送到目标 tmux 窗格。
* `[Task assigned by Researcher]`（由研究员分配的任务）、多行消息以及长消息，始终会写入到 `$ORBIT_HOME/comm/inbox/<agent>/..._payload.md`。
* Worker（工作者）仅收到包含 `file_sha256` 和 `file_bytes` 的简短指针。
* Worker 的通知会在尝试通过 tmux 传递之前，将 JSONL 记录追加到 `$ORBIT_HOME/comm/outbox/` 下。
* 如果 tmux 传递受阻，持久化的收件箱/发件箱文件将作为唯一的事实依据（source of truth）。

## 智能体工作流

推荐的 Researcher（研究员）流程：

1. 将用户意图转化为有边界的任务。
2. 使用 `orbit send` 或 `orbit send-file` 来分配任务。
3. 对于重要任务，要求 Worker 在采取实际行动之前给出一行的 ACK（确认）。
4. 仅在处理新任务或主动调试时进行快速轮询。
5. 对于稳定且运行时间较长的作业，等待完成或 P0 级别的发件箱通知。
6. 将未完成的工作如实报告为未完成；不要夸大结论。

推荐的 Worker（工作者）流程：

1. 从收件箱读取任务指针文件。
2. 确认（ACK）任务及边界。
3. 仅执行分配的工作。
4. 编写持久化的报告/产出物 (artifacts)。
5. 使用 `orbit notify researcher --from <role> ...` 通知研究员。

## Claude 审查策略

默认配置文件记录了以下 Claude CLI 审查命令：

```bash
claude -p \
  --dangerously-skip-permissions \
  --output-format json \
  --model opus \
  --effort max \
  "your prompt"

```

在进行实质性的代码实现、实验执行、指标计算或结果解释时，请使用 Claude 审查。对于简单的、低风险的状态检查或文件检查，Worker 可以跳过审查，但应说明跳过的原因。

## 在新服务器上部署

1. 在新服务器上安装并验证 Codex CLI。
2. 克隆此仓库。
3. 将 `bin/` 添加到 `PATH` 或运行 `./install.sh`。
4. 运行 `orbit init --workspace /path/to/project`。
5. 运行 `orbit doctor`。
6. 运行 `orbit launch --dry-run`。
7. 运行 `orbit launch`。

**不要**在服务器之间复制机器本地的 Codex 状态，例如 `auth.json`、Codex 会话数据库、旧的收件箱/发件箱日志或实验输出。

## 特定项目的监控器 (Watchers)

Orbit 核心不了解 GPU、论文约束、奖励定义、评估数据集划分或实验模式。请将这些作为特定项目的监控器 (watchers) 或配置文件来保留。

监控器可以通过以下方式进行报告：

```bash
orbit notify researcher --from watcher --type watcher_event --severity stage "checkpoint reached"

```

预期模式请参考 `examples/watchers/`。

## 故障排除

检查基本健康状况：

```bash
orbit doctor
orbit status

```

检查某个 Worker 窗格：

```bash
orbit peek executor
orbit peek helper

```

如果通知未出现在 Researcher 窗格中，请检查持久化的发件箱文件：

```bash
ls -lt "$ORBIT_HOME/comm/outbox"
tail -n 20 "$ORBIT_HOME/comm/outbox/helper_to_researcher.jsonl"

```

如果发送了长任务，请检查 Worker 的收件箱：

```bash
find "$ORBIT_HOME/comm/inbox" -type f -maxdepth 3 -print

```

如果 `git` 或其他命令因为服务器代理而失败，请在 Orbit 外部修复服务器的网络配置；Orbit 不负责管理网络代理。