# Output records and runtime QC

默认播放器是 `ephys.NativeMoviePlayer`。离线准备以 x264 无损编码复制视频，保留解码 YUV
内容、分辨率、像素格式、帧数和 PTS 间隔，只把首 PTS 归零。每帧 YUV MD5 与原视频
逐项比较，原文件转换前后 SHA-256 一致；转换命令、版本、文件哈希和全部 PTS 保存为映射。

每次呈现提前启动 no-drop 解码，取出并保留首帧；每一次取帧比较预期源帧顺序和 PTS。
重复／缺失／错误 PTS、额外帧以及过早 EOF 均记录后继续；过早结束时保持最后可绘制帧，
直到配置的视频时段结束。源帧编号仅由与离线映射中唯一 PTS 的匹配得到（容差 1 µs），
匹配不成功时 `source_frame_index` 和 `source_pts_s` 为 `NaN`，仍保存原始 `decoder_pts_s`。
编号不是 PTB 提供的原生帧编号，也不是运行时的纹理像素认证。
正常情况下首帧对应源帧 0，通过其实际 Flip 建立显示时间轴；若首帧异常，保留实际身份并标记 QC。
后续按 PTS 调度；缺少 PTS 时仅为继续显示使用映射中的时刻，映射用尽后使用映射末帧的时长，
这些调度回退不会被写成观测到的 PTS。正常重复刷新、解码晚到、显示跳过分别记录。

`movie_preparation_start/end` 记录当前项获取句柄；`cache_hit` 表示已提前准备。
`native_lookahead_start/ready` 记录下一视频在当前预注视阶段的提前准备及截止时间。
manifest 的 `native_trials` 保存每次呈现的解码 PTS、推定源帧顺序、跳过编号和最大取帧耗时。
其中 `qc_issues` 保存异常类型、期望值与实际值，`preparation_overrun_s` 保存加载晚到秒数。
中止时仍打开的当前／下一句柄保存到 `native_pending_trials`，可区分已呈现部分与仅提前准备的素材。
原文件和播放副本在窗口打开前校验哈希；实验期间应保持素材目录不变。
加载界面不计入开头基线；基线在 Space 确认之后独立开始。

`startup_loading_start/end`、`startup_movie_load_start/end` 和 `loading` 阶段 Flip
单独记录启动加载，均为 `trial_nr=0`，不增加刺激次数、不发送视频 marker。
manifest 的 `startup_loading` 保存实际预加载文件、数量、纹理预算和起止时间。

`frames` 旧后端仍可显式选择，其按需完整解码会增加运行时间。

每次运行保存到 `<paths.output_root>/<采集日期 yyyy-mm-dd>/<输出名称>/`，例如
`2026-10-26/sub-003_ses-01_run-08_task-video/`。manifest 的 `run_identity` 记录被试标签、session、run、
记录编号和实际日程编号（`schedule_set`、`schedule_set_source`）；`run_output` 记录采集日期、
是否 Overwrite，以及被改名保留的旧文件夹 `replaced_output`。诊断工具不使用日期子文件夹。
文件夹内包含：

| 文件 | 内容 |
| --- | --- |
| `*_flips.tsv` | 每次 Flip 的 VBL／刺激 onset／返回时间、源帧、PTS、阶段、光电方块状态及 `frame_qc_flags`。 |
| `*_events.tsv` | 指导语、准备、基线、刺激起止、响应和中止事件。 |
| `*_markers.tsv` | 事件 ID、日志序号、命名 trigger／WAV、关联 Flip／输入、预约／音频时间、同步、取消及 `audio_qc_flags`。 |
| `*_trial_qc.tsv` | 视频／记忆 trial 的时长、重复／跳帧、时间戳及 marker 检查；trigger 偏移按与本 run 中位数的差判定。 |
| `*_resolved_config.json` | 本次实际合并后的配置。 |
| `*_manifest.json` | 完成／中止状态、媒体哈希、日程、版本、显示信息、两端基线、WAV 协议、实际音频设备和波形元数据。 |
| `*_trigger_offsets.pdf` | 自动生成的两页 PDF：偏移随时间的散点图、偏移直方图；含范围、中位数、标准差，以及偏离中位数和偏离零超过参考值的次数。 |
| `sources/` | 本次配置／日程／答案的原样副本及哈希。 |
| `frame_maps/` | 按原视频名保存的帧映射 JSON，包含帧编号、PTS、内容校验和及解码来源。 |

### Fixation 的固定刷新时间表

初始／结尾基线、预／后注视和 blank 的重复刷新，目标为该阶段首次实际 onset 加上
`n × IFI`，IFI 来自本次打开的显示窗口（60 Hz 时约 16.67 ms）。晚到时跳过过期目标，
不从晚到的 Flip 重新起算，不延长配置的阶段边界，也不快速补交过期帧。
结尾基线仍提前停止重复刷新，为 run-end WAV 预约留出余量。

`*_flips.tsv` 新增以下字段；非网格调度的 Flip（建立时间原点、独立关闭光电方块、视频帧等）
及旧日志没有这些目标，保持 `NaN`。

| 字段 | 含义 |
| --- | --- |
| `refresh_target_getsecs` | 固定网格上的期望 onset；不是实际显示时间。 |
| `refresh_index` | 相对阶段首次 onset 的刷新槽编号，起点为 0；跳过目标时编号可以不连续。 |
| `refresh_skipped_slots` | 本次之前未提交的刷新槽数；不是光电测得的物理丢帧数。 |
| `refresh_error_s` | PTB `stimulus_onset_getsecs − refresh_target_getsecs`，单位秒；正值表示估计的显示晚到。 |

`phase_flip_seq` 仍是实际提交次数，连续递增；`requested_deadline_getsecs` 仍是传给 PTB 的
`when` 阈值（目标减半个 IFI）。`submission_mode` 的 `fixed_fixation_timed` 表示直接预约
下一固定目标；`fixed_fixation_macos_target` 表示 Mac 外部显示路径等到目标再提交。
它们不修改原始 PTB 时间戳，也不改变视频首帧与 WAV 的同步方式。

### Trigger 偏移报告

PDF 在实验呈现结束、原始日志保存后自动导出，无需额外命令或 Python。正常完成、按 Q 中止和可恢复错误都会生成。
偏移为 `audio_start_getsecs - associated_flip_getsecs`，正值表示音频估计时间较晚；参考线使用本次配置的
`markers.wav.max_sync_error_s`。已有音频和画面时间戳的同步失败事件也会画出；取消、dummy 和未确认的事件不计入分布。
没有有效时间戳对时，PDF 会注明无数据，不会填入零偏移。图中时间均为软件／驱动估计，不代表物理光电校准。
manifest 的 `trigger_offset_report` 保存 PDF 文件名、统计结果和导出状态；导出失败会警告，原始日志仍会保留。
导出保留画布内的页边距，不传入仅较新 MATLAB 才支持的 `Padding` 选项。
两个时间各自如何得到、"predicted onset" 如何计算、如何读这份 PDF，见 [trigger_timing.md](trigger_timing.md)。
保存结束后，命令行会输出三行简要统计，例如：

```text
Trigger offsets (audio - visual): N=86, median=+7.695 ms, SD=0.598 ms.
Range=[+3.715, +7.763] ms; absolute-offset P95=7.746 ms; software/driver estimates.
Beyond median +/-2 ms (trial QC rule): 2/86 (2.3%); beyond +/-2 ms of zero: 86/86.
```

第三行先给出偏离本 run 中位数超过参考值的次数（trial QC 的判定规则，含 run 开始／结束），
再给出偏离零超过参考值的次数。恒定偏移只影响后者。

无有效音频／画面时间戳对时只输出两行无数据说明。设备打开失败、音频未启动／未完成等运行错误仍会报告。

### 运行中的 QC 策略

可恢复的质量问题只记录，实验继续：刷新率偏离参考、音频预约提前量不足、audio underrun、
音频完成时间未被驱动确认、视频加载晚到、PTS／帧序异常和提前 EOF。
日志缓冲超过初始估算时自动扩容，保留全部记录。
实际音画预约目标与实际 Flip／音频时间照实保存，异常不会被改写成零偏移或成功状态。

- `*_markers.tsv` 的 `audio_qc_flags`、`audio_lead_shortfall_s` 和 `audio_xruns` 记录音频问题。
  完成状态未确认的 marker 保持 `status=failed`、`qc_only_failure=1`，实际时间未知时保留 `NaN`；
  该次预约会停止，后续事件继续，不会补造已发出的 trigger。
- `*_flips.tsv` 的 `frame_qc_flags` 和 manifest 的 `native_trials[].qc_issues` 记录帧问题。
  `*_trial_qc.tsv` 汇总这些异常及加载晚到秒数。
- Trigger 偏移只在与本 run 偏移中位数相差超过 `markers.wav.max_sync_error_s`（默认 2 ms）时计为
  同步问题（`audio_sync_issue_count`），该 trial 记为 `timing_anomaly_detected`；恒定偏移不计。
  中位数取自与 PDF 相同的 trigger（含 run 开始／结束），保存在 `run_qc.audio_visual_median_s`；
  每个 trial 另有 `max_abs_delta_from_run_median_s`。markers 文件中的 `sync_status` 仍相对于零偏移，
  trial QC 不再使用 `out_of_tolerance`，只计 `failed`、`late` 和 `missing_timestamp`。
  详见 [trigger_timing.md](trigger_timing.md) 第 7 节。
- manifest 的 `status=complete` 仅表示实验流程已完成；应另外查看 `run_qc`。
  `post_run_qc.status=complete` 表示 QC 计算完成，其结果仍可能包含异常。
  QC 计算或 PDF 生成失败会记录错误，不会把完成的实验改为中止；原始日志和合并后的配置优先保存。

运行前的配置、素材及输出目录检查保留。设备调用失败、完全没有可绘制首帧、
波形预约相互冲突、程序内部状态错误和无法保存原始数据等无法恢复的问题仍报错；Q 仍按中止处理。

### 初始基线的刷新检查（refresh guard）

这是开始 trial 之前的采集前提条件，不属于上面可恢复的 QC。初始基线结束（其边界 Flip 之后）、
第一个 trial 之前，程序用内存中的该基线 Flip 记录计算：固定网格上可用的刷新槽数，以及实际
提交的槽数（`refresh_index` 有限的行）。实际比例低于 `display.refresh_guard_min_fraction`
（默认 0.9）时报 `ephys:RefreshGuard`，在第一个 trial 之前停止；随后按普通中止路径保存全部日志，
并只尝试一次 run-end 波形。检查在基线与第一个 trial 之间只读取内存中的数值槽编号（约 1 ms），
不写文件，不改变绘制、Flip 请求或阶段时长，第一个预注视 Flip 仍落在基线结束后的下一次刷新；
间隔类指标在呈现结束后由 `writeOutput` 从同一批 Flip 记录补充。基线可用槽不足 1 s 时记为 `not_evaluated`，`null` 时记为 `disabled`，
两者都不停止运行。

结果保存为 `trial_nr=0` 的 `refresh_guard` 事件（`status` 与 `detail`），以及 manifest 的
`refresh_guard`：`status`（`passed`、`failed`、`not_evaluated`、`disabled`；未完成初始基线时为
`not_run`）、`available_slots`、`presented_slots`、`presented_fraction`、`min_fraction`、
`max_skipped_slots`、`interval_median_ms`，以及仅供参考的
`timestamp_grid_deviation_median_ifi`（相邻 onset 间隔偏离整数个 IFI 的中位数，单位为 IFI）。
通过检查只说明软件循环能按刷新率提交，不代表物理显示时间已验证。

查看实际呈现的时间：

```matlab
timeline = ephys.reconstructTimeline(videoOut);
disp(timeline.initial_fixation)
disp(timeline.final_fixation)
disp(timeline.trials)
```

两端汇总包括配置时长、实际起止、观测时长、结束误差和中止状态。没有结束边界时，时长保持未知（MATLAB `NaN`／JSON `null`）。旧输出缺少结尾基线参数时记为 `not_configured`，不会按当前配置重新解释旧记录。

刷新间隔波动本身不等于源帧时间未知：重建使用逐次 Flip 的观测时间，并标记非有限／不递增时间戳和源帧跳过。但这些是 PTB 软件时间戳。当前视频任务的 trigger 后端为 **wav**，物理显示、声卡输出延迟和电生理记录对齐仍未实测；见 [HARDWARE_VALIDATION.md](hardware_validation.md)。`ephys.fitClockMapping` 需要独立核实的事件／波形对应关系，当前 WAV 使用音频开始估计建立时钟映射；`ephys.attachFeatures` 需要与精确媒体哈希匹配且已验证的特征／PTS 映射。

日志在呈现期间缓存在内存中，正常结束或可恢复错误后写盘；突然断电仍可能丢失尚未保存的记录。

