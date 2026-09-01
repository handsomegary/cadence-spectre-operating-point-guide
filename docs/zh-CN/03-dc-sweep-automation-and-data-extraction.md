# 第 3 章：DC Sweep Automation and Data Extraction

本章把 VCM/VID sweep 笔记整理成可公开、可重复使用的 Cadence Virtuoso、Spectre、
OCEAN workflow。原始笔记中的本机路径与项目名称已改成占位符。

## 1. 范围

本流程包含：

1. 在 schematic 参数化 `VCM` 与 `VID`
2. 用 OCEAN 跑 DC operating point、VCM sweep、VID sweep
3. 提取 swept device operating-point data
4. 检查 MOS `region` 与 saturation margin
5. 由 VID sweep 计算 1% DC linearity

示例条件：

```text
Circuit type:        five-transistor one-stage OTA
Supply:              VDD = 1.2 V
Nominal VCM:         0.8 V
Nominal VID:         0 V
Temperature:         27 deg C
Corner:              <process-corner>
```

这些只是示例，不是所有设计都必须采用的规格。

## 2. 目录结构

建议把 scripts 和 batch results 与 GUI ADE results 分开：

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

常用脚本：

```text
dcop.ocn
vcm_sweep.ocn
vid_sweep.ocn
inspect_vid_linearity.ocn
```

确认可用的脚本可用日期后缀保存：

```bash
cp -p vid_sweep.ocn vid_sweep.ocn.working_YYYYMMDD
```

## 3. 稳定的 GUI-to-Batch 流程

只有 schematic 层级信息改变时才需要回 Virtuoso：

1. Circuit topology 改变。
2. Device size 或 source property 在 schematic 中改变。
3. 新增 design variable。
4. Instance name 改变。
5. 为 STB analysis 加入或移除 `iprobe`。

建议流程：

1. 修改 schematic。
2. 执行 **Check and Save**。
3. 在 ADE 使用 **Variables -> Copy From Cellview**。
4. 确认所有 design variables 的 nominal values。
5. 使用 **Simulation -> Netlist -> Recreate**。
6. 若下一步要跑 OCEAN batch，不要在 ADE 点 **Run**。
7. 确认 Virtuoso 没有写入同一个 result directory。
8. 从 Linux shell 执行 OCEAN script。

Batch simulation 前：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

理想状态是没有输出。若有其他 Cadence process，请确认它使用不同 result directory。

## 4. 参数化 VCM 与 VID

Differential input pair 的两个 input source 建议使用同一组变量：

```text
Vin+ DC value: VCM + VID/2
Vin- DC value: VCM - VID/2
```

因此：

```text
VCM = (Vin+ + Vin-) / 2
VID = Vin+ - Vin-
```

改完 source property 后，执行 **Check and Save**、copy variables from cellview、
设置 nominal values，然后 recreate netlist。

检查 netlist：

```bash
grep -nE '^parameters|V[0-9]+.*vsource' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

预期形式：

```text
parameters VCM=<nominal-vcm> VID=0
V0 (...) vsource dc=VCM+VID/2 ...
V1 (...) vsource dc=VCM-VID/2 ...
```

## 5. DC OP 与 DC Sweep

单点 operating point：

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

`saveOpPoint()` 只指定要保存哪些 device OP quantities；它不会自己建立 DC analysis。

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

执行与验证：

```bash
ocean -nograph -restore vcm_sweep.ocn 2>&1 | tee vcm_sweep_run.log
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|Segmentation' vcm_sweep_run.log
awk 'NF==12 {n++} END {print "VCM_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/vcm_devices_raw.txt
```

0 V 到 1.2 V、step 10 mV 时，预期是 `121` 个数据点。

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

其他 `saveOpPoint()` 和 `ocnPrint()` 可沿用 VCM sweep pattern，输出到：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/vid_devices_raw.txt
```

-50 mV 到 +50 mV、step 100 uV 时，预期是 `1001` 个数据点。

## 8. Swept Device Data 的正确抓法

单点 DC OP：

```lisp
selectResult('dcOpInfo)
pv("/NM0" "ids")
```

Swept DC data：

```lisp
selectResult('dc)
getData("NM0:ids")
```

原始 IC618 环境中的关键差异：

```text
Correct for swept device OP: getData("NM0:ids")
Wrong in that environment:   getData("/NM0:ids")
```

Node voltage 仍使用：

```lisp
v("/vout")
```

如果 `outputs()` 看得到 `/NM0:ids`，但 `getData("/NM0:ids")` 返回 `nil`，请测试
`getData("NM0:ids")`。

## 9. Raw TXT 字段对应

输出 `vout` 加五颗 device 的 `ids`、`region` 时，每行有 12 列：

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

找出五颗 MOS 都回报 `region = 2` 的行：

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

这不等于 1% linear input range。

## 10. Saturation Margin

用 `vds` 和 `vdsat` 交叉确认 `region`：

```text
SAT_MARGIN = abs(VDS) - abs(VDSAT)
```

判读：

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

限制元件会随 topology 与 bias point 改变，每个设计都要重新确认。

## 11. 计算前先输出 Scientific Notation

Raw `ocnPrint()` 可能有 `100u`、`1m`、`69.6u` 这类 suffix。一般 AWK 不会自动把它们
转成浮点数。

计算 gain 或 percentage error 前，先输出 scientific notation：

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

原始流程使用“相对于零点小信号斜率的 secant-gain error”：

```text
A0 = [VOUT(+100 uV) - VOUT(-100 uV)] / 200 uV
Gsec(VID) = [VOUT(VID) - VOUT(0)] / VID
error_percent = 100 * abs[Gsec(VID)/A0 - 1]
```

判断：

```text
error_percent <= 1: pass
error_percent > 1: fail
```

`VID = 0` 时分母为零，必须跳过。这是 DC transfer linearity，不是 THD、AC response
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

两者不同。MOS 还在 saturation，不代表 OTA transfer curve 仍符合 1% linearity。

## 13. 最小验证清单

信任 sweep 前请检查：

1. 没有非预期 Cadence process 使用同一个 result directory。
2. OCEAN log 没有 `OCN-`、`ERROR`、`FATAL`、`SYNTAX`、`Segmentation`。
3. Sweep data point 数量正确。
4. `VID = 0` 时，对称 testbench 的 branch current 对称。
5. `region` boundary 有用 saturation margin 交叉确认。
6. 百分比计算使用 scientific notation。
7. 保存 dated known-good script checkpoint。
8. 保留 main script、final log 和 final data。

## 14. 重点整理

1. 在 schematic 一次性参数化 `VCM` 与 `VID`，之后用 OCEAN sweep。
2. 单点 `dcOpInfo` 用 `pv()`；swept device waveform 用 `getData()`。
3. `region = 2` 范围和 1% linear input range 是不同规格。
4. 上传公开文件前，请清掉 username、private path、PDK name、VM IP 与未公开 project name。
