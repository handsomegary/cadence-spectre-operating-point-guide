# 第 1 章：DC Operating-Point Simulation and Automation

本章说明 Cadence Virtuoso ADE L 搭配 Spectre 的基本 DC operating point，也就是 DCOP
流程。先处理“不做 sweep，只求 nominal operating point”的情况，再说明如何用共享
`opdump.scs` 自动输出文本版 `oppoint.lis`。

## 1. DCOP 是什么

DC operating-point simulation 是在一组固定 bias condition 下求解电路。它可以回答：

- 哪些 MOS 在 on、off、triode、saturation 或 subthreshold？
- 在目前 bias 下，`id`、`gm`、`gds`、`vgs`、`vds`、`vdsat` 是多少？
- 在做 AC、STB、transient 之前，nominal bias point 是否合理？

请先分清楚：

```text
Pure DC operating point: 一个 bias point，不扫任何变量。
DC sweep: 扫 VCM、VID、VOUT_TEST、VDD 等变量，得到一条曲线。
```

一开始先做 pure DCOP。之后要做 ICMR、output swing、input linearity 时，再改成 DC sweep。

## 2. 准备 Testbench

公开笔记请使用占位符：

```text
Project:            <project-name>
Library:            <library-name>
Cell:               <cell-name>
Supply:             VDD = <supply-voltage>
Common-mode input:  VCM = <nominal-common-mode-voltage>
Simulation root:    /home/<linux-user>/simulation/<project-name>
Shared OP file:     /home/<linux-user>/eda/config/opdump.scs
```

对 differential amplifier 或 OTA 的 nominal DCOP：

```text
Vin+ DC = VCM
Vin- DC = VCM
```

对 single-ended 或其他 biased block，请把每个 independent source 设置成你想检查的 nominal
DC value。

## 3. 在 ADE L 执行 Pure DC Operating Point

在 ADE L：

1. 打开 **Analyses -> Choose**。
2. 保持选中 **`dc`**。
3. 勾选 **`Save DC Operating Point`**。
4. 下面的 **Sweep Variable** 区块全部不要勾。
5. 按 **OK**。
6. 回 ADE L 按 **Run**。

最重要的 no-sweep 设置就是：

```text
dc selected
Save DC Operating Point checked
Sweep Variable unchecked
```

如果 Sweep Variable 被勾起来，ADE 会做 DC sweep，而不是只求 nominal operating point。

## 4. 保存常用 OP Parameters

若想让重要 device values 更容易画图或查看：

```text
Outputs -> To Be Saved -> Select OP Parameters
```

MOS 建议保存：

```text
id
gm
gds
vgs
vds
vdsat
region
```

判断饱和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

裕量大于 0 表示有 saturation headroom；越接近 0，越靠近 triode boundary。

## 5. 用 `opdump.scs` 自动输出文本报告

创建共享 Spectre definition file：

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

内容使用：

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

repo 内也有模板：

```text
templates/opdump.scs
```

在 ADE L 加入共享文件：

1. 打开 **Setup -> Simulation Files**。
2. 在 **Definition Files** 加入：

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

3. 按 **OK**。
4. 再跑一次 DC operating point。

不要把长期设置直接写进 ADE 自动生成的 `input.scs`。请从 ADE 加入 definition file，这样重新
netlist 后设置才会保留。

## 6. 验证自动化是否成功

检查 netlist 是否 include 共享文件：

```bash
grep -n "opdump.scs" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

应看到：

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

检查 Spectre log：

```bash
tail -n 80 \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

成功时通常会看到：

```text
DC Analysis `dcOp'
Convergence achieved
opDump: writing operating point information to file `../psf/oppoint.lis'.
```

寻找报告：

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

## 7. 阅读结果

在 Virtuoso：

```text
Results -> Print -> DC Operating Point
Results -> Annotate -> DC Operating Points
```

在 MobaXterm：

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

快速筛选：

```bash
grep -nE 'region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

## 8. 什么时候才改用 DC Sweep

只有真的要看曲线时才开 DC sweep：

```text
ICMR:               sweep VCM
Output swing:       sweep VOUT_TEST
Input linearity:    sweep VID
Supply sensitivity: sweep VDD
Bias sensitivity:   sweep a bias voltage or current
```

这些情况才勾选正确 sweep variable，并设置 start、stop、step。Nominal DCOP 时，Sweep
Variable 请保持全部不勾。

## 9. 常见错误

- 只是要 nominal DCOP，却不小心勾了 Sweep Variable。
- 加入 `opdump.scs` 后忘记重新 Run。
- 直接修改 `input.scs`，下一次 netlist 后设置消失。
- 把 `oppoint.lis` 当程序执行，而不是用 `less`、`more`、`grep`、`nano` 或 `vi` 打开。
- 把真实 Linux home path、私人 PDK 名称、IP、library name 或未公开 cell name 放进公开 repo。

## 10. DCOP Checklist

设置正确时应符合：

1. ADE L 选中 `dc`。
2. `Save DC Operating Point` 已勾选。
3. Nominal DCOP 时，没有任何 Sweep Variable 被勾选。
4. Testbench source 使用正确 DC bias。
5. 若使用文本输出，`input.scs` 有 include 共享 `opdump.scs`。
6. `spectre.out` 显示 convergence。
7. 若启用 `opDump`，`oppoint.lis` 已生成。
8. MOS OP data 中可看到 model 提供的 `id`、`gm`、`gds`、`vgs`、`vds`、`vdsat`、`region`。
