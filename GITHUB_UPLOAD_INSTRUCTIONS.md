# GitHub 推送准备

当前账号需先创建一个独立的空仓库。建议 `warp-ssh-manager`，选择 **Private**，建议勾选初始化 README 以创建默认 `main` 分支；暂不添加 LICENSE 和 .gitignore。后续提交项目时以本工程的 README 覆盖初始化文件。

如果已连接可写入该仓库的 GitHub 账号，后续可由 ChatGPT 协助推送；否则使用 GitHub Desktop 打开此文件夹、提交、Publish。

推送 `main` 后，GitHub Actions 的 `Build macOS App (Universal 2)` 会自动触发。不保证首次编译成功。成功时到 Actions → 对应运行 → Artifacts 下载。

本仓库源码不可包含真实的 ~/.ssh/config、私钥和认证令牌。不要将工作目录外的个人配置复制进仓库。
