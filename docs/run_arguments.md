## Function inputs

```matlab
out = run_aot_ephys();   % 弹出输入窗口
out = run_aot_ephys(sub,ses,run[,recordingNumber],'Name',value,...);
```

`[,recordingNumber]` 表示可选参数，实际输入时不要键入方括号。

| 输入 | 默认 | 含义 |
| --- | --- | --- |
| `sub` | 必填 | 被试标签。数字补零到 3 位（`3` → `sub-003`，`17` → `sub-017`）；字母数字名称原样保留（`'patientname'` → `sub-patientname`）；可带 `sub-` 前缀。只允许字母和数字（不能含下划线或空格：下划线用于分隔输出名称的各部分，如 `patient_name` 无效）。 |
| `ses` / `run` | 必填 | 正整数，与被试的日程编号一起选择保存的日程并命名输出。 |
| 第 4 个 `recordingNumber` | 省略 | 正整数，输出追加 `_record-XX`；仅区分重复记录，`[]` 等同省略。 |
| `'Task'` | `'video'` | `'video'` 或 `'memory'`。 |
| `'Overwrite'` | `false` | 当天已有同名输出时，将旧文件夹改名为 `<名称>_replaced-<时分秒>` 后重新记录；不删除任何数据。为 `false` 时已有输出会在开始前报错。 |
| `'Site'` | `config/active_site.yml` 的 `site_file` | 临时覆盖默认选择，指定另一份 site YAML。 |
| `'Schedule'` | 自动选择 | 自定义有序日程 YAML；日常运行无需自己构建日程变量。 |
| `'SubjectMap'` | `config/subjects.local.yml` | 被试标签到日程编号的对应表；见下文。 |
| `'Answers'` | `''` | 与记忆日程匹配的答案 TSV；未提供时不计算正确率。 |
| `'Debug'` | `false` | 加载短 trial／800 × 600 窗口配置，输出名称加 `_debug`。 |
| `'DebugSkipSyncTests'` | `false` | 仅限 Debug；跳过 PTB 同步检查，使用配置的刷新间隔。 |
| `'DebugSimulatedInputOnly'` | `false` | 仅限 Debug；自动继续指导语并模拟记忆响应，不记录参与者键盘输入。 |
| `'Backend'` | `[]` | `ephys.TriggerBackend` 对象；空值按 YAML 选择视频 WAV 或记忆 dummy。 |

### 输出位置

每次记录保存到 `<paths.output_root>/<采集日期 yyyy-mm-dd>/<输出名称>/`。例如 2026-10-26 运行
`run_aot_ephys(1,1,8,2)` 的输出为 `2026-10-26/sub-001_ses-01_run-08_task-video_record-02`，Debug 再加 `_debug`。
同一名称在不同日期各自保存；输入窗口会提示该名称在其他日期已有记录。

输出的 `run_identity` 保存被试标签（文本）、session、run、可选记录编号、实际使用的日程编号
`schedule_set` 及其来源 `schedule_set_source`；`run_output` 保存采集日期、`overwrite` 和被改名的旧文件夹
`replaced_output`（无则为空）。

### 被试标签与日程编号

保存的日程文件名为 `experiment_settings_sub_NN_ses_SS_run_RR.yml`，其中 `NN` 是日程编号。
数字被试始终使用自身编号（`sub-003` 使用第 3 套日程），无需写入对应表。名称被试必须写入本地对应表
`config/subjects.local.yml`（`setup_aot` 从 `subjects.example.yml` 创建，不入 Git），否则运行在开始前停止：

```yaml
subjects:
  - {label: patientname, schedule_set: 3}
```

每个条目写在一行。对应表不能为数字被试指定其他编号，否则运行在开始前报错。标签会出现在输出文件夹名和 manifest 中，建议使用研究编号而非真实姓名。

### 输入窗口

不带参数调用 `run_aot_ephys()` 时，窗口依次询问被试、session、run、任务（video／memory）和
Overwrite。窗口下方实时显示输出路径、所用日程及其来源；输入无效、日程不存在或当天已有同名输出
（未勾选 Overwrite）时 Start 不可用。取消返回空字符串。窗口在开始前关闭，不会与实验窗口重叠。
需要记录编号、Debug 或其他选项时，请使用命令行形式。
