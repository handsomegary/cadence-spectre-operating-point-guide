# 第 1 章：DC Operating-Point Simulation and Automation

本章說明 Cadence Virtuoso ADE L 搭配 Spectre 的基本 DC operating point，也就是 DCOP
流程。先處理「不做 sweep，只求 nominal operating point」的情況，再說明如何用共用
`opdump.scs` 自動輸出文字版 `oppoint.lis`。

## 1. DCOP 是什麼

DC operating-point simulation 是在一組固定 bias condition 下求解電路。它可以回答：

- 哪些 MOS 在 on、off、triode、saturation 或 subthreshold？
- 在目前 bias 下，`id`、`gm`、`gds`、`vgs`、`vds`、`vdsat` 是多少？
- 在做 AC、STB、transient 之前，nominal bias point 是否合理？

請先分清楚：

```text
Pure DC operating point: 一個 bias point，不掃任何變數。
DC sweep: 掃 VCM、VID、VOUT_TEST、VDD 等變數，得到一條曲線。
```

一開始先做 pure DCOP。之後要做 ICMR、output swing、input linearity 時，再改成 DC sweep。

## 2. 準備 Testbench

公開筆記請使用占位字：

```text
Project:            <project-name>
Library:            <library-name>
Cell:               <cell-name>
Supply:             VDD = <supply-voltage>
Common-mode input:  VCM = <nominal-common-mode-voltage>
Simulation root:    /home/<linux-user>/simulation/<project-name>
Shared OP file:     /home/<linux-user>/eda/config/opdump.scs
```

對 differential amplifier 或 OTA 的 nominal DCOP：

```text
Vin+ DC = VCM
Vin- DC = VCM
```

對 single-ended 或其他 biased block，請把每個 independent source 設成你想檢查的 nominal
DC value。

## 3. 在 ADE L 執行 Pure DC Operating Point

在 ADE L：

1. 打開 **Analyses -> Choose**。
2. 保持選中 **`dc`**。
3. 勾選 **`Save DC Operating Point`**。
4. 下面的 **Sweep Variable** 區塊全部不要勾。
5. 按 **OK**。
6. 回 ADE L 按 **Run**。

最重要的 no-sweep 設定就是：

```text
dc selected
Save DC Operating Point checked
Sweep Variable unchecked
```

如果 Sweep Variable 被勾起來，ADE 會做 DC sweep，而不是只求 nominal operating point。

## 4. 儲存常用 OP Parameters

若想讓重要 device values 更容易畫圖或查看：

```text
Outputs -> To Be Saved -> Select OP Parameters
```

MOS 建議儲存：

```text
id
gm
gds
vgs
vds
vdsat
region
```

判斷飽和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

裕量大於 0 表示有 saturation headroom；越接近 0，越靠近 triode boundary。

## 5. 用 `opdump.scs` 自動輸出文字報告

建立共用 Spectre definition file：

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

內容使用：

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

repo 內也有範本：

```text
templates/opdump.scs
```

在 ADE L 加入共用檔：

1. 打開 **Setup -> Simulation Files**。
2. 在 **Definition Files** 加入：

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

3. 按 **OK**。
4. 再跑一次 DC operating point。

不要把長期設定直接寫進 ADE 自動產生的 `input.scs`。請從 ADE 加入 definition file，這樣重新
netlist 後設定才會保留。

## 6. 驗證自動化是否成功

檢查 netlist 是否 include 共用檔：

```bash
grep -n "opdump.scs" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

應看到：

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

檢查 Spectre log：

```bash
tail -n 80 \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

成功時通常會看到：

```text
DC Analysis `dcOp'
Convergence achieved
opDump: writing operating point information to file `../psf/oppoint.lis'.
```

尋找報告：

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

## 7. 閱讀結果

在 Virtuoso：

```text
Results -> Print -> DC Operating Point
Results -> Annotate -> DC Operating Points
```

在 MobaXterm：

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

快速篩選：

```bash
grep -nE 'region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

## 8. 什麼時候才改用 DC Sweep

只有真的要看曲線時才開 DC sweep：

```text
ICMR:               sweep VCM
Output swing:       sweep VOUT_TEST
Input linearity:    sweep VID
Supply sensitivity: sweep VDD
Bias sensitivity:   sweep a bias voltage or current
```

這些情況才勾選正確 sweep variable，並設定 start、stop、step。Nominal DCOP 時，Sweep
Variable 請保持全部不勾。

## 9. 常見錯誤

- 只是要 nominal DCOP，卻不小心勾了 Sweep Variable。
- 加入 `opdump.scs` 後忘記重新 Run。
- 直接修改 `input.scs`，下一次 netlist 後設定消失。
- 把 `oppoint.lis` 當程式執行，而不是用 `less`、`more`、`grep`、`nano` 或 `vi` 打開。
- 把真實 Linux home path、私人 PDK 名稱、IP、library name 或未公開 cell name 放進公開 repo。

## 10. DCOP Checklist

設定正確時應符合：

1. ADE L 選中 `dc`。
2. `Save DC Operating Point` 已勾選。
3. Nominal DCOP 時，沒有任何 Sweep Variable 被勾選。
4. Testbench source 使用正確 DC bias。
5. 若使用文字輸出，`input.scs` 有 include 共用 `opdump.scs`。
6. `spectre.out` 顯示 convergence。
7. 若啟用 `opDump`，`oppoint.lis` 已產生。
8. MOS OP data 中可看到 model 提供的 `id`、`gm`、`gds`、`vgs`、`vds`、`vdsat`、`region`。
