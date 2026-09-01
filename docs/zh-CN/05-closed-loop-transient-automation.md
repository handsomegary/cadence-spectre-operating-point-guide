# 第 5 章：Closed-Loop Transient Automation

本章整理 Cadence Virtuoso、Spectre 与 OCEAN 的 closed-loop transient 自动化流程。

原始笔记包含本机 project path、working checkpoint name 与 case-specific log。公开版保留
工程方法，并用占位符替换可能涉及隐私的环境信息。

## 1. 范围

本流程包含：

1. 小信号 closed-loop transient，例如 10 mV input step
2. 大信号 closed-loop transient，例如 100 mV input step
3. Slew-rate ceiling check，例如 140 mV input step
4. OCEAN script、Spectre result、raw waveform export 与 post-processing report 的分工
5. Pre-run check、执行、验证、AWK analysis 与 working checkpoint
6. 常见 command 与 post-processing error 的安全判读

这些命令是给远端 Linux shell 使用，通常通过 MobaXterm 或其他 SSH terminal 贴上执行。
不要假设 Windows 本机可以直接访问远端 Linux 文件系统。

## 2. 目录分工

OCEAN scripts 放在 Cadence project directory。PSF data、raw export 与 analysis report
放在 simulation result directories。

示例结构：

```text
Cadence project and OCEAN scripts:
/home/<linux-user>/cadence_projects/<ota-project>

OCEAN result root:
/home/<linux-user>/simulation/<ota-project>_ocean

10 mV transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_small

100 mV transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_large

140 mV slew-ceiling transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m
```

常见脚本：

```text
tran_small.ocn
tran_large.ocn
tran_slew_140m.ocn
analyze_tran_140m.awk
```

除非你刻意复制过，否则不要在 simulation result directory 里找原始 `.ocn` 脚本。

## 3. 整体数据流程

建议流程：

```text
OCEAN script
  -> Spectre transient simulation
  -> PSF database
  -> ASCII raw waveform export
  -> AWK post-processing
  -> text analysis report
  -> engineering comparison and conclusion
```

OCEAN 负责设置 design variables、transient time settings、saved signals 与 output files。
AWK 只读取既有 ASCII raw file 并计算指标。AWK 不会修改 PSF database，也不会重新执行
Spectre。

## 4. 执行前检查

进入 Cadence project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
pwd
```

确认 transient scripts 存在：

```bash
ls -lh tran_small.ocn tran_large.ocn tran_slew_140m.ocn
```

检查每份 script 的 result directory、step size、stop time、maximum time step 与 output
file：

```bash
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_small.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_large.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_slew_140m.ocn
```

检查是否有仍在执行的 Cadence 或 Spectre process：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

如果不确定既有 process 是否仍在写入同一个 result directory，不要启动另一份 simulation。

## 5. OCEAN 执行模板

一次只跑一个 transient case，且每个 case 保留独立 log。

`pipefail` 可以避免 `tee` 成功时掩盖 OCEAN 本身失败：

```bash
set -o pipefail
```

小信号 case：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_small.ocn 2>&1 | tee tran_small_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

大信号 case：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_large.ocn 2>&1 | tee tran_large_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Slew-ceiling case：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_slew_140m.ocn 2>&1 | tee tran_slew_140m_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

如果 valid raw file 已存在，而且 circuit 或 script 没有改，不要只是为了重跑
post-processing 而重新模拟。

## 6. 执行后验证

不要只因为 terminal 没有红字就信任 transient run。至少检查：

1. OCEAN/Spectre 没有 fatal error。
2. 预期 raw file 存在且不是空文件。
3. PSF directory 存在。
4. Raw file 有合理数量的 numeric rows。
5. Input/output steady-state values 合理。
6. Step direction 与 transition timing 符合原本测试设置。

140 mV case 验证示例：

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
ls -ld psf
ls -lh tran_slew_140m_raw.txt
wc -l tran_slew_140m_raw.txt
head -5 tran_slew_140m_raw.txt
tail -5 tran_slew_140m_raw.txt
```

检查 run log：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-' tran_slew_140m_run.log
tail -80 tran_slew_140m_run.log
```

原始流程中 raw file 有三行 header 或 nonnumeric rows，加上数千行 numeric data。只要数值行
数量合理，header rows 是正常现象。

## 7. Transient 指标

每个 transient case 至少保存：

```text
PRE_RISE_VIN
HIGH_FINAL_VIN
POST_FALL_VIN
PRE_RISE_VOUT
HIGH_FINAL_VOUT
POST_FALL_VOUT
ACTUAL_INPUT_STEP
ACTUAL_RISE_STEP
ACTUAL_FALL_STEP
CLOSED_LOOP_GAIN
RISE_TIME_10_TO_90
FALL_TIME_90_TO_10
MAX_POSITIVE_SR_20PS
MAX_NEGATIVE_SR_20PS
MAX_POSITIVE_SR_50PS
MAX_NEGATIVE_SR_50PS
RISE_SETTLING_1PCT
RISE_SETTLING_0P1PCT
FALL_SETTLING_1PCT
FALL_SETTLING_0P1PCT
RISE_MAX
FALL_MIN
RISE_OVERSHOOT
FALL_UNDERSHOOT
```

Rise/fall time 应使用实际 output step 的 10% 与 90% threshold，不要直接用 supply voltage
或理想 input level。

Settling band 也应依实际 output step 与 final output value 计算，尤其 finite closed-loop
gain 造成 DC tracking error 时更重要。

## 8. AWK 后处理

建议把 analyzer script 持久化保存，不要只放在 `/tmp`，因为 `/tmp` 可能在 reboot 后被清空。

若 analyzer 原本在 `/tmp`，请复制到 project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk
cmp -s -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk && echo "ANALYZER_VERIFIED"
ls -lh analyze_tran_140m.awk
```

从 result directory 执行 analyzer，并用 `tee` 保存 report：

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
awk -f /home/<linux-user>/cadence_projects/<ota-project>/analyze_tran_140m.awk \
    tran_slew_140m_raw.txt | tee tran_slew_140m_analysis.txt
```

验证 analysis report：

```bash
test -s tran_slew_140m_analysis.txt && echo "ANALYSIS_FILE_VERIFIED"
cat tran_slew_140m_analysis.txt
```

## 9. Working Checkpoint Pattern

Checkpoint 要建立在 OCEAN script 实际所在的 Cadence project directory。

使用逐字节验证：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
checkpoint="tran_slew_140m.ocn.working_$(date +%Y%m%d_%H%M%S)"
if cp -p -- tran_slew_140m.ocn "$checkpoint"; then
    if cmp -s -- tran_slew_140m.ocn "$checkpoint"; then
        echo "CHECKPOINT_VERIFIED"
        echo "SOURCE=$PWD/tran_slew_140m.ocn"
        echo "CHECKPOINT=$PWD/$checkpoint"
        ls -lh -- tran_slew_140m.ocn "$checkpoint"
    else
        echo "ERROR: The checkpoint does not match the source."
    fi
else
    echo "ERROR: Checkpoint creation failed."
fi
```

`cp -p` 会保留 timestamp，所以 checkpoint 可能显示原始修改时间，这是正常的。
`cmp -s` 的结果才是重点。

## 10. 示例结果

100 mV transient checkpoint 示例：

```text
CLOSED_LOOP_GAIN=0.965503 V/V
RISE_TIME_10_TO_90=300.717540 ps
FALL_TIME_90_TO_10=308.804621 ps
MAX_POSITIVE_SR_20PS=380.875000 V/us
MAX_NEGATIVE_SR_20PS=-349.280000 V/us
MAX_POSITIVE_SR_50PS=377.725000 V/us
MAX_NEGATIVE_SR_50PS=-347.208333 V/us
RISE_SETTLING_1PCT=0.509337 ns
RISE_SETTLING_0P1PCT=0.929337 ns
FALL_SETTLING_1PCT=0.497341 ns
FALL_SETTLING_0P1PCT=0.979341 ns
```

140 mV transient checkpoint 示例：

```text
ACTUAL_INPUT_STEP=140.000000 mV
ACTUAL_RISE_STEP=135.141600 mV
ACTUAL_FALL_STEP=135.141600 mV
CLOSED_LOOP_GAIN=0.965297 V/V
RISE_TIME_10_TO_90=304.685794 ps
FALL_TIME_90_TO_10=316.884457 ps
MAX_POSITIVE_SR_20PS=527.820000 V/us
MAX_NEGATIVE_SR_20PS=-467.490000 V/us
MAX_POSITIVE_SR_50PS=523.088000 V/us
MAX_NEGATIVE_SR_50PS=-464.868000 V/us
RISE_SETTLING_1PCT=0.520061 ns
RISE_SETTLING_0P1PCT=0.924061 ns
FALL_SETTLING_1PCT=0.506299 ns
FALL_SETTLING_0P1PCT=0.996299 ns
RISE_OVERSHOOT=0.21355 percent
FALL_UNDERSHOOT=0.50229 percent
```

原始笔记也提到 10 mV case 已完成。精确数值应以该 case 自己保存的 report 为准，不要把
未重新核对的数字直接写进 summary。

## 11. Slew-Rate Ceiling 判读

比较 100 mV 与 140 mV case 时，要一起看 output step ratio、rise/fall time ratio 与
slew-rate ratio。

判断原则：

```text
Mostly linear behavior:
  Step 变大时，slew rate 大致同比增加。
  Rise/fall time 大致相近。
  Settling time 没有大幅恶化。

Hard slew-rate ceiling:
  Slew rate 接近停在小步阶时的值。
  Rise/fall time 随 step size 明显增加。
```

原始流程的示例结论：

```text
HARD_SLEW_RATE_CEILING=NO
POSITIVE_PATH_COMPRESSION=MINIMAL
NEGATIVE_PATH_COMPRESSION=MILD
LARGE_SIGNAL_OPERATION_AT_140MV=ACCEPTABLE
```

若不同 case 使用了不同 slope window，优先采用 actual window 一致的比较。原始流程中，
20 ps window 是 100 mV 与 140 mV 之间更干净的比较依据。

## 12. 常见错误判读

`awk` 显示 `unexpected newline`：

```text
这是 post-processing command 的语法错误。
Raw waveform 和 PSF data 不会因此损坏。
避免把 <、>、<=、>=、&& 或 || 放在行尾后换行。
```

`cp` 显示 `cannot stat`：

```text
Source path 不存在。
Checkpoint 没有建立。
用 pwd、ls 或 find 确认位置。
```

`sha256sum` 显示 `No such file`：

```text
前面的 copy step 很可能失败，所以 checkpoint file 不存在。
这不影响原始 script。
```

`echo` 印出 `Checkpoint saved`：

```text
echo 只会印文字。
它不能证明 cp 成功。
请使用 if cp ...; then ... fi 加上 cmp -s。
```

前一次 run 失败，后一次 run 成功：

```text
最终结果应看最后一次 run log、PSF directory、raw file、numeric row count 与 analysis report。
不要只因为旧 log 有 error 就否定后面成功的结果。
```

## 13. 完成清单

每个 transient case：

```text
[ ] OCEAN script 位于 Cadence project directory。
[ ] 风险修改前已建立并验证 working checkpoint。
[ ] resultsDir 指向正确且独立的 case directory。
[ ] VSTEP、stop time、maxstep 已核对。
[ ] OCEAN log 已保存。
[ ] OCEAN exit status 已检查。
[ ] PSF directory 存在。
[ ] ASCII raw file 存在且非空。
[ ] Numeric row count 合理。
[ ] Input/output steady-state values 合理。
[ ] Rise/fall time 已计算。
[ ] Positive/negative slew rates 已计算。
[ ] Actual slope window 已记录。
[ ] 1% 与 0.1% settling 已计算。
[ ] Overshoot/undershoot 已计算。
[ ] Analysis output 已用 tee 保存。
[ ] 大小步阶结果已比较。
[ ] Engineering conclusion 已记录。
```

## 14. Transient 阶段状态

完成本流程后的示例 project status：

```text
DC OP:                              complete
VCM sweep:                          complete
VID sweep:                          complete
Open-loop AC:                       complete
Formal STB:                         complete
10 mV closed-loop transient:         complete
100 mV closed-loop transient:        complete
140 mV slew-ceiling transient:       complete
140 mV post-processing:              complete
140 mV analysis report:              saved
140 mV OCEAN working checkpoint:     created and verified
```

到这里，documented conditions 下的 nominal transient automation 与 large-signal
slew-ceiling check 可以视为完成。PVT、temperature、supply、load 与 mismatch sweeps
仍需要另外整理。
