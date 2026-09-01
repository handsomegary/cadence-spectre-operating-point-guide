# 第 6 章：Schematic DC OP Annotation

本文件說明如何把 MOS 的 DC operating-point 參數，例如 `region`、`gm`、
`vgs`、`vds`、`vdsat`，直接標示在 Cadence Virtuoso schematic 上，並保存
annotation 設定以便下次重用。

這和產生 `oppoint.lis` 有關，但不是同一件事。即使 schematic 沒有顯示所有欄位，
`.lis` 報告裡仍可能已經有完整 operating-point 資料。

## 1. 通用環境占位字

公開文件請使用占位字：

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

不要公開真實 username、私人 PDK 路徑、VM IP、客戶名稱或尚未公開的電路名稱。

## 2. 為什麼 `region` 會不見

`region` 從 schematic 上消失，不一定代表 Spectre 沒有算出來。常見原因包括：

- Annotation Setup 回到預設顯示清單。
- MOS symbol 可顯示的 `cdsParam` 標籤數量有限。
- 只載入 ADE saved state，沒有載入 schematic annotation setup。

如果 `id`、`vgs`、`vds`、`gm`、`vdsat` 等數值已經能顯示，通常代表 DC
operating-point 資料存在，只是顯示位置被其他參數占用了。

## 3. 重新載入 DC Operating-Point 結果

先在 ADE L 視窗操作：

1. 確認已選擇 DC analysis。
2. Run simulation，並確認收斂。
3. 選擇 **Results -> Annotate -> DC Operating Points**。
4. 回到 schematic 視窗。

這一步會讓 Virtuoso 知道最新 operating-point data 的位置，以及有哪些參數可用。

## 4. 在 NMOS 上加入 `region`

在 schematic 視窗：

1. 開啟 **View -> Annotations -> Setup**。
2. 點選任意一顆 NMOS。
3. 將 **Instance Name** 設成：

   ```text
   *
   ```

4. 確認 **Display Mode** 是：

   ```text
   DC Operating Point
   ```

5. 將其中一個可見的 `cdsParam` 欄位改成：

   ```text
   region
   ```

6. 按 **Apply**。

`*` 代表套用到同類型 device，而不是只套用到剛剛點選的那顆。

## 5. PMOS 要分開設定

NMOS 和 PMOS 是不同元件類型。完成 NMOS 後，請對 PMOS 再做一次：

1. 點選任意一顆 PMOS。
2. 將 **Instance Name** 設成 `*`。
3. 確認 **Display Mode = DC Operating Point**。
4. 將其中一個顯示欄位改成 `region`。
5. 按 **Apply**。

如果只設定 NMOS，PMOS 可能仍然不會顯示 `region`；反之亦然。

## 6. 選擇要顯示的欄位

有些 MOS symbol 能直接顯示的 OP 欄位有限。如果只方便顯示五項，請依目的取捨。

偏重飽和區判斷：

```text
vgs
vds
vdsat
gm
region
```

偏重偏壓電流與小訊號參數：

```text
id
vds
vdsat
gm
region
```

其他放不下的欄位可以到 `oppoint.lis` 查看。不要只是為了多顯示欄位就修改 foundry PDK
symbol 或 Base CDF。

## 7. 找不到 `region` 或欄位呈灰色

依序檢查：

1. 回到 ADE L 重新 Run DC simulation。
2. 再選一次 **Results -> Annotate -> DC Operating Points**。
3. 開啟 **View -> Annotations -> Setup**。
4. 確認 **Simulation Data Directory** 不是空白。
5. 確認 **Display Mode** 是 `DC Operating Point`，不是 `Component Parameter`。

也可以在 MobaXterm 檢查 `oppoint.lis` 是否包含 `region`：

```bash
grep -n "region" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | head
```

如果 `oppoint.lis` 有 `region`，問題通常在 schematic 顯示設定。如果 `oppoint.lis`
不存在或內容不完整，才需要檢查 model、PDK CDF 或 operating-point save 設定。

## 8. 保存 Annotation Setup

ADE saved state 和 schematic annotation setup 不一定是同一份設定，因此建議另外保存。

在 **View -> Annotations -> Setup**：

1. 按 **Save**。
2. 選擇 **Save at Absolute Path**。
3. 儲存到：

   ```text
   /home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as
   ```

下次使用：

1. Run DC simulation。
2. 選擇 **Results -> Annotate -> DC Operating Points**。
3. 開啟 **View -> Annotations -> Setup**。
4. 選擇 **Load -> Load from Absolute Path**。
5. 載入 `.as` 檔。

如果 GUI 裡沒有 Save/Load 按鈕，也可以在 CIW 使用 SKILL 指令。執行時 schematic 視窗要是目前作用中視窗：

```lisp
annSaveAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

```lisp
annLoadAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

## 9. 判讀 `region`

許多 BSIM 類 model report 常見對應如下：

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

正式設計仍應以你的 PDK/model 文件為準。

不要只看 `region`。也要檢查飽和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

裕量大於零代表有飽和裕量；越接近零，代表越接近 triode 邊界。

## 10. 最短恢復流程

如果 `region` 又不見：

```text
ADE L: Run
ADE L: Results -> Annotate -> DC Operating Points
Schematic: View -> Annotations -> Setup
Annotation Setup: Load -> Load from Absolute Path
Select dc_op_region.as
```

如果還沒有 `.as` 檔：

```text
Click NMOS -> Instance Name = * -> set one field to region -> Apply
Click PMOS -> Instance Name = * -> set one field to region -> Apply
Save at Absolute Path
```
