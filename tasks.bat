@echo off
REM ============================================================
REM  Brainrot RPG — Automated Build Tasks
REM  Uses opencode serve + run --attach (avoids v1.16.0 run bug).
REM  --dangerously-skip-permissions allows unattended execution.
REM ============================================================

setlocal EnableDelayedExpansion

set OPENCODE=%USERPROFILE%\.opencode\bin\opencode.exe
set TASK_NUM=0
set TOTAL=7

REM Start headless server (stays alive for all tasks — no cold-boot)
echo Starting opencode server on port 4096...
start /b "" "%OPENCODE%" serve --port 4096 >nul 2>&1
timeout /t 4 /nobreak >nul
echo Server ready.
echo.

call :run_task "TASK 1/7 - ShopService.lua: Create ServerScriptService/Services/ShopService.lua. NPC shop that sells items for coins. Generate rotating stock of items from ItemData weighted by rarity. Players spend coins to buy items directly (no player listing yet). Include BuyItem(player, listingIndex) and GetShopList(player) functions. Use existing Coins from Leaderboard.AddCoins (deduct via negative amount) for currency. Follow the same service pattern as LootService (ModuleScript required by Main, deferred saves, pcall DataStore ops). The shop should refresh stock every 5 minutes. Each listing has: id, templateName, name, slot, statType, stat (rolled), rarity, icon, price (coins, based on rarity tier * stat value)."

call :run_task "TASK 2/7 - Update RemotesInit.server.lua: In src/ServerScriptService/Core/RemotesInit.server.lua, add these to the EVENTS table: BuyShopItem (Client to Server, listingIndex number), ShopStockUpdated (Server to Client, shopList table), SellItem (Client to Server, itemId string). Add to FUNCTIONS table: GetShopStock (returns shop list). Keep ALL existing remotes intact. Do not remove or reorder anything."

call :run_task "TASK 3/7 - Update Main.server.lua: In src/ServerScriptService/Core/Main.server.lua, add ShopService require after LootService (after line 27). Add a comment '-- 6.5. Shop depends on Loot + Leaderboard (coins)'. Use the same require pattern: local ShopService = require(script.Parent.Parent.Services.ShopService). Do not change any existing requires or the boot order."

call :run_task "TASK 4/7 - ShopClient.lua: Create src/StarterPlayer/StarterPlayerScripts/ShopClient.lua as a LocalScript. It should: (1) Get remotes via WaitForChild: BuyShopItem, ShopStockUpdated, SellItem, GetShopStock. (2) On character added, call GetShopStock to get initial stock. (3) Listen to ShopStockUpdated for stock refreshes. (4) Provide openShop()/closeShop() functions that toggle a ShopGui panel. (5) When buy button clicked, fire BuyShopItem with listing index. (6) Use same patterns as InventoryController.client.lua: WaitForChild for remotes, rarity color table, placeholder icon rbxassetid://101140058690765."

call :run_task "TASK 5/7 - ShopGui: Create src/StarterGui/ShopGui/ShopGui.client.lua as a LocalScript that builds the shop UI programmatically (like InventoryController does). Create a ScreenGui named ShopGui with: (1) Main Frame centered, dark background (Color3.fromRGB(18,18,28)), UICorner radius 8, UIStroke. (2) Title TextLabel 'Shop' at top. (3) ScrollingFrame with UIGridLayout for shop items. (4) Each item slot: Frame with ItemIcon (ImageLabel), ItemName (TextLabel), PriceLabel showing coin icon + price, BuyButton (TextButton). (5) UIStroke colored by rarity. (6) Close button in top-right. (7) Style must match existing inventory UI aesthetic."

call :run_task "TASK 6/7 - Cleanup: Delete these superseded/junk files using Remove-Item: (1) src/ReplicatedStorage/Remotes/RemoteInit.server.lua - superseded by SSS/Core/RemotesInit.server.lua. (2) src/StarterPlayer/StarterPlayerScripts/MovementController.client.lua - canonical copy is MovementController.lua. (3) src/StarterPlayer/StarterCharacterScripts/IsoCamera.lua - correct copy is in StarterPlayerScripts. (4) src/StarterPlayer/StarterCharacterScripts/test.txt - junk file. Also remove empty StarterCharacterScripts folder if it becomes empty."

call :run_task "TASK 7/7 - Update default.project.json: In the root default.project.json, add a ShopGui entry under StarterGui alongside LoadingGui. The StarterGui section should look like: 'StarterGui': { 'LoadingGui': { '$path': 'src/StarterGui/LoadingGui' }, 'ShopGui': { '$path': 'src/StarterGui/ShopGui' } }. Verify the JSON is valid after editing."

echo.
echo ============================================================
echo  ALL %TOTAL% TASKS COMPLETED
echo ============================================================

REM Kill the background server
taskkill /f /im opencode.exe >nul 2>&1

pause
exit /b 0

:run_task
set /a TASK_NUM+=1
echo.
echo ============================================================
echo  [%TASK_NUM%/%TOTAL%] Starting task...
echo ============================================================
echo.

"%OPENCODE%" run --attach http://localhost:4096 %1 --dangerously-skip-permissions

if %ERRORLEVEL% NEQ 0 (
    echo [WARN] Task %TASK_NUM% exited with code %ERRORLEVEL% - continuing...
) else (
    echo [OK] Task %TASK_NUM% completed.
)
echo.
goto :eof
