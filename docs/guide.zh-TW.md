# Spectre Operating-Point LIS SOP

本 SOP 說明如何在 Cadence Virtuoso ADE 執行 Spectre DC operating point，並把
MOS 的工作點資料輸出成可由 MobaXterm 閱讀的 `oppoint.lis`。

本文件中的 `oppoint.lis` 是 Spectre 產生的 ASCII operating-point 報告，不是
HSPICE 模擬器原生的 `.lis` 檔。

## 1. 使用通用占位路徑

公開文件請使用占位字，不要放真實使用者名稱、IP、專案名稱或 PDK 路徑：

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

請把設計資料和模擬輸出分開：

- `cadence_projects` 放 schematic、library 等設計資料。
- `simulation` 放 ADE/Spectre 產生的模擬結果。

## 2. 用 MobaXterm 連線到 VM

在 MobaXterm terminal 輸入：

```bash
ssh <linux-user>@<vm-ip-address>
```

如果不確定 VM IP，可在 VM 裡查：

```bash
hostname -I
```

## 3. 建立共用 `opdump.scs`

這個檔案只需要建立一次，之後不同 project 可以共用：

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

檔案內容：

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

`nano` 儲存方式：

1. `Ctrl+O`
2. 按 `Enter`
3. `Ctrl+X`

檢查內容：

```bash
sed -n '1,10p' /home/<linux-user>/eda/config/opdump.scs
```

其中 `../psf/oppoint.lis` 是相對於該 cell 的 netlist 目錄，因此不同 cell 通常會寫到各自的
`psf` 資料夾，不會互相覆蓋。

## 4. 建立新的 Cadence project 資料夾

範例：

```bash
mkdir -p /home/<linux-user>/cadence_projects/<project-name>
cd /home/<linux-user>/cadence_projects/<project-name>
nano cds.lib
```

`cds.lib` 範例內容：

```text
INCLUDE /home/<linux-user>/eda/pdk/<process-pdk>/cds.lib
```

請從 project 資料夾啟動 Virtuoso：

```bash
cd /home/<linux-user>/cadence_projects/<project-name>
virtuoso &
```

每個 project 建議有自己的設計資料夾與 simulation 資料夾：

```text
/home/<linux-user>/cadence_projects/<project-name>
/home/<linux-user>/simulation/<project-name>
```

這樣可以避免不同 project 或 cell 的模擬結果混在一起。

## 5. 在 ADE 加入 `opdump.scs`

1. 開啟 schematic。
2. 選擇 **Launch -> ADE L**。
3. 確認 simulator 是 **spectre**。
4. 進入 **Setup -> Simulator/Directory/Host**。
5. 將 **Project Directory** 設為：

   ```text
   /home/<linux-user>/simulation/<project-name>
   ```

6. 進入 **Setup -> Simulation Files**。
7. 在 **Definition Files** 加入：

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

8. Analysis 設定為 **dc**。DC operating point 本身不需要 sweep。
9. 執行 simulation。

不要把長期修正做在 ADE 自動產生的 `input.scs` 裡。應該回 ADE 或 schematic 修改，再重新
netlist。

## 6. 確認 `input.scs`

尋找最近產生的 Spectre netlist：

```bash
find /home/<linux-user> -type f -name "input.scs" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -10
```

檢查目前 cell 的 netlist：

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

應看到類似：

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

如果沒有這一行，通常代表 Definition Files 尚未正確加入，或加入後尚未重新 netlist / Run。

## 7. 執行 Spectre 並確認 `oppoint.lis`

在 ADE Run 完後，查看 Spectre log：

```bash
tail -n 50 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

成功時通常會看到：

```text
opDump: writing operating point information to file `../psf/oppoint.lis'.
DC Analysis `dcOp'
Convergence achieved
```

尋找所有 operating-point 報告：

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

報告通常位於：

```text
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

## 8. 在 MobaXterm 閱讀 `oppoint.lis`

開啟報告：

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

`less` 常用快捷鍵：

- `/NM2` 搜尋 `NM2`
- `/region` 搜尋 `region`
- `n` 下一個搜尋結果
- `Shift+N` 上一個搜尋結果
- `q` 離開

快速篩選 MOS 名稱與參數：

```bash
grep -nE 'NM0|NM1|NM2|PM0|PM1|region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

不要直接把 `oppoint.lis` 當程式執行：

```bash
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

這會得到 `Permission denied`，因為 shell 以為你要執行文字檔。請使用 `less`、`more`、`nano`、
`grep` 或 `vi` 閱讀。

## 9. 判斷 MOS 是否在飽和區

許多 BSIM 類模型的 `region` 常見對應如下：

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

實際定義仍應以你的 PDK/model 文件為準。

不要只看 `region`，也要看飽和裕量：

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

結果大於 0 代表有飽和裕量；越接近 0，代表越靠近 triode 邊界。

建議檢查：

- `region`: 模型判定的工作區
- `gm`: 跨導
- `gds`: 輸出電導
- `id`: 汲極電流
- `vgs`: 閘源電壓
- `vds`: 汲源電壓
- `vdsat`: 模型計算的飽和所需電壓
- `gm/id`: 評估反轉程度與效率時可使用

`VGS` 只能幫你判斷導通與偏壓狀態，不能單獨證明 MOS 已進入飽和區；是否飽和還取決於 `VDS`
是否足夠。

## 10. 在 Virtuoso GUI 內查看 DC Operating Point

模擬成功後，可使用：

```text
Results -> Print -> DC Operating Point
```

或把工作點標回 schematic：

```text
Results -> Annotate -> DC Operating Points
```

若要調整顯示欄位，可嘗試：

```text
View -> Annotations -> Setup
```

GUI 適合快速查看；`oppoint.lis` 適合保存、搜尋、比較與版本追蹤。

若要專門設定 schematic 上的 MOS `region` 與 DC OP 欄位，請看
[在 Virtuoso 顯示並保存 MOS region 與 DC OP 參數](annotate-region.zh-TW.md)。

## 11. 保存某一次模擬結果

進入該 cell 的 `psf` 資料夾：

```bash
cd /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf
```

依條件複製並重新命名：

```bash
cp oppoint.lis oppoint_tt_27C_VDD1p2.lis
```

檔名範例：

```text
oppoint_tt_27C_VDD1p2.lis
oppoint_ss_125C_VDD1p08.lis
oppoint_ff_m40C_VDD1p32.lis
```

## 12. 保存與重開 ADE State

在 ADE L 使用：

```text
Session -> Save State -> Cellview
```

state 名稱範例：

```text
spectre_op_export
```

下次使用：

```text
Session -> Load State
```

如果重新開啟視窗時名稱出現 `(1)`、`(2)`、`(3)`，通常只是同一工作階段重複開啟視窗的編號，
不是新的設計版本。

## 13. 常見錯誤

### 找不到 `oppoint.lis`

先確認：

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
tail -n 80 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

如果 `input.scs` 有 include `opdump.scs`，且 log 顯示 `opDump` 正在寫檔，報告通常就在該 cell
的 `psf` 目錄中。

### Undefined model 錯誤

例如 `undefined model <model-name>`，通常代表 Spectre 沒有載入正確的 model library 或 model
section。

請檢查 `input.scs` 是否指向正確 PDK model 檔，並確認 corner section，例如 `tt`、`ss` 或 `ff`。

### `CDS.log is already locked`

通常代表另一個 Virtuoso 還在執行，或上次異常結束留下 lock。

檢查程序：

```bash
pgrep -af -u <linux-user> 'virtuoso|icfb|cdsMsgServer|libManager|libSelect'
```

檢查 log：

```bash
ls -la /home/<linux-user>/CDS.log*
```

最安全的做法是先在原本 Virtuoso CIW 使用：

```text
File -> Exit
```

若已確認某個 process 是不要的舊 session：

```bash
kill -TERM <pid>
ps -o pid,ppid,stat,etime,cmd -p <pid>
```

只有在確認 process 必須結束且 `TERM` 無效時，才考慮 `kill -KILL <pid>`。

關閉 MobaXterm 視窗不一定會關閉背景執行的 Virtuoso。能從 CIW 正常 Exit 時，請先正常退出。

### 模擬成功但工作點異常

除了尺寸與偏壓，也要檢查接線：

- Diode-connected current mirror 的 gate 與 drain 應接在一起。
- Bulk terminal 應正確連接。
- VDD、input common-mode、tail current bias 與 output nodes 應符合設計。

請回 schematic 修正，然後 **Check and Save**、重新 netlist、重新 Run。

## 14. 新電路最短檢查清單

1. 每個 project 建立獨立設計資料夾與 simulation 資料夾。
2. 從 project 設計資料夾啟動 `virtuoso &`。
3. 選擇正確的 Spectre simulator、model library 和 corner。
4. 將 ADE Project Directory 設為 project simulation 資料夾。
5. 在 Definition Files 加入共用 `opdump.scs`。
6. 執行 DC operating-point analysis。
7. 從 `spectre.out` 確認 convergence 與 `opDump` writing。
8. 找到 `oppoint.lis`。
9. 用 `less` 開啟。
10. 檢查 `region`、`gm`、`gds`、`id`、`vgs`、`vds`、`vdsat`。
11. 將重要結果複製成帶條件名稱的備份。
12. 保存 ADE state。

## 成功判斷標準

流程成功時應同時符合：

1. `input.scs` 有 include 共用 `opdump.scs`。
2. `spectre.out` 顯示 DC convergence。
3. `spectre.out` 顯示 `opDump` 正在寫入 `../psf/oppoint.lis`。
4. 對應 cell 的 `psf` 目錄存在 `oppoint.lis`。
5. 使用 `less` 能看到 MOS 的 `gm`、`gds`、`vgs`、`vds`、`vdsat`、`region` 等資料。
