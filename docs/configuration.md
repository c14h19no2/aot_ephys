# Configuration and parameters

```text
aot_ephys/
  run_aot_ephys.m           正式入口
  +ephys/                  运行、解码、日志、重建及公共工具
  config/
    experiment.yml        跨设备的实验时长、任务和通用配置
    active_site.yml       本地选择文件，不入 Git
    active_site.example.yml 选择文件模板，由 setup 复制
    site.example.yml      新设备配置模板
    site.local.yml        本机屏幕、路径、注视尺寸及批准标记
    subjects.example.yml  被试标签→日程编号对应表模板，由 setup 复制
    subjects.local.yml    本机被试对应表，不入 Git
    debug.yml             Debug 窗口和短 trial 参数
    runs/
      main/               被试视频 run 日程
      memory_main_complete/ 默认 360 图片记忆日程
      memory_main/        旧 180 图片日程及 answers/
      debug_*.yml         小型调试日程
      source_manifest.json 原始日程复制校验记录
  tests/                  unit、integration、local_media 与 hardware 检查
  tools/                  离线视频副本准备
  outputs/                本机实验输出，不入 Git
```

site 选择顺序为：显式 `'Site'` 参数优先，否则读取 `active_site.yml` 的 `site_file`。
无参数的 `run_aot_ephys()` 窗口第一行可选择 site（`config/site.*.yml`，不含示例）；选择其他 site 并按
Start 时，窗口把它写入 `active_site.yml` 的 `site_file`（保留注释），之后的运行都使用它。
`site.example.yml` 只用于创建新 site，不参与运行时合并。配置合并顺序为 `experiment.yml → 所选 site → debug.yml（仅 Debug）`。
所选 site 不会再继承 `site.local.yml`；site 只需写需要覆盖的字段。未知字段会报错；自定义 site 中旧的时长覆盖应移回公共配置，以保持设备间一致。
通过选择文件启动时，选择文件与实际 site 都会复制到本次输出的 `sources/` 并保存哈希；
`resolved_config.json` 同时记录 `site_path` 和 `site_selection_path`。

名称被试（如 `patientname`）所用的日程编号写在本地 `subjects.local.yml`，格式与示例见
[run_arguments.md](run_arguments.md#被试标签与日程编号)。该文件可能含有可识别参与者的标签，
因此不入 Git，也不复制到输出 `sources/`；输出只在 `run_identity` 中记录实际日程编号及来源。

[config/experiment.yml](../config/experiment.yml) 的公共时长为：

```yaml
protocol:
  approved_for_acquisition: false
  video_initial_fixation_s: 5
  video_final_fixation_s: 5
  video_pre_fixation_s: 1.0
  video_duration_s: 2.5
  video_post_fixation_s: 0.1
```

本地 `site.local.yml` 的 `protocol` 只保留 `approved_for_acquisition: True`；时长从公共配置继承。这个批准标记决定是否允许非 Debug 运行，它本身不提供真实 TTL 或物理时序验证。

### 公共实验参数

后缀 `_s` 表示秒，`_px` 表示像素，`rgb255` 表示 0–255 的 RGB 三元组。

| 参数 | 当前正式值／含义 |
| --- | --- |
| `protocol.video_initial_fixation_s` | 当前 5；开头视频注视基线，0 禁用，以公共 YAML 为准。 |
| `protocol.video_final_fixation_s` | 当前 5；正常结束后的注视基线，0 禁用，以公共 YAML 为准。 |
| `protocol.video_pre_fixation_s` | 1.0；每个视频／blank 项前的注视。 |
| `protocol.video_duration_s` | 2.5；每个视频／blank 项的时长。 |
| `protocol.video_post_fixation_s` | 0.1；每项结束后的注视。 |
| `input.instruction_continue_key` | `space`；指导语继续键。 |
| `input.memory_yes_key` / `memory_no_key` | `j` / `k`；见过／没见过。 |
| `input.quit_key` | `q`；中止键。 |
| `instructions.video` / `instructions.memory` | 对应任务的指导语。 |
| `instructions.text_height_px` | 指导语字体尺寸。 |
| `stimulus.movie_canvas_px` | 兼容旧 site 配置保留；当前显示尺寸由窗口和素材实际宽高决定，该字段不再限制显示区域。 |
| `stimulus.movie_scale` | 相对于完整适配窗口后的额外缩放，范围 `(0,1]`；默认 `1` 使一组对边贴齐窗口，小于 `1` 会进一步缩小。注视点始终在窗口中心。 |
| `stimulus.background_rgb255` | 背景颜色，目前 `[128,128,128]`。 |
| `stimulus.target_size_deg` | 影片应占的视角 `[宽, 高]`（度），默认 `[14.42, 8.14]`；与 `display.screen_size_cm` 一起用于计算观看距离。`null` 时不计算。 |
| `task.name` / `task.memory_variant` | 任务与记忆版本标签；运行时根据所选记忆日程更新版本。 |

视频和记忆图片均完整显示，按素材真实宽高比等比缩放并居中，外围使用
`stimulus.background_rgb255` 灰色背景。缩放比例为
`min(窗口宽 / 素材宽, 窗口高 / 素材高) × movie_scale`，适用于不同分辨率和横竖素材。
默认 `movie_scale: 1` 时，一组对边贴齐窗口，只在另一方向出现必要的灰边；
窗口与素材宽高比相同时没有灰边。
例如当前 1440 × 900 窗口中，1920 × 1080 影片显示为 **1440 × 810**：
左右贴齐窗口，上下各留 45 像素。切换为 1920 × 1080 窗口时，影片完整铺满窗口。
进一步缩小 `movie_scale` 时仍保持居中，此时可能在四边留白。

**观看距离。** 在 site 文件中设置 `display.screen_size_cm`（可见画面的宽和高，厘米）后，运行窗口
会显示受试者眼睛到屏幕的距离，使影片正好占 `stimulus.target_size_deg`（默认 14.42° × 8.14°）。
计算方法：按上述规则得到影片的像素矩形，乘以每像素的厘米数（屏幕厘米 ÷ `resolution_px`）得到影片的
实际宽高，再由 `距离 = (宽 / 2) / tan(视角宽 / 2)` 计算，高度方向同理；两个方向的结果取平均。
例如 30 × 16.875 cm 的屏幕、1920 × 1080 窗口、`movie_scale: 1` 时，影片宽 30 cm，距离约 118.6 cm。
若量得的屏幕宽高比与分辨率不一致，两个方向的距离会不同，窗口会提示该距离下影片的实际视角，
请重新测量。结果同时保存在 manifest 的 `viewing` 中。

**注视点。** 注视点按原 Python 版本以视角度定义（`stimulus.fixation.*_deg`），位于窗口中心（影片中心）。
受试者坐在上述距离时，影片宽度对应 14.42°，因此像素距离为 `d = (影片宽像素 / 2) / tan(7.21°)`，
视角为 a 的元素宽 `2 × d × tan(a / 2)` 像素；不需要屏幕厘米数，任何分辨率都保持同样的视角。
1920 像素宽的影片上：底衬 24.20 px、中心点 4.84 px、线宽 1.04 px（原设备 1920 px／69 cm、196 cm
时分别为 17.39、3.48 和 0.75 px）。绘制顺序：底衬 → 两条抗锯齿白线 → 黑点。原说明要求最后画线，
但中心点只有几个像素，两条白线会盖住大部分黑色，看起来是白点，所以点画在线之上。原说明中的白色描边
默认不画（`outline_width_deg: 0`）；设为 0.00788 时在黑点边缘加 1.04 px 白色描边。
底衬与点各为一张窗口打开时生成的 8 × 8 超采样抗锯齿纹理，按像素对齐绘制。像素尺寸和驱动支持的
平滑线宽范围保存在 manifest 的 `fixation` 中；线宽超出该范围时运行开始会警告。
实际素材矩形 `[left, top, right, bottom]` 记录在 manifest 的 `media[].display_rect_px` 中；
视频矩形在呈现前计算并缓存，视频播放期间不重新计算布局。

### 设备、呈现和日志参数

| 参数 | 含义 |
| --- | --- |
| `protocol.approved_for_acquisition` | 非 Debug 运行需要为 `true`。 |
| `display.screen_index` | PTB 显示编号；`Screen('Screens')` 查看可用编号。 |
| `display.resolution_px` | 期望窗口宽高 `[width,height]`；必须与实际打开的窗口一致。 |
| `display.expected_refresh_hz` | 期望刷新率；用于调度检查及日志容量估算。 |
| `display.refresh_tolerance_hz` | PTB 调度刷新率与期望值的差异参考；超出时警告并记录，使用实际 PTB 间隔继续。 |
| `display.full_screen` | 是否全屏；Debug 改为窗口。 |
| `display.skip_sync_tests` | PTB 同步检查跳过开关；正式运行保持 `false`。 |
| `display.screen_size_cm` | 刺激屏幕可见画面的实际宽高 `[宽, 高]`（厘米），在 site 文件中用尺子量取；默认 `null`（观看距离未知）。见下文“观看距离”。 |
| `display.refresh_guard_min_fraction` | 初始基线结束时的刷新检查：基线固定网格刷新槽中实际提交的最低比例，默认 `0.9`。低于该值时在第一个 trial 之前停止运行，按中止保存；基线不足 1 s 时只记录、不判定；`null` 关闭判定。 |
| `display.steady_flip` | 视频任务的 onset 呈现方式，默认 `true`：在每个带 WAV 的 onset 之前逐帧刷新注视画面直到 onset 所在刷新，使每个 onset 前显示管线状态相同。site 中设为 `false` 时改为首帧提前绘制并保持到定时 Flip。两种模式的比较方法见 [trigger_timing.md](trigger_timing.md#10-held-and-steady-onset-modes)。 |
| `input_device_index` | PTB 键盘编号；`-1` 使用默认设备。 |
| `paths.video_root` / `picture_root` | 日程中原始 MP4／PNG 所在目录。 |
| `paths.output_root` | 每次记录的输出父目录；`run_aot_ephys` 在其下按采集日期 `yyyy-mm-dd` 建子文件夹。 |
| `stimulus.fixation.surround_diameter_deg` / `surround_fringe` | 灰色圆形底衬的外径（视角度，默认 0.18270°）及边缘比例（默认 0.3）：半径内 70% 不透明，外 30% 按升余弦（PsychoPy `raisedCosine`）渐变到透明。在灰色背景上不可见，叠在视频上为柔边灰盘。 |
| `stimulus.fixation.dot_diameter_deg` / `outline_width_deg` | 黑色中心点直径（默认 0.03654°）及可选白色描边宽度（以点的边缘为中心；默认 `0`，不画描边；原说明为 0.00788°）。 |
| `stimulus.fixation.line_width_deg` | 过中心 45° 和 135° 两条白色贯穿线的宽度（默认 0.00788°），在中心点之前绘制（点在线之上），并做抗锯齿。 |
| `stimulus.fixation.line_rgb255` / `outline_rgb255` / `dot_rgb255` / `surround_rgb255` | 线、描边、点和底衬的颜色；底衬与背景同为 128 灰。 |
| `photodiode.enabled` | 光电二极管方块总开关，默认 `false`。开启后每一帧都在 `rect_px` 处画一个实心方块，位于影片、注视点和文字之上：影片显示期间（首帧 Flip 到移除末帧的 Flip）为 `on_rgb255`，其余时间（加载、指导语、基线、注视、blank、记忆图片、run 开始／结束）为 `off_rgb255`。每次 Flip 在 flips 日志记录 `photodiode_state`，影片 onset／offset 事件记录 `photodiode_transition`。 |
| `photodiode.approved_placement` | 开启方块时必须为 `true`，表示该 site 接受这个对受试者可见的方块，包括它遮住的影片部分（如全屏影片的一角）。否则运行在配置检查时停止。 |
| `photodiode.rect_px` | 方块位置 `[left, top, right, bottom]`（窗口像素，整数），必须在窗口内，例如左上角 `[0, 0, 60, 60]`。液晶屏自上而下刷新，顶部方块比底部早将近一帧亮起，请固定一个位置。 |
| `photodiode.on_rgb255` / `off_rgb255` | 方块的亮／暗颜色，默认白 `[255,255,255]`／黑 `[0,0,0]`；两者必须不同。 |
| `photodiode.fixation_onset_enabled` | 另在每个 trial 预注视开始时亮一帧，下一次刷新熄灭（事件 `photodiode_off`），标记 trial 开始；预注视至少需两帧。默认 `false`。 |
| `playback.ffmpeg_path` / `ffprobe_path` | 仅离线准备副本及旧 `frames` 播放器使用；空值时自动查找。正式 `native` 运行忽略这些字段。 |
| `playback.backend` | 默认 `native`：独立 PTB 句柄与滚动提前准备；`frames`：保留旧的完整 RGB 解码和纹理缓存播放器。 |
| `playback.python_path` | 离线准备所用 Python；空值使用 `python3`。仅需 Python 标准库。 |
| `playback.native_media_root` | 必须明确填写的原生播放副本目录；例如 `C:\path\to\aot_movie\derived_media\native`。缺失、空值、`null` 或 `none` 会报错。 |
| `playback.native_buffer_s` | 原生 no-drop 解码缓冲容量，默认 `3 s`，必须覆盖完整视频时段。 |
| `playback.native_prepare_timeout_s` | 完全取不到可绘制首帧时的等待上限，默认 `5 s`；预注视截止时间仅用于记录加载晚到。 |
| `playback.native_disable_hw_decode` | 默认 `false`；本机 site 为 `true`，使用 PTB 官方软件视频解码选项。显示和 Flip 仍由 PTB/GPU 执行。 |
| `playback.startup_preload_movies` | Space 提示前准备的视频句柄数，默认 `2`；原生模式允许 `1` 或 `2`。旧 `frames` 模式按不同文件缓存，`0` 可关闭。 |
| `playback.max_texture_bytes` | 所有缓存视频合计的估计 RGBA 纹理内存上限，默认 1 GiB；不包括 CPU 数据、窗口等其他开销。 |
| `markers.backend` | 视频使用 `wav`，通过 PsychPortAudio 输出模拟波形；`dummy` 仅供无声软件测试。 |
| `markers.memory_backend` | 记忆任务当前使用独立的 `dummy`，只保存命名事件，不复用视频 WAV。 |
| `markers.video_offset_enabled` | 默认 `false`；视频／blank offset 仍记录实际 Flip 时间。 |
| `markers.fixation_onset_enabled` | 默认关闭；没有为该事件配置真实 WAV。 |
| `markers.memory_onset_enabled` | 是否记录记忆图片 onset，默认开启。 |
| `markers.run_boundary_enabled` | 是否输出实验开始／结束波形，默认开启。 |
| `markers.blank_enabled` | blank 刺激 onset 共用视频 onset 波形，默认开启。 |
| `markers.waveforms` | `run_start`、`run_end`、`video_onset`、备用 `video_offset` 对应的 WAV 文件名。 |
| `markers.wav.directory` | 波形资源目录；相对路径基于 `aot_ephys/`。 |
| `markers.wav.device_index` / `device_name` | 音频设备 ID／名称约束；空值选择系统默认输出，实际设备写入 manifest。 |
| `markers.wav.sample_rate_hz` / `channels` / `gain` | 默认 `48000`／`2`／`0.5`；原始 100 点波形不重采样，脉宽约 2.083 ms。 |
| `markers.wav.output_channel` | 输出通道：`1` 为左声道，`2` 为右声道，默认 `2`；另一声道保持静音。可在当前 site YAML 覆盖。 |
| `markers.wav.latency_class` | PsychPortAudio 延迟等级，默认 `2`；实际支持情况取决于设备。 |
| `markers.wav.minimum_lead_s` / `minimum_low_s` | 默认 0.1 s 目标预约提前量及 0.01 s 波形间静音间隔；提前量不足只记录，波形重叠仍禁止。 |
| `markers.wav.max_sync_error_s` | 默认 0.002 s。trial QC 中，trigger 偏移与本 run 偏移中位数相差超过此值才计为同步问题，恒定偏移不计；同时是偏移日志、PDF 和结束汇总的参考值。超出不会中止实验。 |
| `markers.wav.completion_timeout_s` | 默认 2 s；结束／关闭时等待波形完成的上限。 |
| `eyelink.enabled` / `address` | 是否使用 EyeLink，以及设备地址。 |
| `eyelink.calibration_type` | 校准图形，默认 `HV13`。 |
| `eyelink.calibration_area_proportion` / `validation_area_proportion` | 传给 EyeLink 的校准／验证区域比例。 |
| `eyelink.sample_rate_hz` | 请求的 EyeLink 采样率。 |
| `logging.max_flips` / `max_events` / `max_markers` | 预分配日志容量上限；容量不足时中止，避免静默丢记录。 |

本机注视尺寸来自 Python 参考配置的像素换算，尚未测量其在当前屏幕上的视角匹配。Debug 使用 5 px 半径和 50 px 周围直径。当前绘制器没有使用的 `fringe_fraction` 和 `eyelink.edf_prefix` 已从正式配置移除。

### WAV Trigger 与发送时机

公共 [config/experiment.yml](../config/experiment.yml) 的 `markers.waveforms` 保存命名事件与 WAV 的映射。
当前协议使用 `trigger_key` 和 `waveform_file`，已经移除整数事件码、数字位宽和归零码。
`marker_nr` 只是日志行序号；声卡输出的是模拟波形，不会自动转换为整数 TTL 编码。
每次运行保存原始 YAML、解析配置和音频设备／波形来源信息。

Debug 默认也使用真实 WAV，并记录音画偏移，在结束后统一汇总；`DebugSkipSyncTests` 仅控制 PTB 的显示同步检查。
只检查流程、无需输出音频时，可显式使用模拟后端：

```matlab
videoOut = run_aot_ephys(1,1,8,2,'Debug',true, ...
    'DebugSkipSyncTests',true,'Backend',ephys.DummyTriggerBackend());
```

`markers.wav.device_index`／`device_name` 为空时使用系统默认输出。本次声卡诊断实际选择了
`MacBook Pro Speakers`，并未接入记录系统；使用外置设备时应在 site YAML 中选择该设备。

| `trigger_key` | 默认 WAV | 输出边界 |
| --- | --- | --- |
| `run_start` | `TrigP08.wav` | Space 后，与开头基线之前的开始边界 Flip 对齐。 |
| `video_onset` | `TrigP16.wav` | 视频源第 0 帧或 blank 刺激阶段的首次 Flip。 |
| `run_end` | `TrigN08.wav` | 正常结束与最终基线结束边界对齐；按 Q 中止时也输出一次。 |
| `video_offset` | `TrigN16.wav` | 默认关闭；开启时与切回后注视的 Flip 对齐。 |

正向、反向视频和 blank 共用 onset 波形，身份由 `video_file`、`condition` 和 trial 编号识别。
两端基线不额外发送视频波形。开始前的 loading／指导语退出不发送实验结束波形；
run 开始后按 Q，取消未来预约、停止呈现、尽快发送一次结束波形，待其完成后关闭音频。
正常结束与中止共用 `run_end`，事件日志的 `status` 区分 `complete`／`aborted`。

正常完整 run 8 应输出 **86 次波形**：72 次视频 onset、12 次 blank onset，以及开始／结束各一次。
取消记录不算已输出波形。历史输出保留当时的数字协议和原始数量。

同步采用 **完成首帧绘制 → 预测共同 onset → 预约音频并连续提交已绘制的 Flip → 关联实际 Flip**。
预测 onset 由 `ephys.predictVisualOnset` 计算：沿用 PTB `PredictVisualOnsetForTime` 的规则
（请求时间之后的第一次刷新），但以本次 Session 记录的上一次 Flip 的 VBL 时间为起点，
而非 PTB 内部的 `LastVBLTime`。Windows 测试笔记本上该内部值随读取时机变化，曾使空白之后的
trial 的音频预约比其他 trial 早约 7–13 ms；Mac 上两者完全相同。PTB 的消隐期校正在打开窗口时
按相同规则计算一次，保存在 manifest 的 `display_timing.vbl_duration_s`。
更新另一台电脑时，请删除旧的 `aot_ephys/+ephys/Session.m`，保留整个 `+ephys/@Session/`
目录，并在 MATLAB 执行 `clear classes; rehash;`。正式入口会检查实际加载的实现；
旧单文件版本不能与类目录并存。
视频／blank onset、run 开始和正常结束共用此路径。预注视循环和下一视频的准备都在
音频预约之前完成；预约后不再插入注视 Flip、媒体加载或首帧绘制。
剩余预注视期间，屏幕前缓冲仍保持原注视画面，首帧留在后台直到目标 Flip。
固定的预注视、视频和首尾基线时长不变；绘制后若已无法满足音频最小提前量，
仍保存失败日志并中止，不静默推迟既定边界。

Windows／普通显示后端在 WAV 预约返回后立即调用定时 `Screen('Flip')`，
`submission_mode=direct`。定时 Flip 是同步调用：等待期间 Q 由键盘队列保存，
返回后立即处理并发送一次结束波形；这段等待不能撤回已经输出的 onset 波形。
Mac 外部显示后端曾在本机提前呈现远期 Flip，因此等待至音频预约使用的同一预测 onset
才调用 Flip，记录为 `macos_external_target`。它不再将提前约半帧的 Flip 请求阈值当作
实际等待终点。等待期间继续检查 Q，但不重画或 Flip 注视画面；提交和显示耗时仍保留
在原始偏移中，没有根据本机统计值平移音频或修改时间戳。
该兼容路径不代表 Windows 的直接提交方式已在 Mac 上通过验证。

输出声道在 `active_site.yml` 当前选中的 site YAML 中设置，例如：

```yaml
markers:
  wav:
    output_channel: 2  # 1 = left, 2 = right; the other channel is silent.
```

`channels: 2` 表示打开两个声卡输出通道；`output_channel` 选择脉冲所在的那一路。
程序参照 `trigger_example/Orientation.m` 的 `FillBuffer` 数据布局，
将原 WAV 的 100 点脉冲放入所选输出行，保持波形文件、幅值、极性和采样点不变。
每条波形日志的 `output_channel`、resolved config 和 manifest 都会保存所选通道。
音频通道号对应声卡输出；记录系统输入通道由实际接线决定。
WAV 在 loading 阶段读取、预加载并静音预热。使用 48000 Hz 播放原始每声道 100 个采样点，
不因源 WAV 标注 22050 Hz 而重采样。预约不会自动跟随迟到的 Flip；偏差、欠载、取消和错误均保留。
PTB 报告的音频开始时间是设备／驱动估计，`physical_onset_getsecs` 未经独立测量保持未知。
设备、音频输出与显示光电同步的实测步骤见 [HARDWARE_VALIDATION.md](hardware_validation.md)。

`*_markers.tsv` 保存 `trigger_key`、`waveform_file`、计划／预测／实际音频时间、关联 Flip、
`audio_visual_delta_s`、`sync_status`、取消结果和完成状态。QC 的 `onset_marker_request_lag_s`
现在通常为负值，表示在视觉 onset 之前预约音频；它不是实际音画延迟。实际音画估计差见
`audio_visual_delta_s`。记忆图片、J／K 响应使用命名的
`memory_stimulus_onset`、`memory_response_yes`、`memory_response_no` 软件事件，当前不输出 WAV。

`*_markers.tsv` 与 `*_flips.tsv` 额外记录 `frame_ready_getsecs`、
`flip_submit_getsecs` 和 `submission_mode`；markers 还保存 `flip_return_getsecs`。
`frame_ready_getsecs` 表示 CPU 已完成绘制调用并通知 PTB，不是独立测得的 GPU 完成或发光时间。
可用 `flip_submit_getsecs-write_getsecs` 检查预约后到 Flip 调用的间隔，
以及 `flip_return_getsecs-flip_submit_getsecs` 检查 Flip 阻塞时间。

