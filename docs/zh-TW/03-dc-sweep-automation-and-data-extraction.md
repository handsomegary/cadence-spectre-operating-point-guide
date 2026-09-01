# 第 3 章：DC Sweep Automation and Data Extraction

本章把 VCM/VID sweep 筆記整理成可公開、可重複使用的 Cadence Virtuoso、Spectre、
OCEAN workflow。原始筆記中的本機路徑與專案名稱已改成占位字。

## 1. 範圍

本流程包含：

1. 在 schematic 參數化 `VCM` 與 `VID`
2. 用 OCEAN 跑 DC operating point、VCM sweep、VID sweep
3. 擷取 swept device operating-point data
4. 檢查 MOS `region` 與 saturation margin
5. 由 VID sweep 計算 1% DC linearity

示例條件：

```text
Circuit type:        five-transistor one-stage OTA
Supply:              VDD = 1.2 V
Nominal VCM:         0.8 V
Nominal VID:         0 V
Temperature:         27 deg C
Corner:              <process-corner>
```

這些只是示例，不是所有設計都必須採用的規格。

## 2. 目錄結構

建議把 scripts 和 batch results 與 GUI ADE results 分開：

```text
OCEAN scripts:
/home/<linux-user>/cadence_projects/<ota-project>

ADE netlist:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/netlist

Quick netlist inspection file:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs

OCEAN result root:
/home/<linux-user>/simulation/<ota-project>_ocean

DC OP results:
/home/<linux-user>/simulation/<ota-project>_ocean/dcop

VCM sweep results:
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm

VID sweep results:
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid
```

常用腳本：

```text
dcop.ocn
vcm_sweep.ocn
vid_sweep.ocn
inspect_vid_linearity.ocn
```

確認可用的腳本可用日期後綴保存：

```bash
cp -p vid_sweep.ocn vid_sweep.ocn.working_YYYYMMDD
```

## 3. 穩定的 GUI-to-Batch 流程

只有 schematic 層級資訊改變時才需要回 Virtuoso：

1. Circuit topology 改變。
2. Device size 或 source property 在 schematic 中改變。
3. 新增 design variable。
4. Instance name 改變。
5. 為 STB analysis 加入或移除 `iprobe`。

建議流程：

1. 修改 schematic。
2. 執行 **Check and Save**。
3. 在 ADE 使用 **Variables -> Copy From Cellview**。
4. 確認所有 design variables 的 nominal values。
5. 使用 **Simulation -> Netlist -> Recreate**。
6. 若下一步要跑 OCEAN batch，不要在 ADE 按 **Run**。
7. 確認 Virtuoso 沒有寫入同一個 result directory。
8. 從 Linux shell 執行 OCEAN script。

Batch simulation 前：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

理想狀況是沒有輸出。若有其他 Cadence process，請確認它使用不同 result directory。

## 4. 參數化 VCM 與 VID

Differential input pair 的兩個 input source 建議使用同一組變數：

```text
Vin+ DC value: VCM + VID/2
Vin- DC value: VCM - VID/2
```

因此：

```text
VCM = (Vin+ + Vin-) / 2
VID = Vin+ - Vin-
```

改完 source property 後，執行 **Check and Save**、copy variables from cellview、
設定 nominal values，然後 recreate netlist。

檢查 netlist：

```bash
grep -nE '^parameters|V[0-9]+.*vsource' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

預期形式：

```text
parameters VCM=<nominal-vcm> VID=0
V0 (...) vsource dc=VCM+VID/2 ...
V1 (...) vsource dc=VCM-VID/2 ...
```

## 5. DC OP 與 DC Sweep

單點 operating point：

```lisp
desVar("VCM" 800m)
desVar("VID" 0)
analysis('dc ?saveOppoint t)
```

Parameter sweep：

```lisp
analysis('dc
    ?saveOppoint t
    ?param "VCM"
    ?start "0"
    ?stop "1.2"
    ?step "10m"
)
```

`saveOpPoint()` 只指定要保存哪些 device OP quantities；它不會自己建立 DC analysis。

## 6. VCM Sweep Pattern

示例：

```text
VCM:   0 V to VDD
Step:  10 mV
VID:   0 V
```

OCEAN 核心：

```lisp
resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm")

desVar("VCM" 800m)
desVar("VID" 0)

analysis('dc
    ?saveOppoint t
    ?param "VCM"
    ?start "0"
    ?stop "1.2"
    ?step "10m"
)

save('v "/vout")

saveOpPoint("/PM0" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/PM1" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM0" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM1" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM2" ?operatingPoints "ids gm gds vgs vds vdsat region")

temp(27)
run()

selectResult('dc)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/vcm_devices_raw.txt"
    v("/vout")
    getData("NM0:ids") getData("NM0:region")
    getData("NM1:ids") getData("NM1:region")
    getData("NM2:ids") getData("NM2:region")
    getData("PM0:ids") getData("PM0:region")
    getData("PM1:ids") getData("PM1:region")
)

exit()
```

執行與驗證：

```bash
ocean -nograph -restore vcm_sweep.ocn 2>&1 | tee vcm_sweep_run.log
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|Segmentation' vcm_sweep_run.log
awk 'NF==12 {n++} END {print "VCM_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/vcm_devices_raw.txt
```

0 V 到 1.2 V、step 10 mV 時，預期是 `121` 個資料點。

## 7. VID Sweep Pattern

示例：

```text
VCM:   fixed at nominal common-mode voltage
VID:   -50 mV to +50 mV
Step:  100 uV
```

OCEAN 核心：

```lisp
resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid")

desVar("VCM" 800m)
desVar("VID" 0)

analysis('dc
    ?saveOppoint t
    ?param "VID"
    ?start "-50m"
    ?stop "50m"
    ?step "100u"
)

save('v "/vout")
```

其他 `saveOpPoint()` 和 `ocnPrint()` 可沿用 VCM sweep pattern，輸出到：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/vid_devices_raw.txt
```

-50 mV 到 +50 mV、step 100 uV 時，預期是 `1001` 個資料點。

## 8. Swept Device Data 的正確抓法

單點 DC OP：

```lisp
selectResult('dcOpInfo)
pv("/NM0" "ids")
```

Swept DC data：

```lisp
selectResult('dc)
getData("NM0:ids")
```

原始 IC618 環境中的關鍵差異：

```text
Correct for swept device OP: getData("NM0:ids")
Wrong in that environment:   getData("/NM0:ids")
```

Node voltage 仍使用：

```lisp
v("/vout")
```

如果 `outputs()` 看得到 `/NM0:ids`，但 `getData("/NM0:ids")` 回傳 `nil`，請測試
`getData("NM0:ids")`。

## 9. Raw TXT 欄位對應

輸出 `vout` 加五顆 device 的 `ids`、`region` 時，每列有 12 欄：

```text
$1  = sweep variable, VCM or VID
$2  = VOUT
$3  = NM0 ids
$4  = NM0 region
$5  = NM1 ids
$6  = NM1 region
$7  = NM2 ids
$8  = NM2 region
$9  = PM0 ids
$10 = PM0 region
$11 = PM1 ids
$12 = PM1 region
```

找出五顆 MOS 都回報 `region = 2` 的列：

```bash
awk 'NF==12 && $4==2 && $6==2 && $8==2 && $10==2 && $12==2 {
    if (!seen) { first=$1; seen=1 }
    last=$1
    count++
}
END {
    if (seen)
        print "FIRST_ALL_REGION2 =",first,
              "\nLAST_ALL_REGION2  =",last,
              "\nPOINTS =",count
    else
        print "No all-region-2 point found"
}' INPUT_FILE.txt
```

示例 checkpoint：

```text
VCM all-region-2 sampled range: 0.72 V to 1.2 V
VID all-region-2 sampled range: -18.2 mV to +13.8 mV
```

這不等於 1% linear input range。

## 10. Saturation Margin

用 `vds` 和 `vdsat` 交叉確認 `region`：

```text
SAT_MARGIN = abs(VDS) - abs(VDSAT)
```

判讀：

```text
SAT_MARGIN > 0: inside saturation condition
SAT_MARGIN = 0: boundary
SAT_MARGIN < 0: outside saturation condition
```

OCEAN pattern：

```lisp
openResults("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/psf")
selectResult('dc)

nm0Margin = abs(getData("NM0:vds")) - abs(getData("NM0:vdsat"))
nm1Margin = abs(getData("NM1:vds")) - abs(getData("NM1:vdsat"))
nm2Margin = abs(getData("NM2:vds")) - abs(getData("NM2:vdsat"))
pm0Margin = abs(getData("PM0:vds")) - abs(getData("PM0:vdsat"))
pm1Margin = abs(getData("PM1:vds")) - abs(getData("PM1:vdsat"))
```

限制元件會隨 topology 與 bias point 改變，每個設計都要重新確認。

## 11. 計算前先輸出 Scientific Notation

Raw `ocnPrint()` 可能有 `100u`、`1m`、`69.6u` 這類 suffix。一般 AWK 不會自動把它們
轉成浮點數。

計算 gain 或 percentage error 前，先輸出 scientific notation：

```lisp
openResults("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/psf")
selectResult('dc)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/vid_vout_scientific.txt"
    ?numberNotation 'scientific
    ?precision 12
    v("/vout")
)

exit()
```

## 12. 1% DC Linearity

原始流程使用「相對於零點小訊號斜率的 secant-gain error」：

```text
A0 = [VOUT(+100 uV) - VOUT(-100 uV)] / 200 uV
Gsec(VID) = [VOUT(VID) - VOUT(0)] / VID
error_percent = 100 * abs[Gsec(VID)/A0 - 1]
```

判斷：

```text
error_percent <= 1: pass
error_percent > 1: fail
```

`VID = 0` 時分母為零，必須跳過。這是 DC transfer linearity，不是 THD、AC response
或 transient large-signal distortion。

示例 checkpoint：

```text
A0 = 31.4345 V/V
A0 = 29.948 dB
Interpolated 1% input range: -1.094528 mV <= VID <= +2.046602 mV
```

原始流程也得到：

```text
Five-device all-region-2 sampled VID range: -18.2 mV to +13.8 mV
```

兩者不同。MOS 還在 saturation，不代表 OTA transfer curve 仍符合 1% linearity。

## 13. 最小驗證清單

信任 sweep 前請檢查：

1. 沒有非預期 Cadence process 使用同一個 result directory。
2. OCEAN log 沒有 `OCN-`、`ERROR`、`FATAL`、`SYNTAX`、`Segmentation`。
3. Sweep data point 數量正確。
4. `VID = 0` 時，對稱 testbench 的 branch current 對稱。
5. `region` boundary 有用 saturation margin 交叉確認。
6. 百分比計算使用 scientific notation。
7. 保存 dated known-good script checkpoint。
8. 保留 main script、final log 和 final data。

## 14. 重點整理

1. 在 schematic 一次性參數化 `VCM` 與 `VID`，之後用 OCEAN sweep。
2. 單點 `dcOpInfo` 用 `pv()`；swept device waveform 用 `getData()`。
3. `region = 2` 範圍和 1% linear input range 是不同規格。
4. 上傳公開文件前，請清掉 username、private path、PDK name、VM IP 與未公開 project name。
