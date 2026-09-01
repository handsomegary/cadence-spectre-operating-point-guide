# 第 5 章：Schematic DC OP Annotation

本文说明如何把 MOS 的 DC operating-point 参数，例如 `region`、`gm`、
`vgs`、`vds`、`vdsat`，直接标示在 Cadence Virtuoso schematic 上，并保存
annotation 设置以便下次重用。

这和生成 `oppoint.lis` 有关，但不是同一件事。即使 schematic 没有显示所有字段，
`.lis` 报告里仍可能已经有完整 operating-point 数据。

## 1. 通用环境占位符

公开文档请使用占位符：

```text
Cadence Virtuoso:        <virtuoso-version>
Simulator:               Spectre <spectre-version>
Process/PDK:             <process-pdk>
Library:                 <library-name>
Cell:                    <cell-name>
ADE simulation root:     /home/<linux-user>/simulation/<project-name>
Shared OP file:          /home/<linux-user>/eda/config/opdump.scs
Annotation setup file:   /home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as
```

不要公开真实 username、私人 PDK 路径、VM IP、客户名称或尚未公开的电路名称。

## 2. 为什么 `region` 会不见

`region` 从 schematic 上消失，不一定代表 Spectre 没有算出来。常见原因包括：

- Annotation Setup 回到默认显示列表。
- MOS symbol 可显示的 `cdsParam` 标签数量有限。
- 只加载 ADE saved state，没有加载 schematic annotation setup。

如果 `id`、`vgs`、`vds`、`gm`、`vdsat` 等数值已经能显示，通常代表 DC
operating-point 数据存在，只是显示位置被其他参数占用了。

## 3. 重新加载 DC Operating-Point 结果

先在 ADE L 窗口操作：

1. 确认已选择 DC analysis。
2. Run simulation，并确认收敛。
3. 选择 **Results -> Annotate -> DC Operating Points**。
4. 回到 schematic 窗口。

这一步会让 Virtuoso 知道最新 operating-point data 的位置，以及有哪些参数可用。

## 4. 在 NMOS 上加入 `region`

在 schematic 窗口：

1. 打开 **View -> Annotations -> Setup**。
2. 点击任意一颗 NMOS。
3. 将 **Instance Name** 设置成：

   ```text
   *
   ```

4. 确认 **Display Mode** 是：

   ```text
   DC Operating Point
   ```

5. 将其中一个可见的 `cdsParam` 字段改成：

   ```text
   region
   ```

6. 点击 **Apply**。

`*` 代表套用到同类型 device，而不是只套用到刚刚点击的那颗。

## 5. PMOS 要分开设置

NMOS 和 PMOS 是不同元件类型。完成 NMOS 后，请对 PMOS 再做一次：

1. 点击任意一颗 PMOS。
2. 将 **Instance Name** 设置成 `*`。
3. 确认 **Display Mode = DC Operating Point**。
4. 将其中一个显示字段改成 `region`。
5. 点击 **Apply**。

如果只设置 NMOS，PMOS 可能仍然不会显示 `region`；反之亦然。

## 6. 选择要显示的字段

有些 MOS symbol 能直接显示的 OP 字段有限。如果只方便显示五项，请按目的取舍。

偏重饱和区判断：

```text
vgs
vds
vdsat
gm
region
```

偏重偏置电流与小信号参数：

```text
id
vds
vdsat
gm
region
```

其他放不下的字段可以到 `oppoint.lis` 查看。不要只是为了多显示字段就修改 foundry PDK
symbol 或 Base CDF。

## 7. 找不到 `region` 或字段呈灰色

依次检查：

1. 回到 ADE L 重新 Run DC simulation。
2. 再选一次 **Results -> Annotate -> DC Operating Points**。
3. 打开 **View -> Annotations -> Setup**。
4. 确认 **Simulation Data Directory** 不是空白。
5. 确认 **Display Mode** 是 `DC Operating Point`，不是 `Component Parameter`。

也可以在 MobaXterm 检查 `oppoint.lis` 是否包含 `region`：

```bash
grep -n "region" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | head
```

如果 `oppoint.lis` 有 `region`，问题通常在 schematic 显示设置。如果 `oppoint.lis`
不存在或内容不完整，才需要检查 model、PDK CDF 或 operating-point save 设置。

## 8. 保存 Annotation Setup

ADE saved state 和 schematic annotation setup 不一定是同一份设置，因此建议另外保存。

在 **View -> Annotations -> Setup**：

1. 点击 **Save**。
2. 选择 **Save at Absolute Path**。
3. 保存到：

   ```text
   /home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as
   ```

下次使用：

1. Run DC simulation。
2. 选择 **Results -> Annotate -> DC Operating Points**。
3. 打开 **View -> Annotations -> Setup**。
4. 选择 **Load -> Load from Absolute Path**。
5. 加载 `.as` 文件。

如果 GUI 里没有 Save/Load 按钮，也可以在 CIW 使用 SKILL 指令。执行时 schematic 窗口要是当前作用中窗口：

```lisp
annSaveAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

```lisp
annLoadAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

## 9. 判读 `region`

许多 BSIM 类 model report 常见对应如下：

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

正式设计仍应以你的 PDK/model 文档为准。

不要只看 `region`。也要检查饱和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

裕量大于零代表有饱和裕量；越接近零，代表越接近 triode 边界。

## 10. 最短恢复流程

如果 `region` 又不见：

```text
ADE L: Run
ADE L: Results -> Annotate -> DC Operating Points
Schematic: View -> Annotations -> Setup
Annotation Setup: Load -> Load from Absolute Path
Select dc_op_region.as
```

如果还没有 `.as` 文件：

```text
Click NMOS -> Instance Name = * -> set one field to region -> Apply
Click PMOS -> Instance Name = * -> set one field to region -> Apply
Save at Absolute Path
```
