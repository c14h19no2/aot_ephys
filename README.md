# aot_ephys：AOT 电生理实验（MATLAB / Psychtoolbox）

按保存的 run 日程呈现正向／反向视频、blank 或记忆图片，同时输出命名的模拟 WAV trigger，
并记录逐次 Flip、事件、响应和运行结束后的 QC。正式入口是 [run_aot_ephys.m](run_aot_ephys.m)。

## 1. 开始

已配置好的电脑上，只需进入项目文件夹再运行：

```matlab
cd('C:\path\to\aot_ephys');
run_aot_ephys();
```

必须先 `cd` 到项目文件夹，MATLAB 才能找到 `run_aot_ephys` 和 `+ephys`；YAML 读取库会在读取配置时自动加入 path。

只在以下情况运行 `setup_aot`：

- **新电脑**：从示例创建本机文件 `config/site.local.yml`、`config/active_site.yml` 和
  `config/subjects.local.yml`（已有文件保留，均不入 Git），然后在 site 文件中填写视频目录、
  播放副本目录、输出目录、屏幕和音频设备。
- **Psychtoolbox 不在 MATLAB path 上**：`setup_aot('PsychtoolboxPath','C:\path\to\Psychtoolbox')`
  在本次 MATLAB 会话中加入 PTB。

setup 只修改本次会话的 path，不下载软件、不打开设备、不保存全局 MATLAB path。

## 2. 运行

```matlab
out = run_aot_ephys();                      % 弹出窗口：被试、session、run、任务、Overwrite
out = run_aot_ephys(1,1,8);                 % sub-001_ses-01_run-08_task-video
out = run_aot_ephys(1,1,8,2);               % 同一日程的另一次记录（_record-02）
out = run_aot_ephys('patientname',1,8);     % 名称被试，日程编号见 subjects.local.yml
out = run_aot_ephys(1,1,1,'Task','memory');
```

- 被试：数字补零到 3 位（`3` → `sub-003`）并使用同号日程；名称（只含字母和数字）原样保留，
  其日程编号写在 `config/subjects.local.yml`。
- 输出：`<paths.output_root>/<采集日期 yyyy-mm-dd>/<输出名称>/`。当天已有同名输出时在开始前停止；
  勾选／传入 Overwrite 时旧文件夹改名为 `_replaced-<时分秒>` 保留，不删除任何数据。
- 按键：Space 开始；Q 中止并保存已记录部分，命令行显示 “Run stopped with Q.”，不报错；记忆任务用 J/K。

详细说明：[运行](docs/running.md)、[输入参数](docs/run_arguments.md)、[配置参数](docs/configuration.md)、
[输出与 QC](docs/log_format.md)。

## 3. 配置与素材

| 内容 | 位置 |
| --- | --- |
| 通用实验参数（时长、trigger、显示） | [config/experiment.yml](config/experiment.yml) |
| 本机设备与路径 | `config/site.local.yml`（模板 [site.example.yml](config/site.example.yml)） |
| 当前使用的 site | `config/active_site.yml` 的 `site_file` |
| 名称被试 → 日程编号 | `config/subjects.local.yml`（模板 [subjects.example.yml](config/subjects.example.yml)） |
| Debug 参数 | [config/debug.yml](config/debug.yml) |
| 保存的日程与答案 | [config/runs/](config/runs/README.md) |
| 原始 WAV | [assets/triggers/](assets/triggers) |

配置合并顺序：`experiment.yml → 所选 site → debug.yml（仅 Debug）`。视频、播放副本和图片放在仓库之外，
由 site 指定。

正式播放使用预先准备的无损播放副本，运行时不调用 FFmpeg／Python。只在准备副本的电脑上运行：

```matlab
prepare_aot_ephys_native_media();        % 所选视频目录中的全部 MP4
prepare_aot_ephys_native_media(1,1,8);   % 或只准备一个 run 用到的视频
```

## 4. Trigger 与时序

视频任务通过 PsychPortAudio 以 48000 Hz 在 channel 2 输出四个原始 WAV：run 开始、run 结束、
视频／blank onset，以及默认关闭的视频 offset。它们是模拟波形，不是整数 TTL 编码。音频按记录的
Flip 时间轴提前预约，与画面 onset 保持固定关系。固定注视与 blank 按首次 onset + n × IFI 刷新。

**Windows 笔记本注意事项**

- 显示缩放设为 100%（150% 时 PTB 同步检查经常失败）；接通电源；运行前关闭其他程序。
- Intel 集成显卡在 Windows 上通常强制三缓冲（PTB 启动画面左右抖动即为迹象），实际显示可能比
  Flip 时间戳晚约一帧。正式采集前须用光电二极管与 trigger 在同一采集时钟上记录，确认延迟恒定，
  见 [硬件验证](docs/hardware_validation.md)。

软件日志和测试通过都不能代替物理光电／电信号测量。

## 5. 测试

```matlab
results = run_tests();               % 单元测试：不需要本机 site、视频、PTB 或设备
results = run_tests('integration');  % 合成视频测试，需要 FFmpeg／ffprobe
```

可选的真实素材与设备检查见 [docs/testing.md](docs/testing.md)。

## 6. 目录

```text
run_aot_ephys.m        正式入口
+ephys/                会话、播放、trigger、日志、QC 和工具函数
config/                通用配置、模板和保存的日程
assets/triggers/       原始 WAV
tools/                 离线视频副本准备（Python）
tests/                 单元、合成媒体、真实媒体测试与设备检查说明
docs/                  运行、配置、输出、架构、测试和硬件验证文档
third_party/           YAML 依赖及其许可
```

开发约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，架构见 [docs/architecture.md](docs/architecture.md)，
依赖见 [docs/dependencies.md](docs/dependencies.md)，更新记录见 [CHANGELOG.md](CHANGELOG.md)。
更新已加载的 MATLAB 类后，在下次运行前执行 `clear classes; rehash`。
