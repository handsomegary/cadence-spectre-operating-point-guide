# 第 2 章：导出与阅读 `oppoint.lis`

本 SOP 说明如何在 Cadence Virtuoso ADE 执行 Spectre DC operating point，并把
MOS 的工作点数据输出成可由 MobaXterm 阅读的 `oppoint.lis`。

若要先看 ADE L 里不做 sweep 的基本 DC operating-point 设置，请从
[第 1 章：DC Operating-Point Simulation and Automation](01-dc-operating-point-simulation.md) 开始。

本文中的 `oppoint.lis` 是 Spectre 生成的 ASCII operating-point 报告，不是
HSPICE 仿真器原生的 `.lis` 文件。

## 1. 使用通用占位路径

公开文档请使用占位符，不要放真实用户名、IP、项目名或 PDK 路径：

```text
Linux user:              <linux-user>
VM IP address:           <vm-ip-address>
PDK root:                /home/<linux-user>/eda/pdk/<process-pdk>
Shared OP file:          /home/<linux-user>/eda/config/opdump.scs
Cadence project folder:  /home/<linux-user>/cadence_projects/<project-name>
ADE simulation root:     /home/<linux-user>/simulation/<project-name>
Library / cell:          <library-name> / <cell-name>
Netlist:                 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
OP report:               /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

请把设计数据和仿真输出分开：

- `cadence_projects` 放 schematic、library 等设计数据。
- `simulation` 放 ADE/Spectre 生成的仿真结果。

## 2. 用 MobaXterm 连接到 VM

在 MobaXterm terminal 输入：

```bash
ssh <linux-user>@<vm-ip-address>
```

如果不确定 VM IP，可在 VM 里查询：

```bash
hostname -I
```

## 3. 创建共享 `opdump.scs`

这个文件只需要创建一次，之后不同 project 可以共用：

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

文件内容：

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

`nano` 保存方式：

1. `Ctrl+O`
2. 按 `Enter`
3. `Ctrl+X`

检查内容：

```bash
sed -n '1,10p' /home/<linux-user>/eda/config/opdump.scs
```

其中 `../psf/oppoint.lis` 是相对于该 cell 的 netlist 目录，因此不同 cell 通常会写到各自的
`psf` 文件夹，不会互相覆盖。

## 4. 创建新的 Cadence project 文件夹

示例：

```bash
mkdir -p /home/<linux-user>/cadence_projects/<project-name>
cd /home/<linux-user>/cadence_projects/<project-name>
nano cds.lib
```

`cds.lib` 示例内容：

```text
INCLUDE /home/<linux-user>/eda/pdk/<process-pdk>/cds.lib
```

请从 project 文件夹启动 Virtuoso：

```bash
cd /home/<linux-user>/cadence_projects/<project-name>
virtuoso &
```

每个 project 建议有自己的设计文件夹与 simulation 文件夹：

```text
/home/<linux-user>/cadence_projects/<project-name>
/home/<linux-user>/simulation/<project-name>
```

这样可以避免不同 project 或 cell 的仿真结果混在一起。

## 5. 在 ADE 加入 `opdump.scs`

1. 打开 schematic。
2. 选择 **Launch -> ADE L**。
3. 确认 simulator 是 **spectre**。
4. 进入 **Setup -> Simulator/Directory/Host**。
5. 将 **Project Directory** 设置为：

   ```text
   /home/<linux-user>/simulation/<project-name>
   ```

6. 进入 **Setup -> Simulation Files**。
7. 在 **Definition Files** 加入：

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

8. Analysis 设置为 **dc**。DC operating point 本身不需要 sweep。
9. 执行 simulation。

不要把长期修正做在 ADE 自动生成的 `input.scs` 里。应该回 ADE 或 schematic 修改，再重新
netlist。

## 6. 确认 `input.scs`

寻找最近生成的 Spectre netlist：

```bash
find /home/<linux-user> -type f -name "input.scs" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -10
```

检查当前 cell 的 netlist：

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

应看到类似：

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

如果没有这一行，通常代表 Definition Files 尚未正确加入，或加入后尚未重新 netlist / Run。

## 7. 执行 Spectre 并确认 `oppoint.lis`

在 ADE Run 完后，查看 Spectre log：

```bash
tail -n 50 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

成功时通常会看到：

```text
opDump: writing operating point information to file `../psf/oppoint.lis'.
DC Analysis `dcOp'
Convergence achieved
```

寻找所有 operating-point 报告：

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

报告通常位于：

```text
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

## 8. 在 MobaXterm 阅读 `oppoint.lis`

打开报告：

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

`less` 常用快捷键：

- `/NM2` 搜索 `NM2`
- `/region` 搜索 `region`
- `n` 下一个搜索结果
- `Shift+N` 上一个搜索结果
- `q` 退出

快速筛选 MOS 名称与参数：

```bash
grep -nE 'NM0|NM1|NM2|PM0|PM1|region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

不要直接把 `oppoint.lis` 当程序执行：

```bash
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

这会得到 `Permission denied`，因为 shell 以为你要执行文本文件。请使用 `less`、`more`、`nano`、
`grep` 或 `vi` 阅读。

## 9. 判断 MOS 是否在饱和区

许多 BSIM 类模型的 `region` 常见对应如下：

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

实际定义仍应以你的 PDK/model 文档为准。

不要只看 `region`，也要看饱和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

结果大于 0 代表有饱和裕量；越接近 0，代表越靠近 triode 边界。

建议检查：

- `region`: 模型判定的工作区
- `gm`: 跨导
- `gds`: 输出电导
- `id`: 漏极电流
- `vgs`: 栅源电压
- `vds`: 漏源电压
- `vdsat`: 模型计算的饱和所需电压
- `gm/id`: 评估反型程度与效率时可使用

`VGS` 只能帮助判断导通与偏置状态，不能单独证明 MOS 已进入饱和区；是否饱和还取决于 `VDS`
是否足够。

## 10. 在 Virtuoso GUI 内查看 DC Operating Point

仿真成功后，可使用：

```text
Results -> Print -> DC Operating Point
```

或把工作点标回 schematic：

```text
Results -> Annotate -> DC Operating Points
```

若要调整显示字段，可尝试：

```text
View -> Annotations -> Setup
```

GUI 适合快速查看；`oppoint.lis` 适合保存、搜索、比较与版本追踪。

若要专门设置 schematic 上的 MOS `region` 与 DC OP 字段，请看
[第 9 章：Schematic DC OP Annotation](09-schematic-op-annotation.md)。

## 11. 保存某一次仿真结果

进入该 cell 的 `psf` 文件夹：

```bash
cd /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf
```

按条件复制并重新命名：

```bash
cp oppoint.lis oppoint_tt_27C_VDD1p2.lis
```

文件名示例：

```text
oppoint_tt_27C_VDD1p2.lis
oppoint_ss_125C_VDD1p08.lis
oppoint_ff_m40C_VDD1p32.lis
```

## 12. 保存与重新加载 ADE State

在 ADE L 使用：

```text
Session -> Save State -> Cellview
```

state 名称示例：

```text
spectre_op_export
```

下次使用：

```text
Session -> Load State
```

如果重新打开窗口时名称出现 `(1)`、`(2)`、`(3)`，通常只是同一工作阶段重复打开窗口的编号，
不是新的设计版本。

## 13. 常见错误

### 找不到 `oppoint.lis`

先确认：

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
tail -n 80 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

如果 `input.scs` 有 include `opdump.scs`，且 log 显示 `opDump` 正在写文件，报告通常就在该 cell
的 `psf` 目录中。

### Undefined model 错误

例如 `undefined model <model-name>`，通常代表 Spectre 没有加载正确的 model library 或 model
section。

请检查 `input.scs` 是否指向正确 PDK model 文件，并确认 corner section，例如 `tt`、`ss` 或 `ff`。

### `CDS.log is already locked`

通常代表另一个 Virtuoso 还在执行，或上次异常结束留下 lock。

检查进程：

```bash
pgrep -af -u <linux-user> 'virtuoso|icfb|cdsMsgServer|libManager|libSelect'
```

检查 log：

```bash
ls -la /home/<linux-user>/CDS.log*
```

最安全的做法是先在原本 Virtuoso CIW 使用：

```text
File -> Exit
```

若已确认某个 process 是不要的旧 session：

```bash
kill -TERM <pid>
ps -o pid,ppid,stat,etime,cmd -p <pid>
```

只有在确认 process 必须结束且 `TERM` 无效时，才考虑 `kill -KILL <pid>`。

关闭 MobaXterm 窗口不一定会关闭后台执行的 Virtuoso。能从 CIW 正常 Exit 时，请先正常退出。

### 仿真成功但工作点异常

除了尺寸与偏置，也要检查连线：

- Diode-connected current mirror 的 gate 与 drain 应接在一起。
- Bulk terminal 应正确连接。
- VDD、input common-mode、tail current bias 与 output nodes 应符合设计。

请回 schematic 修正，然后 **Check and Save**、重新 netlist、重新 Run。

## 14. 新电路最短检查清单

1. 每个 project 创建独立设计文件夹与 simulation 文件夹。
2. 从 project 设计文件夹启动 `virtuoso &`。
3. 选择正确的 Spectre simulator、model library 和 corner。
4. 将 ADE Project Directory 设置为 project simulation 文件夹。
5. 在 Definition Files 加入共享 `opdump.scs`。
6. 执行 DC operating-point analysis。
7. 从 `spectre.out` 确认 convergence 与 `opDump` writing。
8. 找到 `oppoint.lis`。
9. 用 `less` 打开。
10. 检查 `region`、`gm`、`gds`、`id`、`vgs`、`vds`、`vdsat`。
11. 将重要结果复制成带条件名称的备份。
12. 保存 ADE state。

## 成功判断标准

流程成功时应同时符合：

1. `input.scs` 有 include 共享 `opdump.scs`。
2. `spectre.out` 显示 DC convergence。
3. `spectre.out` 显示 `opDump` 正在写入 `../psf/oppoint.lis`。
4. 对应 cell 的 `psf` 目录存在 `oppoint.lis`。
5. 使用 `less` 能看到 MOS 的 `gm`、`gds`、`vgs`、`vds`、`vdsat`、`region` 等数据。
