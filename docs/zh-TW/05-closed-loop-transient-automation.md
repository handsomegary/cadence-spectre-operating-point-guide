# 第 5 章：Closed-Loop Transient Automation

本章整理 Cadence Virtuoso、Spectre 與 OCEAN 的 closed-loop transient 自動化流程。

原始筆記包含本機 project path、working checkpoint name 與 case-specific log。公開版保留
工程方法，並用占位字替換可能涉及隱私的環境資訊。

## 1. 範圍

本流程包含：

1. 小訊號 closed-loop transient，例如 10 mV input step
2. 大訊號 closed-loop transient，例如 100 mV input step
3. Slew-rate ceiling check，例如 140 mV input step
4. OCEAN script、Spectre result、raw waveform export 與 post-processing report 的分工
5. Pre-run check、執行、驗證、AWK analysis 與 working checkpoint
6. 常見 command 與 post-processing error 的安全判讀

這些命令是給遠端 Linux shell 使用，通常透過 MobaXterm 或其他 SSH terminal 貼上執行。
不要假設 Windows 本機可以直接存取遠端 Linux 檔案系統。

## 2. 目錄分工

OCEAN scripts 放在 Cadence project directory。PSF data、raw export 與 analysis report
放在 simulation result directories。

示例結構：

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

常見腳本：

```text
tran_small.ocn
tran_large.ocn
tran_slew_140m.ocn
analyze_tran_140m.awk
```

除非你刻意複製過，否則不要在 simulation result directory 裡找原始 `.ocn` 腳本。

## 3. 整體資料流程

建議流程：

```text
OCEAN script
  -> Spectre transient simulation
  -> PSF database
  -> ASCII raw waveform export
  -> AWK post-processing
  -> text analysis report
  -> engineering comparison and conclusion
```

OCEAN 負責設定 design variables、transient time settings、saved signals 與 output files。
AWK 只讀取既有 ASCII raw file 並計算指標。AWK 不會修改 PSF database，也不會重新執行
Spectre。

## 4. 執行前檢查

進入 Cadence project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
pwd
```

確認 transient scripts 存在：

```bash
ls -lh tran_small.ocn tran_large.ocn tran_slew_140m.ocn
```

檢查每份 script 的 result directory、step size、stop time、maximum time step 與 output
file：

```bash
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_small.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_large.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_slew_140m.ocn
```

檢查是否有仍在執行的 Cadence 或 Spectre process：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

如果不確定既有 process 是否仍在寫入同一個 result directory，不要啟動另一份 simulation。

## 5. OCEAN 執行範本

一次只跑一個 transient case，且每個 case 保留獨立 log。

`pipefail` 可以避免 `tee` 成功時掩蓋 OCEAN 本身失敗：

```bash
set -o pipefail
```

小訊號 case：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_small.ocn 2>&1 | tee tran_small_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

大訊號 case：

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

如果 valid raw file 已存在，而且 circuit 或 script 沒有改，不要只是為了重跑
post-processing 而重新模擬。

## 6. 執行後驗證

不要只因為 terminal 沒有紅字就信任 transient run。至少檢查：

1. OCEAN/Spectre 沒有 fatal error。
2. 預期 raw file 存在且不是空檔。
3. PSF directory 存在。
4. Raw file 有合理數量的 numeric rows。
5. Input/output steady-state values 合理。
6. Step direction 與 transition timing 符合原本測試設定。

140 mV case 驗證示例：

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
ls -ld psf
ls -lh tran_slew_140m_raw.txt
wc -l tran_slew_140m_raw.txt
head -5 tran_slew_140m_raw.txt
tail -5 tran_slew_140m_raw.txt
```

檢查 run log：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-' tran_slew_140m_run.log
tail -80 tran_slew_140m_run.log
```

原始流程中 raw file 有三行 header 或 nonnumeric rows，加上數千行 numeric data。只要數值列
數量合理，header rows 是正常現象。

## 7. Transient 指標

每個 transient case 至少保存：

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

Rise/fall time 應使用實際 output step 的 10% 與 90% threshold，不要直接用 supply voltage
或理想 input level。

Settling band 也應依實際 output step 與 final output value 計算，尤其 finite closed-loop
gain 造成 DC tracking error 時更重要。

## 8. AWK 後處理

建議把 analyzer script 持久化保存，不要只放在 `/tmp`，因為 `/tmp` 可能在 reboot 後被清空。

若 analyzer 原本在 `/tmp`，請複製到 project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk
cmp -s -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk && echo "ANALYZER_VERIFIED"
ls -lh analyze_tran_140m.awk
```

從 result directory 執行 analyzer，並用 `tee` 保存 report：

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
awk -f /home/<linux-user>/cadence_projects/<ota-project>/analyze_tran_140m.awk \
    tran_slew_140m_raw.txt | tee tran_slew_140m_analysis.txt
```

驗證 analysis report：

```bash
test -s tran_slew_140m_analysis.txt && echo "ANALYSIS_FILE_VERIFIED"
cat tran_slew_140m_analysis.txt
```

## 9. Working Checkpoint Pattern

Checkpoint 要建立在 OCEAN script 實際所在的 Cadence project directory。

使用逐位元組驗證：

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

`cp -p` 會保留 timestamp，所以 checkpoint 可能顯示原始修改時間，這是正常的。
`cmp -s` 的結果才是重點。

## 10. 示例結果

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

原始筆記也提到 10 mV case 已完成。精確數值應以該 case 自己保存的 report 為準，不要把
未重新核對的數字直接寫進 summary。

## 11. Slew-Rate Ceiling 判讀

比較 100 mV 與 140 mV case 時，要一起看 output step ratio、rise/fall time ratio 與
slew-rate ratio。

判斷原則：

```text
Mostly linear behavior:
  Step 變大時，slew rate 大致同比增加。
  Rise/fall time 大致相近。
  Settling time 沒有大幅惡化。

Hard slew-rate ceiling:
  Slew rate 接近停在小步階時的值。
  Rise/fall time 隨 step size 明顯增加。
```

原始流程的示例結論：

```text
HARD_SLEW_RATE_CEILING=NO
POSITIVE_PATH_COMPRESSION=MINIMAL
NEGATIVE_PATH_COMPRESSION=MILD
LARGE_SIGNAL_OPERATION_AT_140MV=ACCEPTABLE
```

若不同 case 使用了不同 slope window，優先採用 actual window 一致的比較。原始流程中，
20 ps window 是 100 mV 與 140 mV 之間更乾淨的比較依據。

## 12. 常見錯誤判讀

`awk` 顯示 `unexpected newline`：

```text
這是 post-processing command 的語法錯誤。
Raw waveform 和 PSF data 不會因此損壞。
避免把 <、>、<=、>=、&& 或 || 放在行尾後換行。
```

`cp` 顯示 `cannot stat`：

```text
Source path 不存在。
Checkpoint 沒有建立。
用 pwd、ls 或 find 確認位置。
```

`sha256sum` 顯示 `No such file`：

```text
前面的 copy step 很可能失敗，所以 checkpoint file 不存在。
這不影響原始 script。
```

`echo` 印出 `Checkpoint saved`：

```text
echo 只會印文字。
它不能證明 cp 成功。
請使用 if cp ...; then ... fi 加上 cmp -s。
```

前一次 run 失敗，後一次 run 成功：

```text
最終結果應看最後一次 run log、PSF directory、raw file、numeric row count 與 analysis report。
不要只因為舊 log 有 error 就否定後面成功的結果。
```

## 13. 完成清單

每個 transient case：

```text
[ ] OCEAN script 位於 Cadence project directory。
[ ] 風險修改前已建立並驗證 working checkpoint。
[ ] resultsDir 指向正確且獨立的 case directory。
[ ] VSTEP、stop time、maxstep 已核對。
[ ] OCEAN log 已保存。
[ ] OCEAN exit status 已檢查。
[ ] PSF directory 存在。
[ ] ASCII raw file 存在且非空。
[ ] Numeric row count 合理。
[ ] Input/output steady-state values 合理。
[ ] Rise/fall time 已計算。
[ ] Positive/negative slew rates 已計算。
[ ] Actual slope window 已記錄。
[ ] 1% 與 0.1% settling 已計算。
[ ] Overshoot/undershoot 已計算。
[ ] Analysis output 已用 tee 保存。
[ ] 大小步階結果已比較。
[ ] Engineering conclusion 已記錄。
```

## 14. Transient 階段狀態

完成本流程後的示例 project status：

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

到這裡，documented conditions 下的 nominal transient automation 與 large-signal
slew-ceiling check 可以視為完成。PVT、temperature、supply、load 與 mismatch sweeps
仍需要另外整理。
