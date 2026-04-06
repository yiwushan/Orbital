# Orbital 更新与推送作业规范 (SOP)

> 适用范围：`yiwushan/Orbital` 的日常开发、推送与设备部署。
>
> 强制要求：每次更新都必须按本文流程执行，不得跳步。

## 1. 目标与原则

- 代码唯一发布源：`origin`（你的 fork：`https://github.com/yiwushan/Orbital.git`）。
- 上游同步源：`upstream`（原作者仓库：`https://github.com/AthBe1337/Orbital.git`）。
- 设备运行路径：`/home/athbe/Orbital`（不再使用 `/root/Orbital` 作为代码目录）。
- 部署方式：设备本机编译 + `systemd` 重启服务。

## 2. 标准环境基线

### 2.1 本地开发机 (WSL/PC)

在项目根目录执行，必须满足：

```bash
git remote -v
```

预期至少包含：

- `origin  https://github.com/yiwushan/Orbital.git`
- `upstream  https://github.com/AthBe1337/Orbital.git`

### 2.2 设备端 (OnePlus6T)

服务文件必须指向：

- `ExecStart=/home/athbe/Orbital/build/run.sh`
- `WorkingDirectory=/home/athbe/Orbital/build`

核查命令：

```bash
sudo systemctl cat orbital.service
```

## 3. 每次更新的强制流程

### 3.1 开发前同步（本地）

```bash
cd /path/to/Orbital
git fetch upstream
git switch master
git rebase upstream/master
git push origin master
```

### 3.2 功能开发（本地）

```bash
git switch -c feat/<feature-name>
# 开发与修改
cmake -B build
cmake --build build -j$(nproc)
```

提交前必须满足：

- `git status` 无非预期文件。
- 编译通过（`cmake --build` 成功）。
- 变更说明可追踪（commit message 清晰）。

### 3.3 提交与推送（本地）

```bash
git add -A
git commit -m "feat: <summary>"
git push -u origin feat/<feature-name>
```

如果你采用“直接在 master 维护”模式，至少要求：

```bash
git switch master
git merge --ff-only feat/<feature-name>
git push origin master
```

## 4. 设备部署流程（必须按顺序）

### 4.1 登录设备

```bash
ssh athbe@10.16.12.170
```

### 4.2 更新代码到最新 `origin/master`

```bash
cd ~/Orbital
git fetch --all --prune
git switch master
git pull --ff-only origin master
```

### 4.3 设备本机编译

```bash
cmake -S /home/athbe/Orbital -B /home/athbe/Orbital/build -DCMAKE_BUILD_TYPE=Release
cmake --build /home/athbe/Orbital/build -j$(nproc)
```

### 4.4 重启服务并验活

```bash
sudo systemctl daemon-reload
sudo systemctl restart orbital.service
sudo systemctl status orbital.service --no-pager -n 25
sudo journalctl -u orbital.service -n 50 --no-pager
```

验收标准（全部满足才算成功）：

- `orbital.service` 显示 `active (running)`。
- 主进程路径包含 `/home/athbe/Orbital/build/run.sh`。
- 日志中无导致启动失败的错误（允许非致命 warning）。

## 5. 发布记录要求

每次部署后，必须记录以下信息（可写在 issue、笔记或变更日志）：

- 部署时间（含时区）。
- 部署 commit 哈希（`git rev-parse --short HEAD`）。
- 是否重启服务成功。
- 是否出现 warning/error（简要列出）。

## 6. 回滚规范（必须掌握）

### 6.1 代码回滚（推荐）

```bash
cd ~/Orbital
git log --oneline -n 20
# 选择一个可用旧版本 <GOOD_COMMIT>
git checkout <GOOD_COMMIT>
cmake -S /home/athbe/Orbital -B /home/athbe/Orbital/build -DCMAKE_BUILD_TYPE=Release
cmake --build /home/athbe/Orbital/build -j$(nproc)
sudo systemctl restart orbital.service
```

恢复到 master：

```bash
git switch master
git pull --ff-only origin master
```

### 6.2 service 配置回滚

如果服务文件误改，恢复备份：

```bash
sudo cp /etc/systemd/system/orbital.service.bak.<timestamp> /etc/systemd/system/orbital.service
sudo systemctl daemon-reload
sudo systemctl restart orbital.service
```

## 7. 禁止事项

- 禁止在未编译验证前直接重启线上服务。
- 禁止跳过 `git pull --ff-only origin master` 直接部署旧代码。
- 禁止在设备端随意改动 `/etc/systemd/system/orbital.service` 且不留备份。
- 禁止把 `/root/Orbital` 当作主开发目录继续迭代。

## 8. 快速执行清单（每次照抄）

```text
[ ] 本地同步 upstream/master
[ ] 本地完成开发并编译通过
[ ] 推送到 origin
[ ] 设备 pull origin/master
[ ] 设备编译通过
[ ] 重启 orbital.service
[ ] 检查 active (running)
[ ] 检查进程路径为 /home/athbe/Orbital/build/run.sh
[ ] 记录部署时间 + commit + 结果
```
