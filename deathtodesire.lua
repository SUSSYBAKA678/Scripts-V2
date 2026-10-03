local ClientSources={
    Owner=[=====[
local RS=game:GetService("RunService")
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local StarterGui=game:GetService("StarterGui")
local SoundService=game:GetService("SoundService")
local TweenService=game:GetService("TweenService")

local LP=Players.LocalPlayer
local OwnerName="__OWNER__"
local SCID="__SCID__"
if type(OwnerName)~="string" or type(SCID)~="string" then
    warn("[MEFE MOBILE] Missing owner or session attributes; client not started")
    return
end
print("[MEFE OWNER CLIENT 01] Starting controller; owner: "..OwnerName.."; current: "..tostring(LP and LP.Name))
if not LP or LP.Name~=OwnerName then return end

local Remote=nil
local Puller=nil
local AttackRemote=nil
local RemoteSigsC={}
local AttackClientHandler=nil
local RebindingRemotes=false
local ReadyForCustomCamera=false
local GuiReadyForHandshake=false
local lastReadyRequest=0
local updateStartup=function(message) print("[MEFE MOBILE STATUS] "..message) end

local function clearRemoteSigs()
	for _,sig in pairs(RemoteSigsC) do
		pcall(function() sig:Disconnect() end)
	end
	table.clear(RemoteSigsC)
end

local function findRemotes()
    local lastWarning=os.clock()
    while script.Parent do
        local r=Shared:FindFirstChild(SCID.."_R")
		local p=Shared:FindFirstChild(SCID.."_P")
		local a=Shared:FindFirstChild(SCID.."_A")
        if r and p and a then return r,p,a end
        if os.clock()-lastWarning>10 then
            lastWarning=os.clock()
            warn("[MEFE MOBILE] Waiting for server remotes in ReplicatedStorage: "..SCID)
            updateStartup("WAITING FOR SERVER REMOTES...")
        end
        task.wait(.25)
    end
    return nil,nil,nil
end

local function bindRemotes()
	if RebindingRemotes then return end
	RebindingRemotes=true
	clearRemoteSigs()
    updateStartup("CONNECTING TO MT2 SERVER...")
    local r,p,a=findRemotes()
    if not r then RebindingRemotes=false return end
    Remote,Puller,AttackRemote=r,p,a
	table.insert(RemoteSigsC,a.OnClientEvent:Connect(function(...)
		if AttackClientHandler then
			AttackClientHandler(...)
		end
	end))
    updateStartup("SERVER CONNECTED — SYNCHRONIZING...")
    task.spawn(function()
        while script.Parent and AttackRemote==a and not GuiReadyForHandshake do
            task.wait(.12)
        end
        if script.Parent and AttackRemote==a and GuiReadyForHandshake then
            print("[MEFE MOBILE] Render-verified GUI; sending CLIENT_READY")
            a:FireServer("CLIENT_READY")
        end
    end)
    a:FireServer("AURA_SYNC")
	local lost=false
	local function onLost()
		if lost then return end
		lost=true
		Remote=nil
		Puller=nil
        AttackRemote=nil
        updateStartup("LOST SERVER CONNECTION — RETRYING...")
        RebindingRemotes=false
        task.defer(bindRemotes)
	end
	for _,rem in ipairs({r,p,a}) do
		table.insert(RemoteSigsC,rem.Destroying:Connect(onLost))
		table.insert(RemoteSigsC,rem.AncestryChanged:Connect(function()
			if not rem:IsDescendantOf(game) then
				onLost()
			end
		end))
	end
	RebindingRemotes=false
end

task.spawn(function()
	for i=1,40 do
		local ok=pcall(function()
			StarterGui:SetCore("SendNotification",{Title="MT2",Text="MT2 initialized.",Duration=4})
		end)
		if ok then break end
		task.wait(.2)
	end
end)

local Camera=workspace.CurrentCamera
while not Camera do
    workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
    Camera=workspace.CurrentCamera
end
print("[MEFE MOBILE] Reusing Roblox CurrentCamera; starting viewport: "..tostring(Camera.ViewportSize))

local CharPos=Vector3.new(0,9,0)
local Yaw=0
local Pitch=0
local Zoom=14
local LerpZoom=14
local SPEED=.92
local FlyMode=true
local CameraFollow=CharPos+Vector3.new(0,1.5,0)
local lastClock=os.clock()
local cameraDragging=false
local lastMouseBehavior=Enum.MouseBehavior.Default
local touchCamera=nil
local lastTouch=nil
local worldTouch=nil
local gamepadMove=Vector2.zero
local gamepadLook=Vector2.zero
local activeGamepad=Enum.UserInputType.Gamepad1
local gamepadNeutralUntil=0
local blackholeShake=nil
local projectionDash=nil
local killMode=true
local beamActive=false
local auraEnabled=true
local mode=1
local uiButtons={}
local preferred=UIS.PreferredInput
local screen=Instance.new("ScreenGui")
screen.Name="MT2Controls"
screen.ResetOnSpawn=false
screen.IgnoreGuiInset=true
screen.DisplayOrder=1000
screen.ZIndexBehavior=Enum.ZIndexBehavior.Global
screen.Enabled=true
local playerGui=LP:WaitForChild("PlayerGui")
local previousGui=playerGui:FindFirstChild("MT2Controls")
if previousGui then previousGui:Destroy() end
screen.Parent=playerGui
print("[MEFE MOBILE] Controls GUI created for "..LP.Name)
local statusLabel=Instance.new("TextLabel")
statusLabel.Name="MT2ClientStatus"
statusLabel.AnchorPoint=Vector2.new(.5,0)
statusLabel.Position=UDim2.fromScale(.5,.145)
statusLabel.Size=UDim2.new(.72,0,0,28)
statusLabel.BackgroundTransparency=.35
statusLabel.BackgroundColor3=Color3.fromRGB(18,20,32)
statusLabel.TextColor3=Color3.fromRGB(255,245,190)
statusLabel.Font=Enum.Font.Code
statusLabel.TextScaled=true
statusLabel.Text="MT2 GUI READY — CONNECTING..."
statusLabel.Parent=screen
updateStartup=function(message)
    if statusLabel.Parent then
        statusLabel.Text="MT2: "..message
        statusLabel.Visible=true
    end
    print("[MEFE MOBILE STATUS] "..message)
end

local modeLabel=Instance.new("TextLabel")
modeLabel.Name="Mode"
modeLabel.AnchorPoint=Vector2.new(.5,0)
modeLabel.Position=UDim2.fromScale(.5,.025)
modeLabel.Size=UDim2.fromOffset(520,44)
modeLabel.BackgroundTransparency=1
modeLabel.TextScaled=true
modeLabel.Font=Enum.Font.Code
modeLabel.TextStrokeTransparency=.25
modeLabel.TextColor3=Color3.new(1,1,1)
modeLabel.Text="MODE 1 // CRIMSON FURY"
modeLabel.Parent=screen

local activeSubmode=false
local secretUnlocked=false
local SUBMODE_TRACKS={
    [1]={Name="ORDER // BLOODTHRONE",Id="112004584817838"},
    [2]={Name="ANTARCTIC REINFORCEMENT // AURORA NOCTURNE",Id="90558938526868"},
    [3]={Name="PANIC BETRAYER // FRACTAL ENGINE",Id="98193243315935"},
    [4]={Name="DANSE MACABRE // BROKEN AXIS",Id="97749541994489"},
    [5]={Name="WAR // PRISM VELOCITY",Id="85895048925934"},
    [6]={Name="UNHOLY INSURGENCY // MARTYR ASCENSION",Id="136518371432697"},
    [7]={Name="NO DEVIL LIVED ON // SINGULAR APOCALYPSE",Id="92019617611841"},
    [8]={Name="REQUIEM // VOID CHOIR",Id="90675953509731"},
    [9]={Name="BACTERIOPHAGE",Id="140550104885102"}
}
local MODE_TRACKS={
    [1]={Name="ALTARS OF APOSTASY",Id="78299681330541"},
    [2]={Name="DEEP BLUE",Id="73150190270807"},
    [3]={Name="THE CYBER GRIND",Id="125545844251648"},
    [4]={Name="SPIRAL OUT (KEEP GOING)",Id="132611192366030"},
    [5]={Name="THE WORLD LOOKS WHITE",Id="78139479686981"},
    [6]={Name="THE DEATH OF GOD'S WILL",Id="108695761500795"},
    [7]={Name="EVENT HORIZON (REACH FOR THE SUN AND BURN! BURN! BURN!)",Id="95074079827457"},
    [8]={Name="IN ABSENTIA",Id="76325881928922"}
}
for _,existing in ipairs(SoundService:GetChildren()) do
    if existing:IsA("Sound") and string.sub(existing.Name,1,15)=="MEFE_ModeTrack_" then
        existing:Stop()
        existing:Destroy()
    end
end
local MusicEnabled=true
local CurrentMusic=nil
local MusicMode=0
local MusicSubmode=nil
local MusicGeneration=0
local MusicVolume=.52
local MusicUI=Instance.new("TextButton")
MusicUI.Name="MEFE_MusicToggle"
MusicUI.Size=UDim2.fromOffset(335,30)
MusicUI.Position=UDim2.fromOffset(12,62)
MusicUI.BackgroundColor3=Color3.fromRGB(12,16,26)
MusicUI.BackgroundTransparency=.17
MusicUI.BorderSizePixel=0
MusicUI.TextColor3=Color3.fromRGB(200,235,255)
MusicUI.TextStrokeTransparency=.6
MusicUI.Font=Enum.Font.Code
MusicUI.TextScaled=true
MusicUI.Text="MUSIC: STARTING"
MusicUI.Parent=screen
local function updateMusicUI()
    local entry=(activeSubmode or mode==9) and SUBMODE_TRACKS[mode] or MODE_TRACKS[mode] or MODE_TRACKS[1]
    MusicUI.Text=MusicEnabled and ("♪ "..entry.Name.." [T]") or "MUSIC OFF [T]"
    MusicUI.TextColor3=MusicEnabled and Color3.fromRGB(196,233,255) or Color3.fromRGB(143,150,163)
end
local function fadeAndDispose(sound)
    if not sound then return end
    pcall(function()
        TweenService:Create(sound,TweenInfo.new(.64,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Volume=0}):Play()
    end)
    task.delay(.73,function() if sound.Parent then sound:Stop() sound:Destroy() end end)
end
local function playModeMusic(which)
    which=math.floor(tonumber(which) or 1)
    local entry=(activeSubmode or which==9) and SUBMODE_TRACKS[which] or MODE_TRACKS[which] or MODE_TRACKS[1]
    if which==MusicMode and MusicSubmode==activeSubmode and CurrentMusic and CurrentMusic.Parent and MusicEnabled then
        updateMusicUI()
        return
    end
    MusicGeneration=MusicGeneration+1
    local generation=MusicGeneration
    local previous=CurrentMusic
    CurrentMusic=nil
    MusicMode=which
    MusicSubmode=activeSubmode
    if previous then fadeAndDispose(previous) end
    updateMusicUI()
    if not MusicEnabled then return end
    local sound=Instance.new("Sound")
    sound.Name="MEFE_ModeTrack_"..SCID
    sound.SoundId="rbxassetid://"..entry.Id
    sound.Volume=0
    sound.Looped=true
    sound.PlaybackSpeed=1
    sound.Parent=SoundService
    CurrentMusic=sound
    sound:Play()
    TweenService:Create(sound,TweenInfo.new(1.05,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Volume=MusicVolume}):Play()
    task.delay(13,function()
        if generation==MusicGeneration and sound==CurrentMusic and sound.Parent and not sound.IsLoaded then
            warn("MEFE soundtrack could not load. Check Roblox audio permissions: "..entry.Name.." ("..entry.Id..")")
        end
    end)
end
local function toggleMusic()
    MusicEnabled=not MusicEnabled
    if MusicEnabled then
        MusicMode=0
        playModeMusic(mode)
    else
        MusicGeneration=MusicGeneration+1
        fadeAndDispose(CurrentMusic)
        CurrentMusic=nil
        updateMusicUI()
    end
end
MusicUI.Activated:Connect(toggleMusic)
playModeMusic(1)

local hint=Instance.new("TextLabel")
hint.AnchorPoint=Vector2.new(.5,1)
hint.Position=UDim2.fromScale(.5,.985)
hint.Size=UDim2.fromOffset(620,28)
hint.BackgroundTransparency=1
hint.TextScaled=true
hint.Font=Enum.Font.Code
hint.TextStrokeTransparency=.5
hint.TextColor3=Color3.fromRGB(220,220,220)
hint.Parent=screen

local cross=Instance.new("Frame")
cross.AnchorPoint=Vector2.new(.5,.5)
cross.Position=UDim2.fromScale(.5,.5)
cross.Size=UDim2.fromOffset(18,18)
cross.BackgroundTransparency=1
cross.Parent=screen
local ch=Instance.new("Frame")
ch.AnchorPoint=Vector2.new(.5,.5)
ch.Position=UDim2.fromScale(.5,.5)
ch.Size=UDim2.fromOffset(18,2)
ch.BorderSizePixel=0
ch.BackgroundColor3=Color3.new(1,1,1)
ch.Parent=cross
local cv=Instance.new("Frame")
cv.AnchorPoint=Vector2.new(.5,.5)
cv.Position=UDim2.fromScale(.5,.5)
cv.Size=UDim2.fromOffset(2,18)
cv.BorderSizePixel=0
cv.BackgroundColor3=Color3.new(1,1,1)
cv.Parent=cross

local mobile=Instance.new("Frame")
mobile.Name="Mobile"
mobile.Size=UDim2.fromScale(1,1)
mobile.BackgroundTransparency=1
mobile.Parent=screen

local function makeButton(id,text)
	local b=Instance.new("TextButton")
	b.Name=id
	b.AnchorPoint=Vector2.new(.5,.5)
	b.BackgroundColor3=Color3.fromRGB(15,15,20)
	b.BackgroundTransparency=.18
	b.BorderSizePixel=0
	b.AutoButtonColor=true
	b.Font=Enum.Font.Code
	b.TextScaled=true
	b.TextColor3=Color3.new(1,1,1)
	b.TextStrokeTransparency=.55
	b.Text=text
	b.Visible=UIS.TouchEnabled
	b.Parent=mobile
	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(.22,0)
	corner.Parent=b
	local stroke=Instance.new("UIStroke")
	stroke.Thickness=1.5
	stroke.Transparency=.25
	stroke.Color=Color3.fromRGB(235,235,255)
	stroke.Parent=b
	uiButtons[id]=b
	return b
end

local bMode=makeButton("MODE","MODE")
local bZ=makeButton("Z","Z")
local bX=makeButton("X","X")
local bC=makeButton("C","C")
local bV=makeButton("V","V")
local bF=makeButton("F","F")
local bG=makeButton("G","SUPER")
local bGlass=makeButton("GLASS","GLASS CANNON")
bGlass.Visible=false
local bSpecial=makeButton("SPECIAL","R FRAME")
bSpecial.Visible=false
local bB=makeButton("B","BOLT")
local bN=makeButton("N","SHATTER")
local bM=makeButton("M","FINISH")
local bAura=makeButton("AURA","AURA ON")
local bKill=makeButton("KILL","HUMANOID")
local auraIndicator=Instance.new("TextLabel")
auraIndicator.Name="KillAuraStatus"
auraIndicator.Size=UDim2.fromOffset(175,25)
auraIndicator.Position=UDim2.new(1,-188,0,45)
auraIndicator.BackgroundColor3=Color3.fromRGB(14,24,20)
auraIndicator.BackgroundTransparency=.22
auraIndicator.BorderSizePixel=0
auraIndicator.TextColor3=Color3.fromRGB(140,255,200)
auraIndicator.Text="KILL AURA: ON [H]"
auraIndicator.Font=Enum.Font.Code
auraIndicator.TextScaled=true
auraIndicator.Parent=screen
local blackholeIndicator=Instance.new("TextLabel")
blackholeIndicator.Name="EventHorizonBlackholeStatus"
blackholeIndicator.Size=UDim2.fromOffset(290,30)
blackholeIndicator.AnchorPoint=Vector2.new(.5,0)
blackholeIndicator.Position=UDim2.new(.5,0,0,77)
blackholeIndicator.BackgroundColor3=Color3.fromRGB(14,7,30)
blackholeIndicator.BackgroundTransparency=.12
blackholeIndicator.BorderSizePixel=0
blackholeIndicator.TextColor3=Color3.fromRGB(205,169,255)
blackholeIndicator.TextStrokeTransparency=.32
blackholeIndicator.TextScaled=true
blackholeIndicator.Font=Enum.Font.Code
blackholeIndicator.Text=""
blackholeIndicator.Visible=false
blackholeIndicator.Parent=screen
local killIndicator=Instance.new("TextLabel")
killIndicator.Name="KillModeStatus"
killIndicator.Size=UDim2.fromOffset(203,25)
killIndicator.Position=UDim2.new(1,-188,0,75)
killIndicator.BackgroundTransparency=.18
killIndicator.BackgroundColor3=Color3.fromRGB(42,14,26)
killIndicator.BorderSizePixel=0
killIndicator.TextColor3=Color3.fromRGB(255,165,188)
killIndicator.Font=Enum.Font.Code
killIndicator.TextScaled=true
killIndicator.Text="TARGET: HUMANOIDS [K]"
killIndicator.Parent=screen
local projectionHUD=Instance.new("TextLabel")
projectionHUD.Size=UDim2.fromOffset(320,29)
projectionHUD.AnchorPoint=Vector2.new(.5,0)
projectionHUD.Position=UDim2.new(.5,0,0,109)
projectionHUD.BackgroundColor3=Color3.fromRGB(26,43,54)
projectionHUD.BackgroundTransparency=.25
projectionHUD.TextColor3=Color3.fromRGB(220,249,255)
projectionHUD.Font=Enum.Font.Code
projectionHUD.TextScaled=true
projectionHUD.BorderSizePixel=0
projectionHUD.Visible=false
projectionHUD.Parent=screen
local projectionHUDUntil=0
local bRefit=makeButton("REFIT","REFIT")
local bLoop=makeButton("LOOP","LOOP")

local mobileStick=Vector2.zero
local activeStickTouch=nil
local moveRegion=Instance.new("Frame")
moveRegion.Name="MEFEMovementRegion"
moveRegion.Active=true
moveRegion.BackgroundTransparency=1
moveRegion.Size=UDim2.fromScale(.44,.40)
moveRegion.Position=UDim2.fromScale(.01,.58)
moveRegion.Visible=UIS.TouchEnabled
moveRegion.ZIndex=2
moveRegion.Parent=mobile
local moveBase=Instance.new("Frame")
moveBase.Name="MovementStick"
moveBase.AnchorPoint=Vector2.new(.5,.5)
moveBase.Position=UDim2.fromScale(.40,.57)
moveBase.Size=UDim2.fromOffset(122,122)
moveBase.BackgroundColor3=Color3.fromRGB(40,57,72)
moveBase.BackgroundTransparency=.53
moveBase.BorderSizePixel=0
moveBase.ZIndex=3
moveBase.Parent=moveRegion
local baseRound=Instance.new("UICorner")
baseRound.CornerRadius=UDim.new(1,0)
baseRound.Parent=moveBase
local moveThumb=Instance.new("Frame")
moveThumb.Name="Thumb"
moveThumb.AnchorPoint=Vector2.new(.5,.5)
moveThumb.Position=UDim2.fromScale(.5,.5)
moveThumb.Size=UDim2.fromScale(.44,.44)
moveThumb.BackgroundColor3=Color3.fromRGB(176,229,255)
moveThumb.BackgroundTransparency=.22
moveThumb.BorderSizePixel=0
moveThumb.ZIndex=4
moveThumb.Parent=moveBase
local thumbRound=Instance.new("UICorner")
thumbRound.CornerRadius=UDim.new(1,0)
thumbRound.Parent=moveThumb
local function setMoveTouch(inp)
    local origin=moveBase.AbsolutePosition+moveBase.AbsoluteSize*.5
    local delta=Vector2.new(inp.Position.X,inp.Position.Y)-origin
    local radius=math.max(1,moveBase.AbsoluteSize.X*.44)
    local bounded=delta.Magnitude>radius and delta.Unit*radius or delta
    local normalized=bounded/radius
    mobileStick=normalized.Magnitude>.12 and Vector2.new(normalized.X,normalized.Y) or Vector2.zero
    moveThumb.Position=UDim2.new(.5, bounded.X, .5, bounded.Y)
end
moveRegion.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.Touch and not activeStickTouch then
        activeStickTouch=inp
        setMoveTouch(inp)
    end
end)
UIS.InputChanged:Connect(function(inp)
    if inp==activeStickTouch then setMoveTouch(inp) end
end)
UIS.InputEnded:Connect(function(inp)
    if inp==activeStickTouch then
        activeStickTouch=nil
        mobileStick=Vector2.zero
        moveThumb.Position=UDim2.fromScale(.5,.5)
    end
end)
local function layoutMobile()
    local current=workspace.CurrentCamera
    if current then Camera=current end
    local vp=Camera.ViewportSize
    if vp.X<150 or vp.Y<150 then
        local success,resolution=pcall(function() return game:GetService("GuiService"):GetScreenResolution() end)
        if success and resolution.X>=150 and resolution.Y>=150 then vp=resolution end
    end
    if vp.X<150 or vp.Y<150 then
        warn("[MEFE MOBILE] Layout waiting for real viewport; received "..tostring(vp))
        return false
    end
	local short=math.min(vp.X,vp.Y)
    local stickSize=math.clamp(short*.23,98,152)
    moveBase.Size=UDim2.fromOffset(stickSize,stickSize)
	local s=math.clamp(short*.115,54,96)
	local small=math.clamp(short*.082,42,68)
	local gap=s*.98
	local right=vp.X-s*.72
	local bottom=vp.Y-s*.72
	bC.Size=UDim2.fromOffset(s,s)
	bX.Size=UDim2.fromOffset(s,s)
	bZ.Size=UDim2.fromOffset(s,s)
	bV.Size=UDim2.fromOffset(s,s)
	bF.Size=UDim2.fromOffset(s,s)
	bG.Size=UDim2.fromOffset(s*1.12,s*.86)
    bGlass.Size=UDim2.fromOffset(s*1.46,s*.77)
    bSpecial.Size=UDim2.fromOffset(s*1.28,s*.76)
	bB.Size=UDim2.fromOffset(small*1.6,small*.82)
	bN.Size=UDim2.fromOffset(small*1.6,small*.82)
	bM.Size=UDim2.fromOffset(small*1.6,small*.82)
	bAura.Size=UDim2.fromOffset(small*1.75,small*.75)
	bKill.Size=UDim2.fromOffset(small*1.95,small*.75)
	bMode.Size=UDim2.fromOffset(s*1.18,s*.68)
	bRefit.Size=UDim2.fromOffset(small*1.25,small*.72)
	bLoop.Size=UDim2.fromOffset(small*1.25,small*.72)
	bC.Position=UDim2.fromOffset(right,bottom)
	bX.Position=UDim2.fromOffset(right-gap,bottom-gap*.18)
	bZ.Position=UDim2.fromOffset(right-gap*.08,bottom-gap)
	bV.Position=UDim2.fromOffset(right-gap*1.55,bottom-gap*1.02)
	bF.Position=UDim2.fromOffset(right-gap*.72,bottom-gap*1.82)
	bG.Position=UDim2.fromOffset(right-gap*1.7,bottom-gap*1.92)
    bGlass.Position=UDim2.fromOffset(right-gap*2.32,bottom-gap*2.65)
    bSpecial.Position=UDim2.fromOffset(right-gap*2.45,bottom-gap*1.16)
	bB.Position=UDim2.fromOffset(small*.95,small*2.1)
	bN.Position=UDim2.fromOffset(small*2.7,small*2.1)
	bM.Position=UDim2.fromOffset(small*4.45,small*2.1)
	bAura.Position=UDim2.fromOffset(small*3.15,small*.75)
	bKill.Position=UDim2.fromOffset(small*5.1,small*.75)
	bMode.Position=UDim2.fromOffset(right-gap*2.05,bottom-gap*.1)
	bRefit.Position=UDim2.fromOffset(small*.82,small*.75)
	bLoop.Position=UDim2.fromOffset(small*2.2,small*.75)
	modeLabel.Size=UDim2.fromOffset(math.min(vp.X*.76,560),math.clamp(short*.065,32,48))
    moveRegion.Visible=UIS.TouchEnabled
    for _,button in pairs(uiButtons) do
        if button~=bGlass and button~=bSpecial then button.Visible=UIS.TouchEnabled end
    end
    bGlass.Visible=UIS.TouchEnabled and mode==5
    bSpecial.Visible=UIS.TouchEnabled and (mode==2 or mode==4 or mode==5 or mode==8)
    return true
end

layoutMobile()
local lastLayoutViewport=Vector2.zero
task.spawn(function()
    local warned=false
    while script.Parent and not GuiReadyForHandshake do
        local current=workspace.CurrentCamera
        if current then Camera=current end
        local vp=Camera and Camera.ViewportSize
        if vp and vp.X>=150 and vp.Y>=150 and screen.Parent==playerGui and screen.Enabled then
            layoutMobile()
            RS.RenderStepped:Wait()
            if modeLabel.AbsoluteSize.X>25 and screen.Parent==playerGui and screen.Enabled then
                GuiReadyForHandshake=true
                print("[MEFE MOBILE] REAL GUI RENDERED "..tostring(vp.X).."x"..tostring(vp.Y).." / touch="..tostring(UIS.TouchEnabled))
                updateStartup("GUI VISIBLE + CAMERA READY")
                break
            end
        else
            if not warned then
                warned=true
                warn("[MEFE MOBILE] Waiting for a rendered GUI and valid Roblox camera")
            end
        end
        task.wait(.12)
    end
end)

local function fakeParts()
	local t={}
    local refs=Shared:FindFirstChild(SCID.."_Refs")
    if refs then
        for _,ref in ipairs(refs:GetChildren()) do
            if ref:IsA("ObjectValue") and ref.Value and ref.Value:IsA("BasePart") then
                t[#t+1]=ref.Value
            end
        end
    end
    if #t>0 then return t end
	for _,v in ipairs(workspace:GetChildren()) do
		if (v:IsA("BasePart") and v:GetAttribute("CXID")==SCID) or v.Name=="MT2FX" or v:GetAttribute("MEFEEffect")==true then
			t[#t+1]=v
		end
	end
	return t
end

local function pointerRay()
	local cam=workspace.CurrentCamera
	local vp=cam.ViewportSize
	local x=vp.X*.5
	local y=vp.Y*.5
	if UIS.PreferredInput==Enum.PreferredInput.KeyboardAndMouse then
		local m=UIS:GetMouseLocation()
		x=m.X
		y=m.Y
	elseif UIS.PreferredInput==Enum.PreferredInput.Touch and worldTouch then
		x=worldTouch.X
		y=worldTouch.Y
	end
	return cam:ViewportPointToRay(x,y)
end

local function aimPoint()
	local ray=pointerRay()
	local rp=RaycastParams.new()
	rp.FilterType=Enum.RaycastFilterType.Exclude
    local excluded=fakeParts()
    for _,obj in ipairs(workspace:GetChildren()) do
        if obj.Name=="MT2FX" or obj:GetAttribute("MEFEEffect")==true or obj:GetAttribute("CXID")==SCID then
            excluded[#excluded+1]=obj
        end
    end
    if LP.Character then excluded[#excluded+1]=LP.Character end
    rp.FilterDescendantsInstances=excluded
    local hit=workspace:Raycast(ray.Origin,ray.Direction*180,rp)
	return hit and hit.Position or ray.Origin+ray.Direction*110
end

local function cast(k)
	if not AttackRemote then return end
	if mode==1 and k=="Z" then
		beamActive=not beamActive
		AttackRemote:FireServer(beamActive and "TOGGLE_ON" or "TOGGLE_OFF","Z",aimPoint())
		bZ.Text=beamActive and "Z ON" or "Z"
		return
	end
	AttackRemote:FireServer("CAST",k,aimPoint())
end

local function useSpecial()
    if (mode==2 or mode==4 or mode==5 or mode==8 or mode==9) and AttackRemote then AttackRemote:FireServer("SPECIAL",nil,aimPoint()) end
end

local function toggleAura()
	if AttackRemote then AttackRemote:FireServer("AURA_TOGGLE") end
end

local function toggleKillMode()
	if AttackRemote then AttackRemote:FireServer("KILLMODE_TOGGLE") end
end

local function sendModeAction(kind)
    if AttackRemote then AttackRemote:FireServer("MODE",kind) end
end
local function cycleMode() sendModeAction("CYCLE") end
local function toggleSubmode() sendModeAction("TOGGLE") end
local function enterSecret() sendModeAction("SECRET") end
local holdStart=nil
local function finishModeHold()
    if not holdStart then return end
    local elapsed=os.clock()-holdStart
    holdStart=nil
    if elapsed>=1.5 and mode==8 and secretUnlocked then enterSecret()
    elseif elapsed>=.45 then toggleSubmode()
    else cycleMode() end
end

local function utility(ev)
	if Remote then Remote:FireServer(ev) end
end

bMode.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        holdStart=os.clock()
    end
end)
bMode.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        finishModeHold()
    end
end)
bZ.Activated:Connect(function() cast("Z") end)
bX.Activated:Connect(function() cast("X") end)
bC.Activated:Connect(function() cast("C") end)
bV.Activated:Connect(function() cast("V") end)
bF.Activated:Connect(function() cast("F") end)
bG.Activated:Connect(function() cast("G") end)
bGlass.Activated:Connect(function() cast("GLASS_CANNON") end)
bSpecial.Activated:Connect(useSpecial)
bB.Activated:Connect(function() cast("B") end)
bN.Activated:Connect(function() cast("N") end)
bM.Activated:Connect(function() cast("M") end)
bAura.Activated:Connect(toggleAura)
bKill.Activated:Connect(toggleKillMode)
bRefit.Activated:Connect(function() utility("REFIT") end)
bLoop.Activated:Connect(function() utility("LOOP") end)

local keymap={

    [Enum.KeyCode.T]=toggleMusic,
	[Enum.KeyCode.Z]=function() cast("Z") end,
	[Enum.KeyCode.X]=function() cast("X") end,
	[Enum.KeyCode.C]=function() cast("C") end,
	[Enum.KeyCode.V]=function() cast("V") end,
	[Enum.KeyCode.F]=function() cast("F") end,

    [Enum.KeyCode.R]=useSpecial,
    [Enum.KeyCode.ButtonL3]=useSpecial,
	[Enum.KeyCode.H]=toggleAura,
	[Enum.KeyCode.K]=toggleKillMode,
	[Enum.KeyCode.B]=function() cast("B") end,
	[Enum.KeyCode.N]=function() cast("N") end,
	[Enum.KeyCode.M]=function() cast("M") end,
	[Enum.KeyCode.ButtonL1]=function() cast("B") end,
	[Enum.KeyCode.ButtonR1]=function() cast("N") end,
	[Enum.KeyCode.ButtonSelect]=function() cast("M") end,
	[Enum.KeyCode.P]=function() utility("REFIT") end,
	[Enum.KeyCode.O]=function() utility("LOOP") end,

	[Enum.KeyCode.ButtonR2]=function() cast("Z") end,
	[Enum.KeyCode.ButtonX]=function() cast("X") end,
	[Enum.KeyCode.ButtonB]=function() cast("C") end,
	[Enum.KeyCode.ButtonL2]=function() cast("V") end,
	[Enum.KeyCode.DPadDown]=function() cast("F") end,
	[Enum.KeyCode.DPadUp]=toggleKillMode,

	[Enum.KeyCode.DPadLeft]=function() utility("REFIT") end,
	[Enum.KeyCode.DPadRight]=function() utility("LOOP") end
}

local heldUltimate=nil
UIS.InputBegan:Connect(function(inp,gpe)
    if inp.UserInputType.Name:sub(1,7)=="Gamepad" then activeGamepad=inp.UserInputType end
    if gpe and inp.UserInputType.Name:sub(1,7)~="Gamepad" then return end
    if UIS:GetFocusedTextBox() then return end
    if inp.KeyCode==Enum.KeyCode.J or inp.KeyCode==Enum.KeyCode.ButtonY then holdStart=os.clock() return end
    if inp.KeyCode==Enum.KeyCode.G or inp.KeyCode==Enum.KeyCode.ButtonR3 then
        if mode==5 and not activeSubmode then
            if not heldUltimate then heldUltimate={Started=os.clock(),Mode=mode} end
        else
            cast("G")
        end
    end
	local fn=keymap[inp.KeyCode]
	if fn then fn() end
	if inp.UserInputType==Enum.UserInputType.MouseButton2 then
		cameraDragging=true
		lastMouseBehavior=UIS.MouseBehavior
		UIS.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
	elseif inp.UserInputType==Enum.UserInputType.Touch and not gpe and not activeStickTouch then
        local active=workspace.CurrentCamera or Camera
		local vp=active.ViewportSize
		local p=Vector2.new(inp.Position.X,inp.Position.Y)
        if inp.Position.X>vp.X*.42 then
            worldTouch=p
            touchCamera=inp
            lastTouch=p
		end
	end
end)

UIS.InputEnded:Connect(function(inp)
    if inp.KeyCode==Enum.KeyCode.J or inp.KeyCode==Enum.KeyCode.ButtonY then finishModeHold() return end
    if (inp.KeyCode==Enum.KeyCode.G or inp.KeyCode==Enum.KeyCode.ButtonR3) and heldUltimate then
        local previous=heldUltimate
        heldUltimate=nil
        if mode==5 and previous.Mode==5 and not activeSubmode then
            cast(os.clock()-previous.Started>=.34 and "GLASS_CANNON" or "G")
        end
    end
	if inp.UserInputType==Enum.UserInputType.MouseButton2 then
		cameraDragging=false
		UIS.MouseBehavior=lastMouseBehavior
	elseif inp==touchCamera then
		touchCamera=nil
		lastTouch=nil
    elseif inp.KeyCode==Enum.KeyCode.Thumbstick1 then
        gamepadMove=Vector2.zero
        gamepadNeutralUntil=os.clock()+.22
    elseif inp.KeyCode==Enum.KeyCode.Thumbstick2 then
        gamepadLook=Vector2.zero
	end
end)

UIS.InputChanged:Connect(function(inp)
	if inp.UserInputType==Enum.UserInputType.MouseWheel then
		Zoom=math.clamp(Zoom-inp.Position.Z*(1+Zoom*.16),3,120)
	elseif inp.UserInputType==Enum.UserInputType.MouseMovement and cameraDragging then
		Yaw=Yaw+inp.Delta.X*math.rad(.25)
		Pitch=math.clamp(Pitch+inp.Delta.Y*math.rad(.25),math.rad(-80),math.rad(80))
	elseif inp.UserInputType==Enum.UserInputType.Touch then
		local p=Vector2.new(inp.Position.X,inp.Position.Y)
        if inp==touchCamera and lastTouch then
            worldTouch=p
			local d=p-lastTouch
			lastTouch=p
			Yaw=Yaw+d.X*math.rad(.18)
			Pitch=math.clamp(Pitch+d.Y*math.rad(.18),math.rad(-80),math.rad(80))
		end
	elseif inp.KeyCode==Enum.KeyCode.Thumbstick1 then
        activeGamepad=inp.UserInputType
        gamepadMove=Vector2.new(inp.Position.X,inp.Position.Y)
        if gamepadMove.Magnitude<=.16 then gamepadNeutralUntil=os.clock()+.08 end
	elseif inp.KeyCode==Enum.KeyCode.Thumbstick2 then
        activeGamepad=inp.UserInputType
        gamepadLook=Vector2.new(inp.Position.X,inp.Position.Y)
	end
end)

local function cleanStick(value,deadzone,exponent)
    local m=value.Magnitude
    if m<=deadzone then return Vector2.zero end
    local amount=math.clamp((m-deadzone)/(1-deadzone),0,1)
    return value.Unit*amount^(exponent or 1)
end

UIS.GamepadDisconnected:Connect(function(which)
    if which==activeGamepad then
        gamepadMove=Vector2.zero
        gamepadLook=Vector2.zero
        gamepadNeutralUntil=os.clock()+.6
    end
end)
UIS.GamepadConnected:Connect(function(which)
    activeGamepad=which
    gamepadMove=Vector2.zero
    gamepadLook=Vector2.zero
    gamepadNeutralUntil=os.clock()+.18
end)

local function readXboxSticks()
    local move=Vector2.zero
    local look=Vector2.zero
    local available=false
    local connected,gamepads=pcall(UIS.GetConnectedGamepads,UIS)
    if connected and type(gamepads)=="table" then
        if not table.find(gamepads,activeGamepad) then
            activeGamepad=gamepads[1] or Enum.UserInputType.Gamepad1
            gamepadMove=Vector2.zero
            gamepadLook=Vector2.zero
        end
        available=#gamepads>0
    else
        available=UIS.GamepadEnabled
    end
    if available then
        local ok,states=pcall(UIS.GetGamepadState,UIS,activeGamepad)
        if ok and type(states)=="table" then
            for _,state in ipairs(states) do
                if state.KeyCode==Enum.KeyCode.Thumbstick1 then
                    move=Vector2.new(state.Position.X,state.Position.Y)
                elseif state.KeyCode==Enum.KeyCode.Thumbstick2 then
                    look=Vector2.new(state.Position.X,state.Position.Y)
                end
            end
        end
    end
    if os.clock()<gamepadNeutralUntil then move=Vector2.zero end
    gamepadMove=move
    gamepadLook=look
    return cleanStick(move,.16,1.18),cleanStick(look,.12,1.45)
end

local function keyboardMove()
	local function down(k)
		return UIS:IsKeyDown(k) and 1 or 0
	end
	local x=down(Enum.KeyCode.D)+down(Enum.KeyCode.Right)-down(Enum.KeyCode.A)-down(Enum.KeyCode.Left)
	local z=down(Enum.KeyCode.S)+down(Enum.KeyCode.Down)-down(Enum.KeyCode.W)-down(Enum.KeyCode.Up)
	local v=Vector3.new(x,0,z)
	if v.Magnitude>1 then v=v.Unit end
	return v
end

local function mobileMove()
    return Vector3.new(mobileStick.X,0,mobileStick.Y)
end

AttackClientHandler=function(action,d)
    if action=="CLIENT_READY_ACK" then
        if d and typeof(d.Position)=="Vector3" then
            CharPos=d.Position
            CameraFollow=CharPos+Vector3.new(0,1.5,0)
        end
        if not GuiReadyForHandshake then
            warn("[MEFE MOBILE] Ignoring premature CLIENT_READY_ACK; GUI has not rendered")
            return
        end
        if not ReadyForCustomCamera then
            Camera=workspace.CurrentCamera or Camera
            ReadyForCustomCamera=true
            Camera.CameraType=Enum.CameraType.Scriptable
            LP.Character=nil
            layoutMobile()
            print("[MEFE MOBILE] OWNER READY: Existing camera and render-verified controls active")
        end
        updateStartup("READY - TEST MOVE / CAMERA")
        task.delay(12,function()
            if statusLabel.Parent and ReadyForCustomCamera then statusLabel.Visible=false end
        end)
    elseif action=="MODE" and d then
        mode=d.Mode or mode
        activeSubmode=d.Submode==true
        secretUnlocked=d.SecretUnlocked==true
        playModeMusic(mode)
        modeLabel.Text=((activeSubmode and "SUBMODE" or "MODE").." %d // %s"):format(mode,d.Name or "?")
        modeLabel.TextColor3=mode==9 and Color3.fromRGB(101,255,127) or (activeSubmode and Color3.fromRGB(183,229,255) or Color3.new(1,1,1))
        bMode.Text=mode==9 and "MODE" or (activeSubmode and "SUBMODE" or "MODE")
        local r3Labels={"RED CATHEDRAL","LAST ECLIPSE","EUCLIDEAN PROOF","PARADOX THEATER","24TH FRAME","SEVENFOLD JUDGEMENT","BLACK HOLE","THE GREAT SILENCE"}
        bG.Text="R3 "..(activeSubmode and "SUBMODE ULTIMATE" or (mode==9 and "GREEN APOCALYPSE" or r3Labels[mode]))
        bSpecial.Visible=(mode==2 or mode==4 or mode==5 or mode==8 or mode==9)
        bSpecial.Text=({[2]="MOONSTEP",[4]="PORTAL",[5]="R FRAME",[8]="NULL GUARD",[9]="INFECT"})[mode] or "SPECIAL"
        bGlass.Visible=mode==5 and UIS.TouchEnabled
        heldUltimate=nil
        if mode~=5 then projectionDash=nil projectionHUD.Visible=false end
		if mode~=1 and beamActive then
			beamActive=false
			bZ.Text="Z"
		end

    elseif action=="SECRET_PROGRESS" and d then
        secretUnlocked=d.Unlocked==true
        projectionHUD.Text=secretUnlocked and "BACTERIOPHAGE UNLOCKED // HOLD MODE 1.5S IN NULL HYMN" or ("NULL COUNTERS: %d/3"):format(d.Count or 0)
        projectionHUD.Visible=true
        projectionHUDUntil=os.clock()+3
    elseif action=="PROJECTION_DASH" and d and typeof(d.To)=="Vector3" then
        projectionDash={From=CharPos,To=d.To,Started=os.clock(),Duration=math.max(.12,d.Duration or .86),GlassCannon=d.GlassCannon==true}
        projectionHUD.Visible=true
        projectionHUD.Text=d.GlassCannon and "GLASS CANNON // PHASE THROUGH" or (d.Variant and "PROJECTION // FRAME BREAK" or (d.Second and "PROJECTION // SECOND DASH" or "PROJECTION // 24 FRAMES"))
        projectionHUDUntil=os.clock()+1.1
    elseif action=="PROJECTION_STATUS" and d then
        if d.Frozen then
            projectionHUD.Text="FRAME FREEZE // 3 SECONDS"
        else
            projectionHUD.Text=("PROJECTION // %d%%"):format(math.floor(d.Percent or 0))
        end
        projectionHUD.Visible=(d.Percent or 0)>0 or d.Frozen==true
        projectionHUDUntil=os.clock()+1.8
    elseif action=="KILLMODE_STATE" and d then
        killMode=d.Enabled==true
        bKill.Text=killMode and "HUMANOID" or "PART+RIG"
        bKill.BackgroundColor3=killMode and Color3.fromRGB(91,24,48) or Color3.fromRGB(41,47,65)
        killIndicator.Text=killMode and "TARGET: HUMANOIDS [K]" or "TARGET: PARTS+RIGS [K]"
        killIndicator.TextColor3=killMode and Color3.fromRGB(255,165,188) or Color3.fromRGB(155,205,255)
        if blackholeShake then blackholeIndicator.Text=killMode and "BLACK HOLE: HUMANOIDS" or "BLACK HOLE: PARTS+RIGS" end
    elseif action=="BLACKHOLE_START" and d then
        if typeof(d.Position)=="Vector3" then
            blackholeShake={Center=d.Position,Started=os.clock(),Until=os.clock()+(d.Duration or 16),Radius=d.ShakeRadius or 280,Id=d.Id}
            blackholeIndicator.Visible=true
            blackholeIndicator.Text=killMode and "BLACK HOLE: HUMANOIDS" or "BLACK HOLE: PARTS+RIGS"
        end
    elseif action=="BLACKHOLE_END" and d then
        if blackholeShake and blackholeShake.Id==d.Id then
            blackholeShake.Until=math.min(blackholeShake.Until,os.clock()+.48)
            blackholeIndicator.Visible=false
        end
	elseif action=="AURA_STATE" and d then
		auraEnabled=d.Enabled==true
		bAura.Text=auraEnabled and "AURA ON" or "AURA OFF"
        bAura.BackgroundColor3=auraEnabled and Color3.fromRGB(20,75,54) or Color3.fromRGB(88,27,32)
        auraIndicator.Text=auraEnabled and "KILL AURA: ON [H]" or "KILL AURA: OFF [H]"
        auraIndicator.TextColor3=auraEnabled and Color3.fromRGB(140,255,200) or Color3.fromRGB(255,150,150)
        auraIndicator.BackgroundColor3=auraEnabled and Color3.fromRGB(14,24,20) or Color3.fromRGB(35,16,19)
	elseif action=="BEAM_STATE" and d then
		beamActive=d.Active==true
		bZ.Text=beamActive and "Z ON" or "Z"
	elseif action=="TELEPORT" and d and typeof(d.Position)=="Vector3" then
		CharPos=d.Position
	end
end

if AttackRemote then AttackRemote:FireServer("AURA_SYNC") end

local function updateInputHint()
	preferred=UIS.PreferredInput
	cross.Visible=preferred==Enum.PreferredInput.Gamepad
	if preferred==Enum.PreferredInput.Gamepad then
		hint.Text="Y MODE RT Z X X B C LT V D↓ F R3 G L3 SPECIAL LB B RB N SELECT M D↑ KILL"
	elseif UIS.TouchEnabled then
		hint.Text="R special • G super • GLASS (mode 5) • T music"
	else
		hint.Text="J tap mode / hold submode / 1.5s secret in Null Hymn • G super • R special • T music"
	end
end
UIS:GetPropertyChangedSignal("PreferredInput"):Connect(updateInputHint)
updateInputHint()

local mefeCameraBinding="MEFE_CAMERA_"..SCID
RS:BindToRenderStep(mefeCameraBinding,Enum.RenderPriority.Camera.Value+2,function()
    local active=workspace.CurrentCamera
    if active and active~=Camera then
        Camera=active
        print("[MEFE MOBILE] Roblox changed CurrentCamera; reattached MT2 controller")
        if ReadyForCustomCamera then Camera.CameraType=Enum.CameraType.Scriptable end
        layoutMobile()
    end
    if Camera then
        local viewport=Camera.ViewportSize
        if viewport.X>=150 and viewport.Y>=150 and (viewport-lastLayoutViewport).Magnitude>1 then
            lastLayoutViewport=viewport
            layoutMobile()
        end
    end
    if not ReadyForCustomCamera then return end
	local now=os.clock()
	local dt=math.min(now-lastClock,.075)
	lastClock=now
    if UIS.PreferredInput==Enum.PreferredInput.Gamepad then
        local _,look=readXboxSticks()
        Yaw=Yaw+look.X*math.rad(2.65)*dt*60
        Pitch=math.clamp(Pitch-look.Y*math.rad(2.2)*dt*60,math.rad(-80),math.rad(80))
    end
	LerpZoom=LerpZoom+(Zoom-LerpZoom)*math.min(.25*dt*60,1)
    local focusGoal=CharPos+Vector3.new(0,1.5,0)
    CameraFollow=CameraFollow:Lerp(focusGoal,1-math.exp(-5.5*dt))
    local finalCF=CFrame.new(CameraFollow)*CFrame.Angles(0,-Yaw,0)*CFrame.Angles(-Pitch,0,0)*CFrame.new(0,0,LerpZoom)
    if blackholeShake then
        local t=now-blackholeShake.Started
        if now>=blackholeShake.Until then
            blackholeShake=nil
            blackholeIndicator.Visible=false
        else
            blackholeIndicator.Text=(killMode and "BLACK HOLE: HUMANOIDS" or "BLACK HOLE: PARTS+RIGS")..(" | %.1fs"):format(math.max(0,blackholeShake.Until-now))
            local distance=(CharPos-blackholeShake.Center).Magnitude
            local falloff=math.clamp(1-distance/blackholeShake.Radius,0,1)
            local duration=math.max(blackholeShake.Until-blackholeShake.Started,.01)
            local envelope=math.min(1,t/.75)*math.min(1,(blackholeShake.Until-now)/.65)
            local intensity=(.28+falloff*.72)*envelope
            local ox=(math.sin(t*31)+math.sin(t*53)*.4)*.26*intensity
            local oy=(math.cos(t*36)+math.sin(t*48)*.4)*.19*intensity
            local rz=math.sin(t*25)*math.rad(1.0)*intensity
            finalCF=finalCF*CFrame.new(ox,oy,0)*CFrame.Angles(0,0,rz)
        end
    end
    Camera.CFrame=finalCF
	Camera.CameraType=Enum.CameraType.Scriptable
end)

RS.Heartbeat:Connect(function(dt)
    if projectionHUD.Visible and os.clock()>projectionHUDUntil then projectionHUD.Visible=false end
    if not Puller or not Puller.Parent or not AttackRemote or not AttackRemote.Parent then
        if not RebindingRemotes then task.defer(bindRemotes) end
        return
    end
    if not ReadyForCustomCamera then
        if GuiReadyForHandshake and os.clock()-lastReadyRequest>2 then
            lastReadyRequest=os.clock()
            AttackRemote:FireServer("CLIENT_READY")
        end
        return
    end
	local mv
	if UIS.PreferredInput==Enum.PreferredInput.Gamepad then
        local left=readXboxSticks()
        mv=left.Magnitude>.001 and Vector3.new(left.X,0,-left.Y) or Vector3.zero
    elseif UIS.TouchEnabled and (UIS.PreferredInput==Enum.PreferredInput.Touch or mobileStick.Magnitude>.01 or not UIS.KeyboardEnabled) then
        mv=mobileMove()
	else
		mv=keyboardMove()
	end
	if mv.Magnitude>1 then mv=mv.Unit end
    if projectionDash then
        local t=math.clamp((os.clock()-projectionDash.Started)/projectionDash.Duration,0,1)
        local eased=projectionDash.GlassCannon and t or t*t*(3-2*t)
        CharPos=projectionDash.From:Lerp(projectionDash.To,eased)
        mv=Vector3.zero
        if t>=1 then projectionDash=nil end
    elseif mv.Magnitude>.01 then
        local movementCF=CFrame.new(CharPos)*CFrame.Angles(0,-Yaw,0)*CFrame.Angles(-Pitch,0,0)
        local dir=movementCF.LookVector*(-mv.Z)+movementCF.RightVector*mv.X
        if not FlyMode then dir=Vector3.new(dir.X,0,dir.Z) end
        if dir.Magnitude>.01 then
            CharPos=CharPos+dir.Unit*SPEED*math.clamp(dt*60,0,2)*math.clamp(mv.Magnitude,0,1)
        end
    end
    if CharPos.Y<-200 then
        local nearest=nil
        local distance=math.huge
        for _,obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") then
                local d=(obj.Position-CharPos).Magnitude
                if d<distance then distance=d nearest=obj end
            end
        end
        CharPos=nearest and nearest.Position+Vector3.new(0,9,0) or Vector3.new(CharPos.X,9,CharPos.Z)
        CameraFollow=CharPos+Vector3.new(0,1.5,0)
    end
	local aim=aimPoint()
	pcall(function()
		Puller:FireServer(CFrame.new(CharPos)*CFrame.Angles(0,-Yaw,0)*CFrame.Angles(-Pitch,0,0),mv,aim)
	end)
	if beamActive then
		pcall(function()
			AttackRemote:FireServer("AIM","Z",aim)
		end)
	end
end)

script.Destroying:Connect(function()
    pcall(function() RS:UnbindFromRenderStep(mefeCameraBinding) end)
end)
print("[MEFE MOBILE] Input and camera callbacks registered; connecting to server")
task.spawn(function()
    local last=0
    while script.Parent do
        task.wait(.5)
        if ReadyForCustomCamera and (os.clock()-last)>12 then
            last=os.clock()
            local vp=Camera and Camera.ViewportSize or Vector2.zero
            if screen.Parent~=playerGui or not screen.Enabled then
                warn("[MEFE MOBILE] MT2Controls was removed or disabled after READY; GUI parent="..tostring(screen.Parent))
            elseif vp.X<150 or vp.Y<150 then
                warn("[MEFE MOBILE] CurrentCamera has invalid viewport after READY: "..tostring(vp))
            else
                print("[MEFE MOBILE] Running | GUI="..tostring(screen.Enabled).." | viewport="..tostring(vp))
            end
        end
    end
end)
task.defer(bindRemotes)
]=====],
    Effects=[=====[
local RS=game:GetService("RunService")
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local StarterGui=game:GetService("StarterGui")

local LP=Players.LocalPlayer
local SCID="__SCID__"
local OwnerName="__OWNER__"
if type(SCID)~="string" or type(OwnerName)~="string" then
    warn("[MEFE FX] Missing session attributes")
    return
end
print("[MEFE FX] Client started for "..LP.Name)
print("[MEFE EFFECTS CLIENT 01] Starting visuals for "..tostring(LP and LP.Name))

local Remote=nil
local Puller=nil
local AttackRemote=nil
local RemoteSigsC={}
local RemoteClientHandler=nil
local AttackClientHandler=nil
local RebindingRemotes=false

local function ClearRemoteSigs()
	for _,sig in pairs(RemoteSigsC) do
		pcall(function() sig:Disconnect() end)
	end
	table.clear(RemoteSigsC)
end

local function FindRemotes()
	while true do
		local r=Shared:FindFirstChild(SCID.."_R")
		local p=Shared:FindFirstChild(SCID.."_P")
		local a=Shared:FindFirstChild(SCID.."_A")
		if r and p and a then return r,p,a end
		RS.Heartbeat:Wait()
	end
end

local function BindRemotes()
	if RebindingRemotes then return end
	RebindingRemotes=true
	ClearRemoteSigs()
	local r,p,a=FindRemotes()
	Remote,Puller,AttackRemote=r,p,a
	table.insert(RemoteSigsC,r.OnClientEvent:Connect(function(...)
		if RemoteClientHandler then RemoteClientHandler(...) end
	end))
	table.insert(RemoteSigsC,a.OnClientEvent:Connect(function(...)
		if AttackClientHandler then AttackClientHandler(...) end
	end))
	local lost=false
	local function onLost()
		if lost then return end
		lost=true
		Remote=nil
		Puller=nil
		AttackRemote=nil
		RebindingRemotes=false
		task.spawn(BindRemotes)
	end
	for _,rem in ipairs({r,p,a}) do
		table.insert(RemoteSigsC,rem.Destroying:Connect(onLost))
		table.insert(RemoteSigsC,rem.AncestryChanged:Connect(function()
			if not rem:IsDescendantOf(game) then
				onLost()
			end
		end))
	end
	RebindingRemotes=false
end

task.spawn(function()
	for _=1,40 do
		if pcall(function()
			StarterGui:SetCore("SendNotification",{Title="MT2",Text="Eight states. One body.",Duration=4})
		end) then break end
		task.wait(.25)
	end
end)


local function GetFakeParts()
	local t={}
    local refs=Shared:FindFirstChild(SCID.."_Refs")
    if refs then
        for _,ref in ipairs(refs:GetChildren()) do
            if ref:IsA("ObjectValue") and ref.Value and ref.Value:IsA("BasePart") then
                t[#t+1]=ref.Value
            end
        end
    end
    if #t>0 then return t end
	for _,v in ipairs(workspace:GetChildren()) do
		if v:IsA("BasePart") and v:GetAttribute("CXID")==SCID then t[#t+1]=v end
	end
	return t
end

local CORRUPT_CHARS={"$","#","@","?","!","*","&","%","^","~","|","_","<",">","/","\\","[","]","{","}","=","+","-"}
local function RandCorrupt(n)
    local s=""
    for _=1,n do
        s=s..CORRUPT_CHARS[math.random(#CORRUPT_CHARS)]
    end
    return s
end
local function ShowChatText(msg)
	local torso
	for _,v in ipairs(GetFakeParts()) do if v.Name=="Torso" then torso=v break end end
	if not torso then return end
	msg=tostring(msg):sub(1,80)
	local bg=Instance.new("BillboardGui") bg.Size=UDim2.new(0,420,0,60) bg.StudsOffset=Vector3.new(0,4,0) bg.AlwaysOnTop=true bg.Parent=torso
	local label=Instance.new("TextLabel") label.Size=UDim2.fromScale(1,1) label.BackgroundTransparency=1 label.TextColor3=Color3.fromRGB(180,180,180) label.Font=Enum.Font.Code label.TextScaled=true label.TextStrokeTransparency=.4 label.Parent=bg
	for i=1,#msg do label.Text=RandCorrupt(i) task.wait(.025) end
	for i=1,#msg do label.Text=msg:sub(1,i)..RandCorrupt(#msg-i) task.wait(.035) end
	label.Text=msg task.wait(.75)
	bg:Destroy()
end

local function SpawnGlitchCube(basePart)
	local cube=Instance.new("Part")
	local s=math.random(8,18)/100
	cube.Size=Vector3.new(s,s,s) cube.Anchored=true cube.CanCollide=false cube.CanQuery=false cube.CanTouch=false cube.Material=Enum.Material.Neon
	cube:SetAttribute("MEFEEffect",true)
	cube.Color=Color3.fromRGB(math.random(70,180),math.random(70,180),math.random(70,180))
	local o=Vector3.new((math.random()-.5)*basePart.Size.X*1.8,(math.random()-.5)*basePart.Size.Y*1.8,(math.random()-.5)*basePart.Size.Z*1.8)
	cube.CFrame=basePart.CFrame*CFrame.new(o) cube.Parent=workspace
	TweenService:Create(cube,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1,Size=Vector3.new(.02,.02,.02)}):Play()
	task.delay(.4,function() pcall(function() cube:Destroy() end) end)
end

RemoteClientHandler=function(ev,...)
	if ev=="CHATTEXT" then ShowChatText(...)
	elseif ev=="REFIT" then for _,p in ipairs(GetFakeParts()) do SpawnGlitchCube(p) end end
end


local Debris=game:GetService("Debris")
local FX=Instance.new("Folder")
FX.Name="MT2FX"
FX:SetAttribute("MEFEEffect",true)
FX.Parent=workspace
script.Destroying:Connect(function() pcall(function() FX:Destroy() end) end)

local MODE_NAMES={"CRIMSON FURY","CLAIR DE LUNE","GEOMETRICAL COMPLEXITY","REALITY DISTORTION","REFRACTED EXISTENCE","STORM OF SERAPHS","EVENT HORIZON","NULL HYMN","BACTERIOPHAGE"}
local EffectSubmode=false
local CurrentMode=1
local palette={
	[1]={Color3.fromRGB(255,20,45),Color3.fromRGB(105,0,12),Color3.fromRGB(255,185,190)},
	[2]={Color3.fromRGB(235,248,255),Color3.fromRGB(95,220,255),Color3.fromRGB(105,115,255)},
	[3]={Color3.fromRGB(255,255,255),Color3.fromRGB(75,185,255),Color3.fromRGB(25,35,70)},
	[4]={Color3.fromRGB(220,235,255),Color3.fromRGB(110,65,255),Color3.fromRGB(20,20,35)},
	[5]={Color3.fromRGB(215,255,255),Color3.fromRGB(155,205,255),Color3.fromRGB(255,255,255)},
	[6]={Color3.fromRGB(255,255,245),Color3.fromRGB(120,205,255),Color3.fromRGB(255,225,90)},
	[7]={Color3.fromRGB(15,15,20),Color3.fromRGB(95,65,145),Color3.fromRGB(235,235,255)},
	[8]={Color3.fromRGB(245,245,245),Color3.fromRGB(25,25,25),Color3.fromRGB(150,150,165)},
    [9]={Color3.fromRGB(99,255,118),Color3.fromRGB(3,135,53),Color3.fromRGB(2,28,14)}
}
local variantPalette={
    [1]={Color3.fromRGB(165,0,21),Color3.fromRGB(55,0,8),Color3.fromRGB(255,107,128)},
    [2]={Color3.fromRGB(195,255,255),Color3.fromRGB(0,138,215),Color3.fromRGB(49,72,168)},
    [3]={Color3.fromRGB(210,110,255),Color3.fromRGB(70,16,180),Color3.fromRGB(240,196,255)},
    [4]={Color3.fromRGB(255,172,218),Color3.fromRGB(192,42,124),Color3.fromRGB(52,9,48)},
    [5]={Color3.fromRGB(244,255,255),Color3.fromRGB(18,234,255),Color3.fromRGB(0,70,110)},
    [6]={Color3.fromRGB(255,241,195),Color3.fromRGB(255,174,42),Color3.fromRGB(117,46,11)},
    [7]={Color3.fromRGB(230,93,244),Color3.fromRGB(63,0,110),Color3.fromRGB(10,0,24)},
    [8]={Color3.fromRGB(190,206,222),Color3.fromRGB(29,38,57),Color3.fromRGB(4,7,17)},
    [9]={Color3.fromRGB(99,255,118),Color3.fromRGB(3,135,53),Color3.fromRGB(2,28,14)}
}

local function fxpart(cf,size,color,trans,shape,material)
    local p=Instance.new(shape=="WEDGE" and "WedgePart" or "Part")
    p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false p.CastShadow=false
    p:SetAttribute("MEFEEffect",true)
    p.Material=material or Enum.Material.Neon p.Color=color p.Transparency=trans or 0 p.Size=size p.CFrame=cf
    if shape and shape~="WEDGE" then p.Shape=shape end
    p.Parent=FX
    return p
end

local function tw(o,t,g,style)
	local x=TweenService:Create(o,TweenInfo.new(t,style or Enum.EasingStyle.Quart,Enum.EasingDirection.Out),g)
	x:Play() return x
end




local SFX = {
	[1] = { 
		Z={{9120705982,1.00,1.05,0}},
		X={{9120769331,1.00,1.08,0}},
		C={{9116279358,.80,.92,0},{9116279358,.72,1.08,.11},{9120705982,.65,1.12,.22}},
		V={{9120273932,.70,1.15,0},{9120769331,1.00,.82,.55}},
		F={{9120273932,.75,.82,0},{9120017499,1.00,.72,.85},{9120769331,.90,.68,.95}},
	},
	[2] = { 
		Z={{9125644410,.85,1.12,0}},
		X={{9120687108,.70,1.18,0},{9120769331,.72,1.32,.34}},
		C={{9120725798,.82,1.10,0},{9120114284,.55,1.22,.18}},
		V={{9125986239,.62,1.08,0},{9125980816,.78,1.12,.25},{9120114284,.70,.96,.62}},
		F={{9125719267,.72,1.06,0},{9120114284,.82,.88,.72},{9120769331,.90,.92,1.00}},
	},
	[3] = { 
		Z={{9119902088,.78,1.18,0}},
		X={{9125980816,.68,1.20,0},{9119594530,.78,1.05,.32}},
		C={{9120114284,.62,1.28,0},{9120114284,.55,1.08,.12},{9120705982,.68,1.20,.30}},
		V={{9119902088,.66,.78,0},{9116281362,.72,1.06,.30},{9120114284,.55,.86,.52}},
		F={{9120273932,.66,1.18,0},{9119902088,.72,.72,.46},{9120017499,.92,.84,.92}},
	},
	[4] = { 
		Z={{9125357173,.72,.72,0},{9120769331,.82,.66,.12}},
		X={{5782801042,.55,.78,0},{9114890176,.86,.72,.18}},
		C={{9125357173,.62,.64,0},{9113966910,.82,.62,.24}},
		V={{9120273932,.55,.62,0},{5782801042,.52,.70,.18},{9120017499,.82,.66,.70}},
		F={{5782801042,.60,.58,0},{9114890176,.82,.58,.34},{9120769331,.90,.55,.70},{9120017499,1.00,.55,1.05}},
	},
}

local function play3DSound(pos,id,volume,speed,maxDistance)
	local emitter=Instance.new("Part")
	emitter.Name="VexSFX"
	emitter.Anchored=true
	emitter.CanCollide=false
	emitter.CanTouch=false
	emitter.CanQuery=false
	emitter:SetAttribute("MEFEEffect",true)
	emitter.Transparency=1
	emitter.Size=Vector3.new(.1,.1,.1)
	emitter.CFrame=CFrame.new(pos)
	emitter.Parent=FX

	local sound=Instance.new("Sound")
	sound.SoundId="rbxassetid://"..tostring(id)
	sound.Volume=volume or .8
	sound.PlaybackSpeed=speed or 1
	sound.RollOffMode=Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance=8
	sound.RollOffMaxDistance=maxDistance or 180
	sound.EmitterSize=6
	sound.Parent=emitter

	sound.Ended:Connect(function()
		if emitter.Parent then emitter:Destroy() end
	end)

	sound:Play()
	Debris:AddItem(emitter,20)
	return sound
end

local function playAttackSFX(d)
	local mode=SFX[d.Mode]
	local layers=mode and mode[d.Key]
	if not layers then return end

	local pos=d.Aim or d.Origin or Vector3.zero
	for _,layer in ipairs(layers) do
		local id,volume,speed,delayTime=layer[1],layer[2],layer[3],layer[4] or 0
		task.delay(delayTime,function()
			if FX and FX.Parent then
				
				local variation=1+(math.random(-2,2)*.01)
				play3DSound(pos,id,volume,speed*variation,d.Key=="F" and 260 or 190)
			end
		end)
	end
end

local function ring(pos,r,c,t)
	local p=fxpart(CFrame.new(pos)*CFrame.Angles(0,0,math.pi/2),Vector3.new(.55,r,r),c,.08,Enum.PartType.Cylinder)
	tw(p,t,{Size=Vector3.new(.08,r*2.8,r*2.8),Transparency=1})
	Debris:AddItem(p,t+.1)
end

local function line(a,b,w,c,t)
	local d=(b-a).Magnitude
	if d<.05 then return end
	local p=fxpart(CFrame.lookAt((a+b)/2,b),Vector3.new(math.max(w,0.45),math.max(w,0.45),d),c,.04)
	tw(p,t,{Transparency=1,Size=Vector3.new(.08,.08,d)})
	Debris:AddItem(p,t+.1)
end

local function burst(pos,c,count,power)
	for i=1,count do
		local dir=Vector3.new(math.random()-.5,math.random()-.15,math.random()-.5)
		if dir.Magnitude<.1 then dir=Vector3.yAxis end
		dir=dir.Unit
		line(pos,pos+dir*math.random(5,power),math.random(4,14)/20,c,math.random(20,55)/100)
	end
end

local function glitch(pos,c,count,range)
	range=range or 10
	for i=1,count do
		local p=fxpart(CFrame.new(pos+Vector3.new(math.random(-range,range),math.random(-math.floor(range/2),range),math.random(-range,range))),Vector3.new(math.random(1,9)/4,math.random(1,9)/4,math.random(1,9)/4),c,.05)
		tw(p,math.random(15,50)/100,{Transparency=1,CFrame=p.CFrame*CFrame.new(math.random(-range,range),math.random(-range,range),math.random(-range,range))})
		Debris:AddItem(p,.7)
	end
end

local function coreFlash(pos,color,size,duration)
	local p=fxpart(CFrame.new(pos),Vector3.one*2,color,.12,Enum.PartType.Ball,Enum.Material.Neon)
	tw(p,duration,{Size=Vector3.one*size,Transparency=1},Enum.EasingStyle.Exponential)
	Debris:AddItem(p,duration+.1)
	return p
end

local function shockDisc(pos,color,size,duration)
	local p=fxpart(CFrame.new(pos)*CFrame.Angles(0,0,math.pi/2),Vector3.new(.7,3,3),color,.15,Enum.PartType.Cylinder,Enum.Material.Neon)
	tw(p,duration,{Size=Vector3.new(.08,size,size),Transparency=1},Enum.EasingStyle.Quint)
	Debris:AddItem(p,duration+.1)
end

local function ripple(pos,color,startSize,endSize,duration)
	local p=fxpart(CFrame.new(pos),Vector3.one*startSize,color,0.999999,Enum.PartType.Ball,Enum.Material.Glass)
	p.Reflectance=.12
	tw(p,duration,{Size=Vector3.one*endSize,Transparency=1},Enum.EasingStyle.Exponential)
	Debris:AddItem(p,duration+.1)
	return p
end

local function polygon(pos,radius,sides,color,height,duration,spin)
	local pts={}
	for i=1,sides do
		local a=((i-1)/sides)*math.pi*2
		pts[i]=pos+Vector3.new(math.cos(a)*radius,height or 0,math.sin(a)*radius)
	end
	for i=1,sides do line(pts[i],pts[(i%sides)+1],.28,color,duration) end
	if spin then
		for _,p in ipairs(pts) do line(p,pos+Vector3.new(0,height or 0,0),.16,color,duration) end
	end
end

local function cage(pos,radius,color,duration)
	for h=-8,16,8 do polygon(pos,radius,6,color,h,duration,true) end
	for i=1,6 do
		local a=(i/6)*math.pi*2
		line(pos+Vector3.new(math.cos(a)*radius,-8,math.sin(a)*radius),pos+Vector3.new(math.cos(a)*radius,16,math.sin(a)*radius),.3,color,duration)
	end
end

local function crescent(pos,look,c,scale)
	for i=-4,4 do
		local dir=(CFrame.lookAt(Vector3.zero,look)*CFrame.Angles(0,math.rad(i*13),0)).LookVector
		line(pos+dir*2,pos+dir*(scale or 18),.32,c,.48)
	end
end

local function starfall(aim,c,count,height,spread)
	for i=1,(count or 5) do
		local top=aim+Vector3.new(math.random(-spread,spread),height+math.random(0,25),math.random(-spread,spread))
		line(top,aim+Vector3.new(math.random(-5,5),0,math.random(-5,5)),.45,c,.45)
	end
end

local function crimson(d)
	local c=palette[1] local a=d.Aim local o=d.Origin local k=d.Key
	coreFlash(a,c[1],k=="F" and 34 or k=="V" and 24 or 13,.45)
	shockDisc(a,c[3],k=="F" and 70 or k=="V" and 48 or 28,.65)
	if k=="Z" then
		line(o,a,.75,c[1],.28) burst(a,c[1],14,18) ring(a,6,c[3],.4)
	elseif k=="X" then
		for i=-3,3 do
			local off=Vector3.new(i*3,10+math.abs(i)*2,0)
			line(o+off,a-off*.2,.5,c[(math.abs(i)%2)+1],.5)
		end
		burst(a,c[1],24,28)
	elseif k=="C" then
		for i=1,12 do
			local ang=i/12*math.pi*2
			local p=a+Vector3.new(math.cos(ang)*20,14+math.sin(i*2)*6,math.sin(ang)*20)
			line(p,a,.5,c[1],.7)
		end
		for i=1,3 do ring(a,7+i*5,c[i],.75) end
	elseif k=="V" then
		cage(a,20,c[1],1.1)
		for i=1,18 do
			local ang=i/18*math.pi*2
			line(a+Vector3.new(math.cos(ang)*28,30,math.sin(ang)*28),a,.7,c[1],.9)
		end
		burst(a,c[3],40,42)
	elseif k=="F" then
		for r=8,40,8 do ring(a,r,c[(r/8-1)%3+1],1.1) end
		cage(a,30,c[1],1.25)
		starfall(a,c[1],14,70,35)
		burst(a,c[3],60,55)
	end
end

local function clair(d)
	local c=palette[2] local a=d.Aim local o=d.Origin local k=d.Key
	coreFlash(a,c[1],k=="F" and 38 or k=="V" and 26 or 14,.55)
	shockDisc(a,c[2],k=="F" and 76 or k=="V" and 52 or 30,.75)
	local look=(a-o).Magnitude>.01 and (a-o).Unit or Vector3.zAxis
	if k=="Z" then
		crescent(o,look,c[1],22) ring(a,7,c[2],.55)
	elseif k=="X" then
		starfall(a,c[1],7,55,18) ring(a,11,c[2],.65)
	elseif k=="C" then
		for i=1,5 do
			local ang=i/5*math.pi*2
			local p=a+Vector3.new(math.cos(ang)*18,8,math.sin(ang)*18)
			crescent(p,(a-p).Unit,c[(i%3)+1],18)
		end
		ring(a,17,c[1],.8)
	elseif k=="V" then
		starfall(a,c[1],12,75,30)
		for i=1,4 do ring(a,8+i*7,c[(i%3)+1],1+i*.08) end
		crescent(a,look,c[3],35)
	elseif k=="F" then
		starfall(a,c[1],20,100,45)
		for i=1,7 do ring(a,i*7,c[(i%3)+1],1.25) end
		for i=1,10 do
			local ang=i/10*math.pi*2
			crescent(a+Vector3.new(math.cos(ang)*28,6,math.sin(ang)*28),(a-(a+Vector3.new(math.cos(ang)*28,6,math.sin(ang)*28))).Unit,c[1],28)
		end
	end
end

local function geometry(d)
	local c=palette[3] local a=d.Aim local o=d.Origin local k=d.Key
	coreFlash(a,c[2],k=="F" and 36 or k=="V" and 25 or 12,.5)
	shockDisc(a,c[1],k=="F" and 72 or k=="V" and 50 or 28,.7)
	if k=="Z" then
		polygon(a,10,4,c[1],0,.55,true)
		line(o,a,.25,c[2],.45)
	elseif k=="X" then
		for sides=3,8 do polygon(a,sides*2,sides,c[(sides%3)+1],(sides-3)*2,.75,true) end
	elseif k=="C" then
		cage(a,18,c[2],1)
		polygon(a,27,8,c[1],4,1,true)
	elseif k=="V" then
		for i=1,9 do
			local r=6+i*4
			polygon(a,r,3+(i%6),c[(i%3)+1],math.sin(i)*8,1.15,true)
		end
		burst(a,c[1],28,35)
	elseif k=="F" then
		for i=1,14 do
			local r=5+i*3
			polygon(a,r,3+(i%7),c[(i%3)+1],(i-7)*2,1.35,true)
		end
		cage(a,38,c[1],1.4)
		burst(a,c[2],55,50)
	end
end


local TIMEWARP_IMAGES={112147826492721,87137835272435,15349122896,4998267428}

local function rainbowColor(t)
	return Color3.fromHSV(t%1,1,1)
end

local function imageEmitter(parent,texture,rate,lifetime,speed,size)
	local e=Instance.new("ParticleEmitter")
	e.Texture="rbxassetid://"..tostring(texture)
	e.Rate=rate
	e.Lifetime=NumberRange.new(lifetime*.75,lifetime*1.2)
	e.Speed=NumberRange.new(speed*.5,speed)
	e.SpreadAngle=Vector2.new(180,180)
	e.Rotation=NumberRange.new(0,360)
	e.RotSpeed=NumberRange.new(-240,240)
	e.LightEmission=1
	e.LightInfluence=0
	e.Drag=1
	e.Size=NumberSequence.new({
		NumberSequenceKeypoint.new(0,size*.15),
		NumberSequenceKeypoint.new(.2,size),
		NumberSequenceKeypoint.new(.8,size*.65),
		NumberSequenceKeypoint.new(1,0)
	})
	e.Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0,1),
		NumberSequenceKeypoint.new(.08,.05),
		NumberSequenceKeypoint.new(.8,.2),
		NumberSequenceKeypoint.new(1,1)
	})
	e.Color=ColorSequence.new({
		ColorSequenceKeypoint.new(0,Color3.fromHSV(math.random(),1,1)),
		ColorSequenceKeypoint.new(.25,Color3.fromHSV(math.random(),1,1)),
		ColorSequenceKeypoint.new(.5,Color3.fromHSV(math.random(),1,1)),
		ColorSequenceKeypoint.new(.75,Color3.fromHSV(math.random(),1,1)),
		ColorSequenceKeypoint.new(1,Color3.fromHSV(math.random(),1,1))
	})
	e.Parent=parent
	return e
end

local function timewarpNuke(pos)
	local anchor=fxpart(CFrame.new(pos),Vector3.new(1,1,1),Color3.new(1,1,1),1,Enum.PartType.Ball,Enum.Material.Neon)
	local emitters={}
	for i,id in ipairs(TIMEWARP_IMAGES) do
		local e=imageEmitter(anchor,id,32,1.8+i*.15,34+i*7,5+i*1.5)
		emitters[#emitters+1]=e
	end

	for i=1,28 do
		task.delay((i-1)*.045,function()
			local hue=(i/28+os.clock()*.1)%1
			local col=rainbowColor(hue)
			ripple(pos,col,2+i*.8,28+i*5,1.05+i*.025)
			if i%2==0 then ring(pos,10+i*3,col,1.15) end
			if i%3==0 then shockDisc(pos,rainbowColor(hue+.2),20+i*4,.9) end
		end)
	end

	for i=1,36 do
		task.delay(math.random()*1.25,function()
			local ang=math.random()*math.pi*2
			local rad=math.random(12,72)
			local h=math.random(-30,55)
			local p=pos+Vector3.new(math.cos(ang)*rad,h,math.sin(ang)*rad)
			local col=rainbowColor(math.random())
			line(p,pos,math.random(2,8)/10,col,.55+math.random()*.7)
			ripple(p,col,1,math.random(8,24),.45+math.random()*.5)
		end)
	end

	for i=1,18 do
		task.delay(i*.07,function()
			local hue=(i/18)%1
			local col=rainbowColor(hue)
			local radius=8+i*3.5
			for j=1,6 do
				local ang=j/6*math.pi*2+i*.45
				local p=pos+Vector3.new(math.cos(ang)*radius,math.sin(i*.8)*12,math.sin(ang)*radius)
				line(p,pos,.22,col,.6)
			end
		end)
	end

	task.delay(1.25,function()
		coreFlash(pos,Color3.new(1,1,1),90,.75)
		for i=1,12 do
			local col=rainbowColor(i/12)
			ripple(pos,col,5+i*2,75+i*9,1.25)
			ring(pos,25+i*8,col,1.15)
		end
		burst(pos,Color3.new(1,1,1),110,95)
		glitch(pos,Color3.new(1,1,1),130,70)
	end)

	task.delay(2.4,function()
		for _,e in ipairs(emitters) do e.Enabled=false end
		Debris:AddItem(anchor,3)
	end)
end

local function reality(d)
	local c=palette[4] local a=d.Aim local o=d.Origin local k=d.Key
	coreFlash(a,c[2],k=="F" and 42 or k=="V" and 30 or 15,.6)
	shockDisc(a,c[1],k=="F" and 82 or k=="V" and 58 or 34,.8)
	if k=="Z" then
		for i=1,4 do ripple(a,c[(i%3)+1],2+i,15+i*6,.55+i*.08) end
	elseif k=="X" then
		for i=1,7 do
			local p=a+Vector3.new(math.random(-12,12),math.random(-6,12),math.random(-12,12))
			ripple(p,c[(i%3)+1],2,12+math.random(3,10),.7)
		end
		glitch(a,c[2],22,12)
	elseif k=="C" then
		line(o,a,.6,c[1],.6)
		for i=1,10 do
			local p=a+Vector3.new(math.random(-22,22),math.random(-12,18),math.random(-22,22))
			ripple(p,c[(i%3)+1],1,18,.8)
			line(p,a,.18,c[1],.65)
		end
	elseif k=="V" then
		for i=1,12 do ripple(a,c[(i%3)+1],i*1.5,25+i*4,.8+i*.04) end
		glitch(a,c[2],55,25)
		for i=1,8 do
			local ang=i/8*math.pi*2
			line(a+Vector3.new(math.cos(ang)*35,math.random(-15,25),math.sin(ang)*35),a,.45,c[1],1)
		end
	elseif k=="F" then
		timewarpNuke(a)
	end
end

local function superMT1(d)
	local a=d.Aim
	coreFlash(a,Color3.new(1,1,1),105,.9)
	for i=1,16 do
		local col=rainbowColor(i/16)
		task.delay((i-1)*.045,function()
			ripple(a,col,4+i*1.5,45+i*5,1.1+i*.025)
			if i%2==0 then ring(a,12+i*5,col,1.25) end
		end)
	end
	cage(a,42,palette[1][1],1.7)
	starfall(a,palette[2][1],24,110,52)
	for i=1,12 do
		local r=8+i*4
		polygon(a,r,3+(i%7),palette[3][(i%3)+1],(i-6)*2,1.55,true)
	end
	for i=1,24 do
		task.delay(i*.055,function()
			local ang=i/24*math.pi*2
			local p=a+Vector3.new(math.cos(ang)*(22+i*1.5),math.sin(i*.7)*18,math.sin(ang)*(22+i*1.5))
			line(p,a,.35,rainbowColor(i/24),.8)
			if i%3==0 then glitch(p,palette[4][2],16,7) end
		end)
	end
	task.delay(1.05,function() timewarpNuke(a) end)
	task.delay(1.85,function()
		coreFlash(a,Color3.new(1,1,1),140,.8)
		burst(a,Color3.new(1,1,1),150,120)
		for i=1,12 do
			local col=rainbowColor(i/12)
			ring(a,30+i*9,col,1.35)
			ripple(a,col,8+i*2,85+i*8,1.4)
		end
	end)
end

local function variantFX(d)
    if not d or typeof(d.Aim)~="Vector3" then return end
    local mode=d.Mode or 1
    local col=variantPalette[mode] or variantPalette[9]
    local p=d.Aim
    local o=d.Origin or p
    local key=d.Key
    local power=({Z=1,X=2,C=3,V=4,F=5,B=2,N=3,M=4,G=6})[key] or 2
    local count=math.min(18,4+power*2+(d.Chain and 3 or 0))
    if mode==1 then
        for i=1,count do
            local a=i*2.39996
            line(p+Vector3.new(math.cos(a)*15,11,math.sin(a)*15),p,.12+power*.06,i%2==0 and col[1] or col[3],.48)
        end
        ripple(p,col[1],3,13+power*4,.62)
    elseif mode==2 then
        starfall(p,col[1],count,38+power*6,10+power*3)
        ring(p,7+power*4,col[2],.85)
    elseif mode==3 then
        for i=1,math.min(6,3+power) do polygon(p,6+i*3,4+i,col[(i%3)+1],i*.25,.68,true) end
        glitch(p,col[1],count,13)
    elseif mode==4 then
        for i=1,math.min(6,2+power) do
            local pos=p+Vector3.new(i%2==0 and -i*3 or i*3,i*1.2,i*1.5)
            line(o,pos,.16,col[(i%3)+1],.38)
            ripple(pos,col[1],2,15+i*2,.5)
        end
    elseif mode==5 then
        for i=1,count do
            local a=i*2.39996
            local dest=p+Vector3.new(math.cos(a)*math.min(31,i*2),math.sin(i)*4,math.sin(a)*math.min(31,i*2))
            line(i%2==0 and o or p,dest,.07+power*.02,col[(i%3)+1],.25)
        end
        coreFlash(p,col[1],power*6,.20)
    elseif mode==6 then
        starfall(p,col[2],count,60,13+power*3)
        for i=1,power+2 do line(p+Vector3.new(0,30+i*2,0),p+Vector3.new(i*2,0,-i*2),.13,col[1],.5) end
    elseif mode==7 then
        for i=count,1,-1 do ring(p,3+i*2,col[(i%3)+1],.4+i*.015) end
        shockDisc(p,col[2],power*10,.45)
    elseif mode==8 then
        glitch(p,col[2],count*2,8+power*3)
        for i=1,power+2 do ripple(p,col[1],i*4,15+i*4,.5) end
    elseif mode==9 then
        for i=1,count do
            local a=i*2.39996
            local radius=3+math.sqrt(i)*(power+3)
            local point=p+Vector3.new(math.cos(a)*radius,math.sin(i*2)*radius*.4,math.sin(a)*radius)
            line(p,point,.10,col[(i%3)+1],.58)
            if i%3==0 then coreFlash(point,col[2],2.3,.31) end
        end
        ripple(p,col[1],3,15+power*5,.62)
    end
    if d.Chain then coreFlash(p,col[3],power*4,.24) end
end
local function variantImpactFX(d)
    if not d or typeof(d.Position)~="Vector3" then return end
    local col=variantPalette[d.Mode] or variantPalette[9]
    local p=d.Position
    local r=math.clamp(d.Radius or 10,3,66)
    if d.Infection then
        for i=1,5 do
            local a=i*1.256637
            local to=p+Vector3.new(math.cos(a)*r,math.sin(i)*r*.45,math.sin(a)*r)
            line(p,to,.12,col[i%3+1],.48)
        end
    elseif d.Mode==5 then
        for i=1,6 do line(p+Vector3.new(math.cos(i)*r,math.sin(i*2)*r*.35,math.sin(i)*r),p,.09,col[i%3+1],.22) end
    elseif d.Mode==8 then
        glitch(p,col[1],d.Ultimate and 30 or 11,r)
    elseif d.Mode==7 then
        for i=1,4 do ring(p,r*(1+i*.3),col[(i%3)+1],.45) end
    else
        burst(p,col[1],d.Ultimate and 12 or 5,r)
        ripple(p,col[2],2,r*1.2,.4)
    end
end

local genericNewMode

local function fusionCast(d)
    if d.Variant then variantFX(d) return end
	if d.Key=="G" or d.Mode==0 then return
	elseif d.Mode==1 then crimson(d)
	elseif d.Mode==2 then clair(d)
	elseif d.Mode==3 then geometry(d)
	elseif d.Mode==4 then reality(d)
	else genericNewMode(d) end
end

genericNewMode=function(d)
	local c=palette[d.Mode] or palette[1]
	local a=d.Aim or d.Origin or Vector3.zero
	local o=d.Origin or a
	local k=d.Key
	if d.Mode==5 then
		coreFlash(a,c[1],k=="F" and 50 or 18,.5)
		for i=1,(k=="F" and 14 or 6) do
			local ang=(i/(k=="F" and 14 or 6))*math.pi*2
			local p=a+Vector3.new(math.cos(ang)*(8+i*1.5),math.sin(i*.8)*5,math.sin(ang)*(8+i*1.5))
			line(o,p,.16+(i%3)*.05,c[(i%3)+1],.65)
			line(p,a,.12,c[((i+1)%3)+1],.7)
			if i%2==0 then ripple(p,c[1],1,10+i,.6) end
		end
		ring(a,k=="F" and 48 or 22,c[1],.9)
	elseif d.Mode==6 then
		local count=k=="F" and 22 or k=="V" and 14 or 8
		coreFlash(a,c[1],k=="F" and 58 or 22,.45)
		for i=1,count do
			local ang=math.random()*math.pi*2
			local rad=math.random(8,k=="F" and 55 or 28)
			local p=a+Vector3.new(math.cos(ang)*rad,math.random(-8,18),math.sin(ang)*rad)
			line(i%3==0 and o or a,p,math.random(10,35)/100,c[(i%3)+1],.35+math.random()*.45)
			if i%4==0 then ripple(p,c[1],1,12,.45) end
		end
	elseif d.Mode==7 then
		local radius=k=="F" and 70 or k=="V" and 42 or 24
		coreFlash(a,c[3],radius*.5,.6)
		for i=1,12 do
			ring(a,4+i*(radius/12),c[(i%3)+1],.9+i*.025)
			if i%2==0 then
				local ang=i/12*math.pi*2
				local p=a+Vector3.new(math.cos(ang)*radius,math.sin(i)*12,math.sin(ang)*radius)
				line(p,a,.2,c[3],.8)
			end
		end
		glitch(a,c[2],k=="F" and 80 or 30,k=="F" and 38 or 14)
	elseif d.Mode==8 then
		local count=k=="F" and 18 or 8
		coreFlash(a,c[1],k=="F" and 48 or 16,.35)
		for i=1,count do
			local p=a+Vector3.new(math.random(-30,30),math.random(-18,18),math.random(-30,30))
			local q=(p+a)*.5
			line(p,q,.12,c[(i%3)+1],.35)
			task.delay(.14,function()
				ripple(q,c[2],1,8+math.random(4,16),.4)
			end)
		end
		ring(a,k=="F" and 62 or 26,c[2],.55)
	end
end

local BeamFolder=Instance.new("Folder")
BeamFolder.Name="CrimsonBeam"
BeamFolder.Parent=FX
local BeamData=nil
local BeamClock=0
local BeamSegments={}

local function clearBeam()
    BeamData=nil
    for _,part in ipairs(BeamSegments) do
        if part.Parent then part:Destroy() end
    end
    table.clear(BeamSegments)
end

local function beamSegment(index,a,b,thickness,color)
    local d=b-a
    if d.Magnitude<.05 then return index end
    local part=BeamSegments[index]
    if not part or not part.Parent then
        part=Instance.new("Part")
        part.Name="PooledCrimsonLightning"
        part.Anchored=true
        part.CanCollide=false
        part.CanTouch=false
        part.CanQuery=false
        part.CastShadow=false
        part.Material=Enum.Material.Neon
        part:SetAttribute("MEFEEffect",true)
        part.Parent=BeamFolder
        BeamSegments[index]=part
    end
    part.CFrame=CFrame.lookAt((a+b)/2,b)
    part.Size=Vector3.new(thickness,thickness,d.Magnitude)
    part.Color=color
    part.Transparency=.05
    return index+1
end

RS.RenderStepped:Connect(function(dt)
    if not BeamData then return end
    BeamClock=BeamClock+dt
    if BeamClock<.055 then return end
    BeamClock=0
    local a=BeamData.Origin
    local b=BeamData.Aim
    if typeof(a)~="Vector3" or typeof(b)~="Vector3" then return end
    local rng=Random.new(math.floor(os.clock()*90)%1000000)
    local points={a}
    local dist=(b-a).Magnitude
    local segs=math.clamp(math.floor(dist/6),6,20)
    for i=1,segs-1 do
        local t=i/segs
        local base=a:Lerp(b,t)
        local fall=math.sin(t*math.pi)
        local off=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-1,1),rng:NextNumber(-1,1))*fall*(1.2+dist*.015)
        points[#points+1]=base+off
    end
    points[#points+1]=b
    local index=1
    for i=1,#points-1 do
        index=beamSegment(index,points[i],points[i+1],.22+(i%3)*.07,Color3.fromRGB(255,15,35))
        if i%4==0 then
            local point=points[i]
            local fork=point+Vector3.new(rng:NextNumber(-7,7),rng:NextNumber(-5,7),rng:NextNumber(-7,7))
            index=beamSegment(index,point,fork,.08,Color3.fromRGB(150,0,20))
        end
    end
    for i=index,#BeamSegments do
        local part=BeamSegments[i]
        if part and part.Parent then part.Transparency=1 end
    end
end)

local function finisher(d)
	local origin=d.Origin or Vector3.zero
	for i=1,5 do ripple(origin,palette[4][(i%3)+1],3+i*2,18+i*7,.65+i*.08) end
	ring(origin,12,Color3.new(1,1,1),.8)
	ring(origin,24,Color3.fromRGB(255,35,65),1)
	for _,info in ipairs(d.Parts or {}) do
		local cf=info.CF local sz=info.Size
		if typeof(cf)=="CFrame" and typeof(sz)=="Vector3" then
			local shard=fxpart(cf,sz,Color3.fromRGB(235,245,255),.04,nil,Enum.Material.Glass)
			local dir=cf.Position-origin
			if dir.Magnitude<.1 then dir=Vector3.new(math.random()-.5,1,math.random()-.5) end
			local goal=cf+dir.Unit*math.random(10,25)+Vector3.new(0,math.random(7,22),0)
			tw(shard,.9,{CFrame=goal*CFrame.Angles(math.random()*4,math.random()*4,math.random()*4),Size=sz*.03,Transparency=1},Enum.EasingStyle.Exponential)
			Debris:AddItem(shard,1)
		end
	end
	burst(origin,Color3.new(1,1,1),48,48)
	glitch(origin,Color3.fromRGB(255,35,65),40,25)
end

local modeGui=Instance.new("ScreenGui")
modeGui.Name="VexModeHUD" modeGui.ResetOnSpawn=false
local fxPlayerGui=LP:WaitForChild("PlayerGui")
local oldFxHud=fxPlayerGui:FindFirstChild("VexModeHUD")
if oldFxHud then oldFxHud:Destroy() end
modeGui.Parent=fxPlayerGui
local modeLabel=Instance.new("TextLabel")
modeLabel.AnchorPoint=Vector2.new(.5,1) modeLabel.Position=UDim2.new(.5,0,1,-30) modeLabel.Size=UDim2.new(0,520,0,42)
modeLabel.BackgroundTransparency=1 modeLabel.TextScaled=true modeLabel.Font=Enum.Font.Code modeLabel.TextStrokeTransparency=.25
modeLabel.TextColor3=palette[1][1] modeLabel.Text="MODE 1 // CRIMSON FURY" modeLabel.Parent=modeGui

local function partDerender(d)
	if not d or typeof(d.CF)~="CFrame" or typeof(d.Size)~="Vector3" then return end
	local rng=Random.new(d.Seed or 1)
	local cf,size=d.CF,d.Size
	local ghost=fxpart(cf,size,Color3.new(1,1,1),.05,nil,Enum.Material.Glass)
	ghost.Reflectance=.18
	local slices=math.clamp(math.ceil((size.X+size.Y+size.Z)*1.5),8,26)
	for i=1,slices do
		local axis=i%3
		local ss
		if axis==0 then ss=Vector3.new(math.max(.035,size.X/slices),size.Y,size.Z)
		elseif axis==1 then ss=Vector3.new(size.X,math.max(.035,size.Y/slices),size.Z)
		else ss=Vector3.new(size.X,size.Y,math.max(.035,size.Z/slices)) end
		local off=Vector3.new(rng:NextNumber(-size.X*.48,size.X*.48),rng:NextNumber(-size.Y*.48,size.Y*.48),rng:NextNumber(-size.Z*.48,size.Z*.48))
		local p=fxpart(cf*CFrame.new(off),ss,Color3.fromHSV(rng:NextNumber(),.8,1),.08,nil,Enum.Material.Neon)
		local dir=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-.35,1),rng:NextNumber(-1,1))
		if dir.Magnitude<.01 then dir=Vector3.yAxis end
		tw(p,.28+rng:NextNumber(0,.22),{CFrame=p.CFrame+CFrame.new(dir.Unit*rng:NextNumber(2,8)).Position,Size=Vector3.new(math.max(.01,ss.X*.02),math.max(.01,ss.Y*.02),math.max(.01,ss.Z*.02)),Transparency=1},Enum.EasingStyle.Exponential)
		Debris:AddItem(p,.6)
	end
	for i=1,5 do
		task.delay((i-1)*.045,function()
			if ghost.Parent then
				ghost.Color=Color3.fromHSV(rng:NextNumber(),.65,1)
				ghost.Transparency=(i%2==0) and .75 or .12
				ghost.CFrame=cf*CFrame.new(rng:NextNumber(-.18,.18),rng:NextNumber(-.18,.18),rng:NextNumber(-.18,.18))
			end
		end)
	end
	tw(ghost,.32,{Size=Vector3.new(math.max(.01,size.X*.015),math.max(.01,size.Y*.015),math.max(.01,size.Z*.015)),Transparency=1},Enum.EasingStyle.Exponential)
	Debris:AddItem(ghost,.45)
end

local EXTRA_FACE_ROTATIONS={
    [Enum.NormalId.Left]=CFrame.Angles(0,math.pi/2,0),
    [Enum.NormalId.Right]=CFrame.Angles(0,-math.pi/2,0),
    [Enum.NormalId.Top]=CFrame.Angles(0,math.pi/2,math.pi/2),
    [Enum.NormalId.Bottom]=CFrame.Angles(0,math.pi/2,-math.pi/2),
    [Enum.NormalId.Front]=CFrame.identity,
    [Enum.NormalId.Back]=CFrame.Angles(0,math.pi,0)
}

local EXTRA_MESH_CACHE={}
local function extraPart(info)
    local part
    if type(info.MeshId)=="string" and #info.MeshId>0 then
        if not EXTRA_MESH_CACHE[info.MeshId] then
            local ok,result=pcall(function()
                return game:GetService("InsertService"):CreateMeshPartAsync(info.MeshId,Enum.CollisionFidelity.Box,Enum.RenderFidelity.Performance)
            end)
            if ok and result then EXTRA_MESH_CACHE[info.MeshId]=result end
        end
        if EXTRA_MESH_CACHE[info.MeshId] then
            part=EXTRA_MESH_CACHE[info.MeshId]:Clone()
        end
    end
    if not part then part=Instance.new("Part") end
    part.Anchored=true
    part.CanCollide=false
    part.CanTouch=false
    part.CanQuery=false
    part:SetAttribute("MEFEEffect",true)
    part.CastShadow=false
    part.Material=Enum.Material.Neon
    part.Size=info.Size
    part.CFrame=info.CF
    part.Color=info.Color or Color3.new(1,1,1)
    part.Transparency=math.clamp(info.Transparency or 0,0,.9)
    part.Parent=FX
    return part
end

local function extraLightning(a,b,mode,resolution,offset,size,speed,secondary)
    if typeof(a)~="Vector3" or typeof(b)~="Vector3" then return end
    local delta=b-a
    if delta.Magnitude<.15 then return end
    local colors=palette[mode] or palette[1]
    local c=secondary and colors[2] or colors[1]
    local rng=Random.new(math.floor(os.clock()*1e6)%100000000)
    local segments=math.clamp(UIS.TouchEnabled and math.floor((resolution or 12)*.7) or resolution or 12,3,28)
    local path=CFrame.lookAt(a,b).Rotation
    local points={a}
    for i=1,segments-1 do
        local t=i/segments
        local jitter=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-1,1),rng:NextNumber(-1,1))*((offset or 2)*math.sin(math.pi*t))
        points[#points+1]=a:Lerp(b,t)+path:VectorToWorldSpace(jitter)
    end
    points[#points+1]=b
    for i=1,#points-1 do
        local first,last=points[i],points[i+1]
        local length=(last-first).Magnitude
        if length>.04 then
            local part=fxpart(CFrame.lookAt((first+last)/2,last),Vector3.new(size or .36,size or .36,length),c,1)
            task.delay((i-1)*(.07/(speed or 3)),function()
                if part.Parent then
                    tw(part,.045,{Transparency=0},Enum.EasingStyle.Linear)
                    tw(part,.5,{Size=Vector3.new(.045,.045,length),Color=Color3.new(0,0,0)},Enum.EasingStyle.Linear)
                end
            end)
            Debris:AddItem(part,1.1)
        end
    end
end

local function extraShatter(info,mode,rng)
    if typeof(info.CF)~="CFrame" or typeof(info.Size)~="Vector3" then return end
    local colors=palette[mode] or palette[1]
    local size=info.Size
    local cf=info.CF
    for _,face in ipairs(Enum.NormalId:GetEnumItems()) do
        local normal=Vector3.FromNormalId(face)
        for i=1,2 do
            local inversion=math.pi*(i-1)
            local rotation=EXTRA_FACE_ROTATIONS[face]*CFrame.Angles(0,inversion,inversion)
            local faceCF=cf*CFrame.new(normal*size/2)*CFrame.Angles(0,math.pi/2,0)
            local sizeY,sizeZ=1,1
            if normal.Y==0 then
                sizeY=size.Y
                sizeZ=size.X
            else
                sizeY=size.X
            end
            if normal.Z==0 then sizeZ=size.Z end
            local wedgeSize=Vector3.new(.1,math.max(.06,sizeY),math.max(.06,sizeZ))
            local wedge=Instance.new("WedgePart")
            wedge.Anchored=true
            wedge.CanCollide=false
            wedge.CanTouch=false
            wedge.CanQuery=false
            wedge:SetAttribute("MEFEEffect",true)
            wedge.CastShadow=false
            wedge.Size=wedgeSize
            wedge.CFrame=faceCF*rotation*CFrame.new(-wedgeSize.X/2,0,0)
            wedge.Material=info.Material or Enum.Material.Neon
            wedge.Color=(info.Color or colors[1]):Lerp(colors[(i%2)+1],.42)
            wedge.Transparency=math.clamp(info.Transparency or 0,0,.9)
            wedge.Parent=FX
            local direction=rng:NextUnitVector()
            local distance=rng:NextNumber(2.5,10)
            local duration=rng:NextNumber(.43,1.15)
            local tumble=CFrame.Angles(rng:NextNumber(-math.pi,math.pi),rng:NextNumber(-math.pi,math.pi),rng:NextNumber(-math.pi,math.pi))
            task.delay(.025,function()
                if wedge.Parent then
                    tw(wedge,duration,{
                        CFrame=wedge.CFrame*tumble+direction*distance,
                        Size=Vector3.new(.01,.01,.01),
                        Transparency=1
                    },Enum.EasingStyle.Exponential)
                end
            end)
            Debris:AddItem(wedge,duration+.15)
        end
    end
end

local function extraKillEffect(info,mode,rng)
    if typeof(info.CF)~="CFrame" or typeof(info.Size)~="Vector3" then return end
    local colors=palette[mode] or palette[1]
    local clone=extraPart(info)
    local start=info.CF
    local direction=rng:NextUnitVector()
    local rotation=CFrame.Angles(rng:NextNumber(-math.pi,math.pi),rng:NextNumber(-math.pi,math.pi),rng:NextNumber(-math.pi,math.pi))
    local duration=rng:NextNumber(1.2,2)
    local dest=start*rotation+CFrame.new(direction*rng:NextNumber(8,20)).Position
    clone.Color=colors[rng:NextInteger(1,2)]
    clone.Material=Enum.Material.Neon
    tw(clone,duration,{CFrame=dest,Size=Vector3.new(.02,.02,.02),Color=Color3.new(0,0,0),Transparency=1},Enum.EasingStyle.Exponential)
    Debris:AddItem(clone,duration+.2)
    local smallCount=math.clamp(math.floor(info.Size.Magnitude*1.1),2,UIS.TouchEnabled and 4 or 7)
    for j=1,smallCount do
        local sz=math.max(.09,math.min(info.Size.X,info.Size.Y,info.Size.Z)*rng:NextNumber(.08,.28))
        local spark=fxpart(start*CFrame.new(rng:NextNumber(-.5,.5),rng:NextNumber(-.5,.5),rng:NextNumber(-.5,.5)),Vector3.one*sz,colors[(j%2)+1],.04)
        local push=rng:NextUnitVector()*rng:NextNumber(5,16)
        tw(spark,duration*rng:NextNumber(.55,.95),{CFrame=spark.CFrame*CFrame.Angles(rng:NextNumber(-2,2),rng:NextNumber(-2,2),rng:NextNumber(-2,2))+push,Size=Vector3.one*.01,Color=Color3.new(0,0,0),Transparency=1},Enum.EasingStyle.Exponential)
        Debris:AddItem(spark,duration+.1)
    end
end

local function extraFinisher(d)
    if not d or type(d.Parts)~="table" then return end
    local kind=d.Kind
    local mode=d.Mode or 1
    local colors=palette[mode] or palette[1]
    local rng=Random.new(d.Seed or math.random(1,10000000))
    if #d.Parts==0 then return end
    local origin=d.Origin or d.Parts[1].CF.Position
    if kind=="SHATTER" then
        play3DSound(origin,4958429672,1.7,rng:NextNumber(.85,1.1),220)
        shockDisc(origin,colors[2],math.max(12,math.min(75,#d.Parts*4)),.38)
    else
        play3DSound(origin,4911987243,1.4,rng:NextNumber(.8,1.2),210)
        coreFlash(origin,colors[2],math.max(8,math.min(40,#d.Parts*3)),.38)
    end
    for i=1,math.min(#d.Parts,UIS.TouchEnabled and 10 or (kind=="SHATTER" and 14 or 18)) do
        local info=d.Parts[i]
        if kind=="SHATTER" then
            extraShatter(info,mode,rng)
        else
            extraKillEffect(info,mode,rng)
        end
    end
end

local function extraCastVisual(d)
    local mode=d.Mode or 1
    local colors=palette[mode] or palette[1]
    local pos=d.Aim or d.Origin or Vector3.zero
    local origin=d.Origin or pos
    if d.Type=="B_START" then
        play3DSound(origin,168586586,1.05,math.random(72,125)/100,210)
        task.delay(.14,function() play3DSound(origin,3177740633,.9,math.random(78,123)/100,190) end)
        if mode==2 or mode==6 then starfall(pos,colors[2],mode==6 and 7 or 4,42,14)
        elseif mode==3 then polygon(origin,8,8,colors[1],1,.55,true)
        elseif mode==4 then for i=1,4 do ripple(origin,colors[(i%3)+1],i,10+i*3,.55) end
        elseif mode==5 then for i=1,5 do line(origin,pos+Vector3.new((i-3)*3,0,0),.18,colors[(i%3)+1],.42) end
        elseif mode==7 then shockDisc(origin,colors[2],18,.47)
        elseif mode==8 then glitch(origin,colors[2],12,4)
        else burst(origin,colors[1],10,12) end
    elseif d.Type=="BOLT" then
        extraLightning(d.A,d.B,mode,d.Resolution,d.Offset,d.Size,d.Speed,false)
        extraLightning(d.A,d.B,mode,math.floor((d.Resolution or 12)*.65),d.Offset and d.Offset*.38 or 1.5,(d.Size or .3)*.55,(d.Speed or 3)*.8,true)
    elseif d.Type=="B_IMPACT" then
        local hit=d.Position or pos
        play3DSound(hit,3154301226,d.Final and 1.4 or 1.1,math.random(83,116)/100,205)
        if d.Final then play3DSound(hit,170278900,1.9,math.random(83,118)/100,250)
        else play3DSound(hit,5272307532,.8,math.random(82,127)/100,160) end
        coreFlash(hit,colors[1],d.Final and 34 or 12,d.Final and .58 or .36)
        coreFlash(hit,colors[2],d.Final and 23 or 8,d.Final and .55 or .33)
        if d.Final then
            shockDisc(hit,colors[2],45,.7)
            burst(hit,colors[1],12,34)
            for i=1,6 do extraLightning(hit,hit+Random.new((d.Seed or 8291)+i*379):NextUnitVector()*math.random(18,45),mode,7,2,.16,5,i%2==0) end
        else
            for i=1,2 do extraLightning(hit,hit+Random.new(i*85+math.floor(os.clock()*10)):NextUnitVector()*math.random(5,11),mode,5,1.2,.12,4,i%2==0) end
        end
    elseif d.Type=="N_CHARGE" then
        play3DSound(origin,4958429672,.9,.72,180)
        if mode==2 or mode==6 then starfall(pos,colors[1],6,50,12)
        elseif mode==3 or mode==5 then cage(pos,math.min(d.Radius or 15,22),colors[2],.65)
        elseif mode==7 then for i=1,3 do ring(pos,6+i*5,colors[(i%3)+1],.6) end
        elseif mode==8 then ripple(pos,colors[1],1,32,.58); glitch(pos,colors[3],20,14)
        else shockDisc(pos,colors[2],math.min(48,(d.Radius or 15)*2),.48) end
    elseif d.Type=="M_CHARGE" then
        play3DSound(origin,4911987243,.8,.7,190)
        if mode==1 then burst(pos,colors[1],12,19)
        elseif mode==2 then starfall(pos,colors[1],8,60,17)
        elseif mode==3 then for i=1,4 do polygon(pos,i*5,3+i*2,colors[(i%3)+1],i*.8,.7,true) end
        elseif mode==4 then for i=1,6 do ripple(pos,colors[(i%3)+1],i*2,30+i*3,.65) end
        elseif mode==5 then cage(pos,13,colors[2],.6)
        elseif mode==6 then starfall(pos,colors[2],10,70,20)
        elseif mode==7 then shockDisc(pos,colors[2],45,.75)
        else glitch(pos,colors[1],35,23) end
    elseif d.Type=="M_IMPACT" then
        local pos2=d.Position or pos
        play3DSound(pos2,170278900,1.1,.92,220)
        if mode==2 then starfall(pos2,colors[2],12,55,20)
        elseif mode==3 then for i=1,3 do polygon(pos2,i*6,4+i*2,colors[i],0,.8,true) end
        elseif mode==4 then glitch(pos2,colors[2],25,22)
        elseif mode==5 then for i=1,9 do local a=i*math.pi*2/9; line(pos2+Vector3.new(math.cos(a)*20,7,math.sin(a)*20),pos2,.25,colors[(i%3)+1],.7) end
        elseif mode==6 then starfall(pos2,colors[1],15,75,28)
        elseif mode==7 then for i=1,5 do ring(pos2,i*7,colors[(i%3)+1],.8) end
        elseif mode==8 then ripple(pos2,colors[1],2,55,.68)
        else burst(pos2,colors[1],22,34) end
        coreFlash(pos2,colors[2],math.min(55,d.Radius or 30),.65)
        shockDisc(pos2,colors[1],math.min(70,(d.Radius or 30)*1.8),.72)
    end
end

local function auraPlane(center,radius,color,height,angle,lifetime,width)
    local points={}
    for i=1,8 do
        local a=i*math.pi/4+angle
        points[i]=center+Vector3.new(math.cos(a)*radius,height,math.sin(a)*radius)
    end
    for i=1,8 do line(points[i],points[(i%8)+1],width or .22,color,lifetime) end
end

local function auraDiamond(center,size,color,angle,life)
    local offsets={Vector3.new(0,size,0),Vector3.new(size,0,0),Vector3.new(0,-size,0),Vector3.new(-size,0,0)}
    local orient=CFrame.Angles(angle*.37,angle,angle*.22)
    for i=1,4 do
        local p=center+orient:VectorToWorldSpace(offsets[i])
        local nextP=center+orient:VectorToWorldSpace(offsets[(i%4)+1])
        line(p,nextP,.13,color,life)
    end
end

local function makeAuraPrisms(center,radius,mode)
    local count=7
    local t0=os.clock()
    for i=1,count do
        local phase=i*math.pi*2/count+t0*.72
        local height=math.sin(phase*1.8)*2.0+1.4
        local wedgeA=Instance.new("WedgePart")
        wedgeA.Name="MEFERefractedPrism"
        wedgeA.Size=Vector3.new(1.15,2.15,.85)
        wedgeA.Material=Enum.Material.Glass
        wedgeA.Color=i%2==0 and Color3.fromRGB(215,249,255) or Color3.fromRGB(169,218,244)
        wedgeA.Reflectance=.42
        wedgeA.Transparency=.23
        wedgeA.Anchored=true
        wedgeA.CanCollide=false
        wedgeA.CanQuery=false
        wedgeA.CanTouch=false
        wedgeA.CastShadow=false
        wedgeA:SetAttribute("MEFEEffect",true)
        wedgeA.Parent=FX
        local wedgeB=wedgeA:Clone()
        wedgeB.Parent=FX
        local start=os.clock()
        local conn
        conn=RS.Heartbeat:Connect(function()
            if not FX.Parent or not wedgeA.Parent or not wedgeB.Parent then
                conn:Disconnect()
                return
            end
            local t=math.clamp((os.clock()-start)/.88,0,1)
            local spiral=phase+t*3.0
            local r=5.8*(1-t)+.9
            local pos=center+Vector3.new(math.cos(spiral)*r,height*(1-t*.7),math.sin(spiral)*r)
            local spin=CFrame.new(pos)*CFrame.Angles(t*6,spiral+t*8,t*4)
            wedgeA.CFrame=spin*CFrame.Angles(math.pi/2,0,0)
            wedgeB.CFrame=spin*CFrame.Angles(-math.pi/2,math.pi,0)
            local scale=math.max(.02,1-t^.8)
            local sz=Vector3.new(1.15,2.15,.85)*scale
            wedgeA.Size=sz
            wedgeB.Size=sz
            wedgeA.Transparency=.23+.77*t
            wedgeB.Transparency=.23+.77*t
            if t>=1 then
                conn:Disconnect()
                wedgeA:Destroy()
                wedgeB:Destroy()
            end
        end)
        Debris:AddItem(wedgeA,1.05)
        Debris:AddItem(wedgeB,1.05)
    end
end

local AuraRig=nil
local AuraVisible=true

local function auraObject(rig,name,size,color,material,transparency,kind)
    local p=Instance.new(kind or "Part")
    p.Name=name
    p.Size=size
    p.Color=color
    p.Material=material or Enum.Material.Neon
    p.Transparency=transparency or 0
    p.Anchored=true
    p.CanCollide=false
    p.CanTouch=false
    p.CanQuery=false
    p.CastShadow=false
    p:SetAttribute("MEFEEffect",true)
    p.Parent=rig.Folder
    rig.Parts[#rig.Parts+1]=p
    return p
end

local function auraBeam(p,a,b,width)
    local delta=b-a
    if delta.Magnitude<.001 then return end
    p.Size=Vector3.new(width,width,delta.Magnitude)
    p.CFrame=CFrame.lookAt((a+b)*.5,b)
end

local function auraRibbon(rig,moving,color,life,span)
    local a=Instance.new("Attachment")
    a.Position=Vector3.new(-span*.5,0,0)
    a.Parent=moving
    local b=Instance.new("Attachment")
    b.Position=Vector3.new(span*.5,0,0)
    b.Parent=moving
    local trail=Instance.new("Trail")
    trail.Attachment0=a
    trail.Attachment1=b
    trail.Color=ColorSequence.new(color)
    trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.18),NumberSequenceKeypoint.new(.55,.49),NumberSequenceKeypoint.new(1,1)})
    trail.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.8,.35),NumberSequenceKeypoint.new(1,0)})
    trail.FaceCamera=true
    trail.Lifetime=life
    trail.MinLength=.04
    trail.LightEmission=.8
    trail.LightInfluence=0
    trail.Parent=moving
    rig.Ribbons[#rig.Ribbons+1]=trail
    return trail
end

local function auraCurveBuild(rig,name,color,width,curve)
    local pa=auraObject(rig,name.."Origin",Vector3.new(.05,.05,.05),color,Enum.Material.Glass,1)
    local pb=auraObject(rig,name.."Destination",Vector3.new(.05,.05,.05),color,Enum.Material.Glass,1)
    local a=Instance.new("Attachment")
    a.Parent=pa
    local b=Instance.new("Attachment")
    b.Parent=pb
    local beam=Instance.new("Beam")
    beam.Name=name
    beam.Attachment0=a
    beam.Attachment1=b
    beam.FaceCamera=true
    beam.Segments=20
    beam.Width0=width
    beam.Width1=width*.22
    beam.CurveSize0=curve
    beam.CurveSize1=-curve*.7
    beam.Color=ColorSequence.new(color,Color3.fromRGB(240,245,255))
    beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.28),NumberSequenceKeypoint.new(.65,.14),NumberSequenceKeypoint.new(1,.88)})
    beam.LightEmission=.86
    beam.LightInfluence=0
    beam.Parent=rig.Folder
    local obj={A=pa,B=pb,Attachment0=a,Attachment1=b,Beam=beam,Curve=curve}
    rig.Curves[#rig.Curves+1]=obj
    return obj
end

local function auraCurveMove(obj,fromPos,toPos,twist,pulse)
    local delta=toPos-fromPos
    if delta.Magnitude<.01 then return end
    local axis=CFrame.lookAt(fromPos,toPos)*CFrame.Angles(0,0,twist or 0)
    obj.A.CFrame=axis
    obj.B.CFrame=CFrame.lookAt(toPos,fromPos)*CFrame.Angles(0,0,(twist or 0)+math.pi*.4)
    obj.Beam.CurveSize0=obj.Curve*(.7+.3*math.sin(pulse or 0))
    obj.Beam.CurveSize1=-obj.Curve*(.75+.25*math.cos((pulse or 0)*.7))
end

local function auraDestroy()
    if not AuraRig then return end
    local rig=AuraRig
    AuraRig=nil
    for _,ribbon in ipairs(rig.Ribbons or {}) do
        ribbon.Enabled=false
        ribbon:Clear()
    end
    if rig.Folder and rig.Folder.Parent then rig.Folder:Destroy() end
end

local function auraBuild(mode)
    auraDestroy()
    local rig={Mode=mode,Parts={},Nodes={},Curves={},Ribbons={},Center=Vector3.zero,Last=os.clock(),Start=os.clock(),Pulse=0}
    local folder=Instance.new("Folder")
    folder.Name="MEFE_AURA_SCULPTURE_"..tostring(mode)
    folder:SetAttribute("MEFEEffect",true)
    folder.Parent=FX
    rig.Folder=folder
    local colors=palette[mode]
    if mode==1 then
        for i=1,9 do
            local blade=auraObject(rig,"BloodScythe_"..i,Vector3.new(1.1,7.1,1.4),i%3==0 and colors[2] or colors[1],Enum.Material.Glass,.11,"WedgePart")
            local edge=auraObject(rig,"BloodScytheEdge_"..i,Vector3.new(.14,6.1,.14),colors[3],Enum.Material.Neon,.16)
            rig.Nodes[#rig.Nodes+1]={blade,edge,i}
            if i%2==1 then auraRibbon(rig,edge,colors[1],.48,.72) end
        end
        for i=1,3 do auraCurveBuild(rig,"SanguineArtery_"..i,colors[1],.29,3.5) end
        for i=1,7 do
            local drop=auraObject(rig,"BloodOrbitDroplet_"..i,Vector3.new(.32,.95,.32),colors[1],Enum.Material.Glass,.05,"Part")
            drop.Shape=Enum.PartType.Ball
            rig.Drops=rig.Drops or {}
            rig.Drops[#rig.Drops+1]=drop
        end
    elseif mode==2 then
        rig.Moons={}
        for m=1,2 do
            local moon={Outer={},Inner={}}
            for k=1,10 do
                moon.Outer[k]=auraObject(rig,"MoonCrescentRim_"..m.."_"..k,Vector3.new(.22,.22,1),m==1 and colors[1] or colors[2],Enum.Material.Glass,.07)
                moon.Inner[k]=auraObject(rig,"MoonCrescentInner_"..m.."_"..k,Vector3.new(.10,.1,1),colors[3],Enum.Material.Neon,.25)
            end
            rig.Moons[m]=moon
        end
        for i=1,4 do auraCurveBuild(rig,"MoonlitConstellation_"..i,colors[2],.19,2.9) end
        rig.Stars={}
        for i=1,9 do
            local star=auraObject(rig,"SuspendedConstellation_"..i,Vector3.new(.42,.62,.28),i%3==0 and colors[3] or colors[1],Enum.Material.Neon,.08,"WedgePart")
            rig.Stars[i]=star
            if i<=6 then auraRibbon(rig,star,colors[1],.75,.36) end
        end
    elseif mode==3 then
        rig.Cages={}
        for layer=1,3 do
            local edges={}
            for e=1,12 do
                edges[e]=auraObject(rig,"AxiomPolyhedron_"..layer.."_"..e,Vector3.new(.16,.16,2),layer==2 and colors[2] or colors[1],Enum.Material.Neon,.11)
            end
            rig.Cages[layer]=edges
        end
        for i=1,6 do auraCurveBuild(rig,"ProofDiagonal_"..i,colors[2],.13,1.6) end
        rig.Vertices={}
        for i=1,8 do
            local node=auraObject(rig,"ProofVertex_"..i,Vector3.one*.54,colors[2],Enum.Material.Glass,.09)
            rig.Vertices[i]=node
        end
    elseif mode==4 then
        rig.Portals={}
        for i=1,6 do auraCurveBuild(rig,"SpatialBridge_"..i,colors[(i%3)+1],.31,4.1) end
        for portal=1,3 do
            local item={Rim={},Core=nil,Shards={}}
            for i=1,13 do
                item.Rim[i]=auraObject(rig,"TornPortalRim_"..portal.."_"..i,Vector3.new(.24,.24,1),i%3==0 and colors[1] or colors[2],Enum.Material.Neon,.12)
            end
            item.Core=auraObject(rig,"DisplacedPortalMembrane_"..portal,Vector3.new(.07,4.2,4.2),colors[2],Enum.Material.Glass,.68)
            item.Core.Shape=Enum.PartType.Cylinder
            for i=1,3 do
                item.Shards[i]=auraObject(rig,"FloatingRealityShard_"..portal.."_"..i,Vector3.new(.72,1.6,.28),colors[(i%3)+1],Enum.Material.Glass,.23,"WedgePart")
                if i==1 then auraRibbon(rig,item.Shards[i],colors[2],.55,.9) end
            end
            rig.Portals[portal]=item
        end
    elseif mode==5 then
        rig.PrismPairs={}
        for i=1,5 do auraCurveBuild(rig,"RefractedOpticalRay_"..i,colors[1],.11,2.0) end
        for i=1,9 do
            local left=auraObject(rig,"RefractedGlassFacetL_"..i,Vector3.new(.95,2.4,1.15),i%2==0 and colors[1] or colors[2],Enum.Material.Glass,.34,"WedgePart")
            local right=auraObject(rig,"RefractedGlassFacetR_"..i,Vector3.new(.95,2.4,1.15),colors[3],Enum.Material.Glass,.42,"WedgePart")
            left.Reflectance=.36
            right.Reflectance=.43
            rig.PrismPairs[i]={left,right}
            if i%2==1 then auraRibbon(rig,left,colors[2],.58,.55) end
        end
        rig.RefractionThreads={}
        for i=1,5 do
            rig.RefractionThreads[i]=auraObject(rig,"RefractedSpectrumThread_"..i,Vector3.new(.08,.08,2),i%2==0 and colors[2] or colors[1],Enum.Material.Glass,.45)
        end
    elseif mode==6 then
        rig.Feathers={}
        for i=1,6 do auraCurveBuild(rig,"SeraphWingRay_"..i,colors[3],.24,3.5) end
        for side=-1,1,2 do
            for i=1,9 do
                local feather=auraObject(rig,"SeraphWingFeather_"..side.."_"..i,Vector3.new(.7,3.2,1.5),i%3==0 and colors[3] or colors[1],Enum.Material.Glass,.12,"WedgePart")
                rig.Feathers[#rig.Feathers+1]={Part=feather,Side=side,Index=i}
                if i%2==0 then auraRibbon(rig,feather,colors[1],.72,.8) end
            end
        end
        rig.Halos={}
        for layer=1,2 do
            rig.Halos[layer]={}
            for i=1,15 do
                rig.Halos[layer][i]=auraObject(rig,"SeraphGoldHalo_"..layer.."_"..i,Vector3.new(.18,.18,2),layer==1 and colors[3] or colors[2],Enum.Material.Neon,.12)
            end
        end
        rig.Thunder={}
        for i=1,5 do
            rig.Thunder[i]=auraObject(rig,"SeraphLightningPillar_"..i,Vector3.new(.12,.12,8),i%2==0 and colors[2] or colors[3],Enum.Material.Neon,.28)
        end
    elseif mode==7 then
        rig.Accretion={}
        for layer=1,3 do
            rig.Accretion[layer]={}
            for i=1,16 do
                rig.Accretion[layer][i]=auraObject(rig,"EventHorizonAccretion_"..layer.."_"..i,Vector3.new(.4,.2,3),layer==2 and colors[2] or colors[3],Enum.Material.Glass,.15)
            end
        end
        for i=1,6 do auraCurveBuild(rig,"GravitationalLensing_"..i,colors[2],.37,-3.8) end
        rig.Debris={}
        for i=1,11 do
            rig.Debris[i]=auraObject(rig,"OrbitingMatter_"..i,Vector3.new(.7,.8,1),i%2==0 and colors[1] or colors[2],Enum.Material.SmoothPlastic,.05)
            if i%2==0 then auraRibbon(rig,rig.Debris[i],colors[2],.95,.42) end
        end
        rig.Core=auraObject(rig,"CollapsedGravityCore",Vector3.new(2.2,2.2,2.2),Color3.fromRGB(2,2,4),Enum.Material.SmoothPlastic,.03)
        rig.Core.Shape=Enum.PartType.Ball
    else
        rig.Monoliths={}
        for i=1,8 do auraCurveBuild(rig,"NullHymnBrokenSound_"..i,colors[i%2==0 and 3 or 1],.11,(i%2==0 and -1 or 1)*2.7) end
        for i=1,8 do
            rig.Monoliths[i]=auraObject(rig,"SilentVoidMonolith_"..i,Vector3.new(2.2,5.8,.43),i%3==0 and colors[3] or colors[2],Enum.Material.SmoothPlastic,.05)
        end
        rig.Equilibrium={}
        for i=1,20 do
            rig.Equilibrium[i]=auraObject(rig,"NullSilentWave_"..i,Vector3.new(.36,2.4,.32),i%4==0 and colors[1] or colors[2],Enum.Material.Glass,.19)
        end
        rig.Gaps={}
        for i=1,4 do
            rig.Gaps[i]=auraObject(rig,"NullBrokenFrame_"..i,Vector3.new(2.4,.16,2.4),colors[3],Enum.Material.SmoothPlastic,.16)
        end
    end
    AuraRig=rig
    return rig
end

local function auraAnimate(rig)
    local t=os.clock()-rig.Start
    local base=rig.Center
    local mode=rig.Mode
    if mode==1 then
        for _,data in ipairs(rig.Nodes) do
            local blade,edge,i=data[1],data[2],data[3]
            local a=i*math.pi*2/9+t*1.25
            local r=5.3+math.sin(t*2.1+i)*.5
            local p=base+Vector3.new(math.cos(a)*r,math.sin(t*1.2+i)*1.4,math.sin(a)*r)
            blade.CFrame=CFrame.new(p)*CFrame.Angles(math.rad(12),-a,t*.6+math.rad(i*24))
            edge.CFrame=blade.CFrame*CFrame.new(-.32,.3,.35)*CFrame.Angles(0,0,-.25)
            blade.Transparency=.1+math.sin(t*1.7+i)*.055
        end
        for i,drop in ipairs(rig.Drops) do
            local a=t*1.8+i*math.pi*2/7
            drop.CFrame=CFrame.new(base+Vector3.new(math.cos(a)*(2+i*.36),3.2+math.sin(t*2+i)*2.1,math.sin(a)*(2+i*.36)))
        end
        for i,flux in ipairs(rig.Curves) do
            local edge=rig.Nodes[i*3][2]
            local drop=rig.Drops[i*2]
            auraCurveMove(flux,edge.Position,drop.Position,t*.7+i,t*2+i)
        end
    elseif mode==2 then
        for m,moon in ipairs(rig.Moons) do
            local orbit=t*(m==1 and .36 or -.3)+m*math.pi
            local pos=base+Vector3.new(math.cos(orbit)*8.1,2+math.sin(t*.65+m)*1.7,math.sin(orbit)*8.1)
            local spin=CFrame.new(pos)*CFrame.Angles(.12,orbit+math.pi/2,math.sin(t*.48+m)*.14)
            for k=1,10 do
                local a=-2.15+(k-1)*4.3/10
                local b=-2.15+k*4.3/10
                local outerA=Vector3.new(math.cos(a)*2.5,math.sin(a)*3.25,0)
                local outerB=Vector3.new(math.cos(b)*2.5,math.sin(b)*3.25,0)
                local innerA=Vector3.new(math.cos(a)*2.1+.72,math.sin(a)*2.65,0)
                local innerB=Vector3.new(math.cos(b)*2.1+.72,math.sin(b)*2.65,0)
                auraBeam(moon.Outer[k],spin:PointToWorldSpace(outerA),spin:PointToWorldSpace(outerB),.23)
                auraBeam(moon.Inner[k],spin:PointToWorldSpace(innerA),spin:PointToWorldSpace(innerB),.11)
            end
        end
        for i,star in ipairs(rig.Stars) do
            local a=i*math.pi*2/9+t*.12
            local r=5+(i%3)*2.1
            local p=base+Vector3.new(math.cos(a)*r,4+math.sin(t*.75+i)*3.2,math.sin(a)*r)
            star.CFrame=CFrame.new(p)*CFrame.Angles(t*.7,i,math.pi/4+t*.2)
        end
        for i,flux in ipairs(rig.Curves) do
            auraCurveMove(flux,rig.Stars[i].Position,rig.Stars[9-i].Position,t*.18+i,t*.5+i)
        end
    elseif mode==3 then
        local dirs={Vector3.new(-1,-1,-1),Vector3.new(1,-1,-1),Vector3.new(1,-1,1),Vector3.new(-1,-1,1),Vector3.new(-1,1,-1),Vector3.new(1,1,-1),Vector3.new(1,1,1),Vector3.new(-1,1,1)}
        local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
        for layer,cage in ipairs(rig.Cages) do
            local scale=2.4+layer*2.2
            local cframe=CFrame.new(base+Vector3.new(0,1,0))*CFrame.Angles(t*(layer==2 and -.42 or .5),t*(layer==1 and .87 or -.61),t*(layer==3 and .73 or -.3))
            for i,edge in ipairs(cage) do
                local a,b=edges[i][1],edges[i][2]
                auraBeam(edge,cframe:PointToWorldSpace(dirs[a]*scale),cframe:PointToWorldSpace(dirs[b]*scale),layer==1 and .21 or .11)
            end
            if layer==1 then
                for i,vertex in ipairs(rig.Vertices) do
                    vertex.CFrame=CFrame.new(cframe:PointToWorldSpace(dirs[i]*scale))
                end
            end
        end
        local links={{1,7},{2,8},{3,5},{4,6},{2,7},{3,8}}
        for i,flux in ipairs(rig.Curves) do
            auraCurveMove(flux,rig.Vertices[links[i][1]].Position,rig.Vertices[links[i][2]].Position,t*.11+i,t+i)
        end
    elseif mode==4 then
        for i,portal in ipairs(rig.Portals) do
            local a=t*(i==2 and -.69 or .82)+i*math.pi*2/3
            local r=6.7+math.sin(t*.55+i)*1.1
            local p=base+Vector3.new(math.cos(a)*r,math.sin(t*.9+i)*2.8+1.4,math.sin(a)*r)
            local pivot=CFrame.lookAt(p,base+Vector3.new(0,1,0))*CFrame.Angles(0,0,t*.31+i)
            local wide=2.3+math.sin(t*1.5+i)*.34
            for k,segment in ipairs(portal.Rim) do
                local p1=(k-1)*math.pi*2/13
                local p2=k*math.pi*2/13
                local v1=Vector3.new(math.cos(p1)*wide,math.sin(p1)*3.5,0)
                local v2=Vector3.new(math.cos(p2)*wide,math.sin(p2)*3.5,0)
                auraBeam(segment,pivot:PointToWorldSpace(v1),pivot:PointToWorldSpace(v2),.24)
            end
            portal.Core.CFrame=pivot*CFrame.Angles(0,math.pi/2,0)
            portal.Core.Size=Vector3.new(.08,wide*1.55,wide*1.55)
            portal.Core.Transparency=.58+math.sin(t*2.3+i)*.08
            for k,shard in ipairs(portal.Shards) do
                local az=k*math.pi*2/3+t*.8
                local relative=Vector3.new(math.cos(az)*3.25,math.sin(az*1.5)*3.4,math.sin(az)*1.3)
                shard.CFrame=pivot*CFrame.new(relative)*CFrame.Angles(t*1.1+k,t*.8-k,t*.34)
            end
        end
        for i,flux in ipairs(rig.Curves) do
            local port=rig.Portals[(i-1)%3+1]
            local dst=rig.Portals[i%3+1]
            auraCurveMove(flux,port.Shards[math.floor((i-1)/3)+1].Position,dst.Core.Position,t*.67+i,t*2+i)
        end
    elseif mode==5 then
        for i,pair in ipairs(rig.PrismPairs) do
            local a=t*.65+i*math.pi*2/9
            local r=5.3+math.sin(t*1.5+i)*1.0
            local scale=.45+.55*(.5+.5*math.sin(t*1.9+i))
            local p=base+Vector3.new(math.cos(a)*r,math.sin(a*3+t)*2.1+1.1,math.sin(a)*r)
            local spin=CFrame.new(p)*CFrame.Angles(t*.95,a+t*1.1,t*.8)
            pair[1].CFrame=spin*CFrame.Angles(math.pi/2,0,0)
            pair[2].CFrame=spin*CFrame.Angles(-math.pi/2,math.pi,0)
            pair[1].Size=Vector3.new(.95,2.4,1.15)*scale
            pair[2].Size=Vector3.new(.95,2.4,1.15)*scale
            pair[1].Transparency=.26+.4*(1-scale)
            pair[2].Transparency=.34+.4*(1-scale)
        end
        for i,thread in ipairs(rig.RefractionThreads) do
            local a=i*math.pi*2/5+t*.4
            local v1=base+Vector3.new(math.cos(a)*7,math.sin(t*1.5+i)*3.1,math.sin(a)*7)
            local v2=base+Vector3.new(math.cos(a+1.7)*2.5,1.7,math.sin(a+1.7)*2.5)
            auraBeam(thread,v1,v2,.055)
        end
        for i,flux in ipairs(rig.Curves) do
            local first=rig.PrismPairs[i][1]
            local second=rig.PrismPairs[(i%9)+1][2]
            auraCurveMove(flux,first.Position,second.Position,t*.16+i,t*.45+i)
        end
    elseif mode==6 then
        for _,data in ipairs(rig.Feathers) do
            local i,side=data.Index,data.Side
            local spread=1+i*1.1
            local rise=4.8+math.sin(t*2.1+i*.42)*1.05+i*.4
            local pos=base+Vector3.new(side*(1.45+spread*.6),rise,2-i*.16)
            data.Part.CFrame=CFrame.new(pos)*CFrame.Angles(.27,side*.34,side*(.33+i*.11+math.sin(t*1.35)*.12))
            data.Part.Size=Vector3.new(.8,2.8+i*.28,1.3)
        end
        for layer,halo in ipairs(rig.Halos) do
            local y=6.7+layer*1.3
            local rad=3.3+layer*1.6
            for i,segment in ipairs(halo) do
                local a=(i-1)*math.pi*2/15+t*(layer==1 and .5 or -.64)
                local b=i*math.pi*2/15+t*(layer==1 and .5 or -.64)
                local p=base+Vector3.new(math.cos(a)*rad,y+math.sin(t+i)*.08,math.sin(a)*rad)
                local q=base+Vector3.new(math.cos(b)*rad,y+math.sin(t+i)*.08,math.sin(b)*rad)
                auraBeam(segment,p,q,layer==1 and .23 or .13)
            end
        end
        for i,bolt in ipairs(rig.Thunder) do
            local a=i*math.pi*2/5+t*.13
            local p=base+Vector3.new(math.cos(a)*8,3.5+math.sin(t*4+i)*1,math.sin(a)*8)
            bolt.CFrame=CFrame.new(p)*CFrame.Angles(0,a,0)
            bolt.Size=Vector3.new(.10,7,.10)
            bolt.Transparency=.3+.26*(.5+.5*math.sin(t*10+i*5))
        end
        for i,flux in ipairs(rig.Curves) do
            local feather=rig.Feathers[i*2]
            if feather then
                auraCurveMove(flux,feather.Part.Position,base+Vector3.new(math.cos(t*.38+i)*4.5,8.3,math.sin(t*.38+i)*4.5),t*.08+i,t*.75+i)
            end
        end
    elseif mode==7 then
        for layer,band in ipairs(rig.Accretion) do
            local r=3.4+layer*2.8
            local tilt=CFrame.Angles(.25*layer,.15*layer,t*.13*layer)
            for i,segment in ipairs(band) do
                local a=i*math.pi*2/16+t*(layer==2 and -.85 or .7)
                local b=(i+1)*math.pi*2/16+t*(layer==2 and -.85 or .7)
                local va=tilt:VectorToWorldSpace(Vector3.new(math.cos(a)*r,math.sin(a*3)*.4,math.sin(a)*r))
                local vb=tilt:VectorToWorldSpace(Vector3.new(math.cos(b)*r,math.sin(b*3)*.4,math.sin(b)*r))
                auraBeam(segment,base+va,base+vb,layer==2 and .4 or .21)
            end
        end
        for i,chunk in ipairs(rig.Debris) do
            local a=t*(i%2==0 and -1.15 or .95)+i*math.pi*2/11
            local r=6.4+(i%3)*1.95
            local pos=base+Vector3.new(math.cos(a)*r,math.sin(a*2)*2.4+2.1,math.sin(a)*r)
            chunk.CFrame=CFrame.new(pos)*CFrame.Angles(t*1.7+i,t*1.1,t*.7)
        end
        rig.Core.CFrame=CFrame.new(base+Vector3.new(0,3.3,0))
        for i,flux in ipairs(rig.Curves) do
            local chunk=rig.Debris[i+1]
            auraCurveMove(flux,chunk.Position,rig.Core.Position,t*.5+i,t*.75+i)
        end
    else
        for i,monolith in ipairs(rig.Monoliths) do
            local a=i*math.pi*2/8
            local r=7.8
            local p=base+Vector3.new(math.cos(a)*r,2.7+math.sin(t*.4+i)*.55,math.sin(a)*r)
            monolith.CFrame=CFrame.lookAt(p,base+Vector3.new(0,2,0))*CFrame.Angles(math.sin(t*.45+i)*.05,0,(i%2==0 and 1 or -1)*.19)
        end
        for i,wave in ipairs(rig.Equilibrium) do
            local x=(i-10.5)*.85
            local h=.75+((i*13)%8)*.34
            if i==10 or i==11 then h=.16 end
            local z=(i%2==0 and 7.3 or -7.3)
            local height=h*(1+math.sin(i*.65+t*.65)*.17)
            wave.Size=Vector3.new(.29,height,.3)
            wave.CFrame=CFrame.new(base+Vector3.new(x,.4+height*.5,z))
        end
        for i,gap in ipairs(rig.Gaps) do
            local a=i*math.pi/2+t*.09
            gap.CFrame=CFrame.new(base+Vector3.new(math.cos(a)*3.5,6.7+math.sin(t*.35+i)*.4,math.sin(a)*3.5))*CFrame.Angles(.35,i*.8,.5)
        end
        for i,flux in ipairs(rig.Curves) do
            local from=rig.Monoliths[i].CFrame:PointToWorldSpace(Vector3.new(0,2.7,0))
            local wave=rig.Equilibrium[(i*2)%20+1]
            auraCurveMove(flux,from,wave.Position,t*.08+i,t*.38+i)
            flux.Beam.Width0=.07+.06*(.5+.5*math.sin(t*.7+i*1.15))
        end
    end
end

local AuraFrameClock=0
RS.Heartbeat:Connect(function(dt)
    local rig=AuraRig
    if not rig then return end
    if not AuraVisible or not rig.Folder or not rig.Folder.Parent or os.clock()-rig.Last>1.5 then
        auraDestroy()
        return
    end
    AuraFrameClock=AuraFrameClock+dt
    if AuraFrameClock<.032 then return end
    AuraFrameClock=0
    auraAnimate(rig)
end)

local function modeAuraVisual(d)
    if not AuraVisible then return end
    local mode=d.Mode or CurrentMode
    if typeof(d.Position)~="Vector3" then return end
    if not AuraRig or AuraRig.Mode~=mode then auraBuild(mode) end
    local rig=AuraRig
    if not rig then return end
    rig.Center=d.Position
    rig.Last=os.clock()
    rig.Pulse=d.Tick or (rig.Pulse+1)
    local colors=palette[mode]
    local tick=rig.Pulse
    local center=rig.Center
    if mode==1 and tick%3==0 then
        for i=1,4 do
            local a=tick+i*math.pi/2
            local p=center+Vector3.new(math.cos(a)*5,3,math.sin(a)*5)
            local q=center+Vector3.new(math.cos(a+.7)*8,-2,math.sin(a+.7)*8)
            extraLightning(p,q,1,5,1.3,.12,3,i%2==0)
        end
    elseif mode==2 and tick%3==0 then
        for i=1,3 do
            local a=i*math.pi*2/3+tick*.3
            local p=center+Vector3.new(math.cos(a)*9,15,math.sin(a)*9)
            local q=center+Vector3.new(math.cos(a)*9,-2,math.sin(a)*9)
            starfall(q,colors[2],2,14,4)
            line(p,q,.1,colors[1],.6)
        end
    elseif mode==3 and tick%4==0 then
        for i=1,6 do
            local a=i*math.pi/3
            local p=center+Vector3.new(math.cos(a)*9,-3,math.sin(a)*9)
            local q=center+Vector3.new(math.cos(a+math.pi/3)*9,7,math.sin(a+math.pi/3)*9)
            line(p,q,.15,colors[2],.43)
        end
    elseif mode==4 and tick%2==0 then
        for i=1,3 do
            local a=tick*.4+i*math.pi*2/3
            local p=center+Vector3.new(math.cos(a)*6,i*1.7,math.sin(a)*6)
            local q=p+Vector3.new(math.sin(a*2)*5,-i*2,math.cos(a*2)*5)
            ripple(p,colors[2],2,5,.45)
            line(p,q,.16,colors[1],.38)
        end
    elseif mode==5 and tick%4==0 then
        makeAuraPrisms(center,d.Radius or 19,5)
    elseif mode==6 and tick%3==0 then
        for i=1,3 do
            local a=tick*.3+i*math.pi*2/3
            local p=center+Vector3.new(math.cos(a)*7,17,math.sin(a)*7)
            local q=center+Vector3.new(math.cos(a)*7,-2,math.sin(a)*7)
            extraLightning(p,q,6,6,1.1,.14,3,false)
        end
    elseif mode==7 and tick%3==0 then
        for i=1,5 do
            local a=tick*.3+i*math.pi*2/5
            local p=center+Vector3.new(math.cos(a)*12,4+math.sin(a)*3,math.sin(a)*12)
            local q=center+Vector3.new(0,3.3,0)
            line(p,q,.28,colors[2],.63)
        end
    elseif mode==8 and tick%4==0 then
        for i=1,6 do
            local a=i*math.pi/3
            local p=center+Vector3.new(math.cos(a)*8,5,math.sin(a)*8)
            local q=center+Vector3.new(math.cos(a)*8,-2,math.sin(a)*8)
            line(p,q,.07,colors[i%2==0 and 1 or 3],.24)
        end
    end
end

local function superBezierAccent(center,mode,phase,radius)
    local group=Instance.new("Folder")
    group.Name="MEFE_SUPER_BEAM_TRAIL_"..tostring(mode)
    group:SetAttribute("MEFEEffect",true)
    group.Parent=FX
    local rig={Folder=group,Parts={},Ribbons={},Curves={}}
    local colors=palette[mode] or palette[1]
    local life=phase=="CHARGE" and 1.02 or .68
    local reach=math.min(radius*.45,32)
    for i=1,5 do
        local color=mode==7 and colors[2] or (mode==8 and (i%2==0 and colors[1] or colors[3]) or colors[(i%3)+1])
        local curve=mode==3 and 1.2 or (mode==7 and -reach*.32 or (mode==8 and -1.5 or reach*.23))
        local beam=auraCurveBuild(rig,"SuperResonance_"..i,color,mode==7 and .42 or .23,curve)
        if i<=3 and mode~=3 and mode~=8 then
            auraRibbon(rig,beam.A,color,mode==7 and .5 or .34,mode==6 and 1.1 or .6)
        end
    end
    local started=os.clock()
    local heartbeat
    heartbeat=RS.Heartbeat:Connect(function()
        if not group.Parent then heartbeat:Disconnect() return end
        local elapsed=os.clock()-started
        local u=math.clamp(elapsed/life,0,1)
        local fade=math.sin(math.pi*u)
        for i,flux in ipairs(rig.Curves) do
            local a=i*math.pi*2/5
            local x,y
            if mode==1 then
                x=center+Vector3.new(math.cos(a+elapsed*7)*reach*(1-u*.5),math.sin(elapsed*9+i)*5,math.sin(a+elapsed*7)*reach*(1-u*.5))
                y=center+Vector3.new(math.cos(a+1.8)*reach*.2,4+math.sin(elapsed*5+i)*3,math.sin(a+1.8)*reach*.2)
            elseif mode==2 then
                x=center+Vector3.new(math.cos(a)*reach*.7,22-26*u,math.sin(a)*reach*.7)
                y=center+Vector3.new(math.cos(a+elapsed)*reach*.22,1+math.sin(elapsed*3+i)*3,math.sin(a+elapsed)*reach*.22)
            elseif mode==3 then
                local ap=a+elapsed*(i%2==0 and -1 or 1)
                local h=(i%2==0 and -1 or 1)*reach*.5
                x=center+Vector3.new(math.cos(ap)*reach,h,math.sin(ap)*reach)
                y=center+Vector3.new(math.cos(ap+math.pi*.78)*reach,-h,math.sin(ap+math.pi*.78)*reach)
            elseif mode==4 then
                x=center+Vector3.new(math.cos(a+elapsed*2)*reach,math.sin(elapsed*7+i)*6,math.sin(a+elapsed*2)*reach)
                y=center+Vector3.new(math.cos(a+3.5-elapsed*3)*reach*.65,math.sin(elapsed*4+i)*7,math.sin(a+3.5-elapsed*3)*reach*.65)
            elseif mode==5 then
                x=center+Vector3.new(math.cos(a+elapsed)*reach,6*math.sin(elapsed*3+i),math.sin(a+elapsed)*reach)
                y=center+Vector3.new(math.cos(a+2+elapsed*2)*reach*.4,4*math.cos(elapsed*2+i),math.sin(a+2+elapsed*2)*reach*.4)
            elseif mode==6 then
                x=center+Vector3.new(math.cos(a)*reach*.55,26-elapsed*18,math.sin(a)*reach*.55)
                y=center+Vector3.new(math.cos(a+1)*reach*.8,-2+elapsed*4,math.sin(a+1)*reach*.8)
            elseif mode==7 then
                local spiral=a+elapsed*5
                x=center+Vector3.new(math.cos(spiral)*reach*(1-u*.82),math.sin(elapsed*3+i)*reach*.25,math.sin(spiral)*reach*(1-u*.82))
                y=center+Vector3.new(math.cos(spiral+1.1)*2.1,2.2,math.sin(spiral+1.1)*2.1)
            else
                local b=a+elapsed*.13
                x=center+Vector3.new(math.cos(b)*reach*.75,8+math.sin(elapsed*1.2+i)*1.9,math.sin(b)*reach*.75)
                y=center+Vector3.new(math.cos(b+math.pi)*reach*.6,-3+math.sin(elapsed*1.6+i)*2.8,math.sin(b+math.pi)*reach*.6)
            end
            auraCurveMove(flux,x,y,elapsed*.45+i,elapsed*2+i)
            flux.Beam.Width0=(mode==7 and .42 or .23)*(.15+.85*fade)
            flux.Beam.Width1=flux.Beam.Width0*.2
        end
        if u>=1 then
            heartbeat:Disconnect()
            for _,ribbon in ipairs(rig.Ribbons) do ribbon.Enabled=false ribbon:Clear() end
            group:Destroy()
        end
    end)
    Debris:AddItem(group,life+.3)
end

local ActiveBlackholeVisuals={}
local function spawnBlackholeVisual(d)
    if typeof(d.Position)~="Vector3" then return end
    local center=d.Position
    local duration=math.max(1,d.Duration or 16)
    local id=d.Id
    local prior=ActiveBlackholeVisuals[id]
    if prior and prior.Stop then prior.Stop() end
    local group=Instance.new("Folder")
    group.Name="EVENT_HORIZON_16S_BLACKHOLE"
    group:SetAttribute("MEFEEffect",true)
    group.Parent=FX
    local rig={Folder=group,Parts={},Ribbons={},Curves={}}
    local core=auraObject(rig,"EventHorizonSingularity",Vector3.new(1,1,1),Color3.fromRGB(0,0,0),Enum.Material.SmoothPlastic,0)
    core.Shape=Enum.PartType.Ball
    local inner=auraObject(rig,"SingularityPhotonShadow",Vector3.new(1,1,1),Color3.fromRGB(15,5,25),Enum.Material.Glass,.48)
    inner.Shape=Enum.PartType.Ball
    local rim=auraObject(rig,"GravitationalEventRim",Vector3.new(1,1,1),Color3.fromRGB(124,76,193),Enum.Material.ForceField,.62)
    rim.Shape=Enum.PartType.Ball
    local light=Instance.new("PointLight")
    light.Color=Color3.fromRGB(137,93,235)
    light.Brightness=2.1
    light.Range=56
    light.Parent=core
    local disk={}
    local diskColors={Color3.fromRGB(177,122,255),Color3.fromRGB(238,216,255),Color3.fromRGB(81,47,129)}
    local lens={}
    for i=1,20 do
        lens[i]=auraObject(rig,"WarpedGlassLensing_"..i,Vector3.new(.45,.65,3.2),i%2==0 and diskColors[1] or diskColors[2],Enum.Material.Glass,.42,"WedgePart")
        lens[i].Reflectance=.38
        if i%5==0 then auraRibbon(rig,lens[i],diskColors[1],.35,.38) end
    end
    for i=1,48 do
        local shard=auraObject(rig,"AccretionShard_"..i,Vector3.new(.45,.17,2.8),diskColors[(i%3)+1],Enum.Material.Neon,.09)
        disk[#disk+1]=shard
        if i%6==0 then auraRibbon(rig,shard,diskColors[(i%3)+1],.39,.58) end
    end
    local jets={}
    for i=1,9 do
        local arc=auraCurveBuild(rig,"SpiralGravitationalArc_"..i,diskColors[(i%3)+1],i%2==0 and .27 or .39,4.5)
        jets[#jets+1]=arc
    end
    local lightningClock=0
    local impactFired=false
    local start=os.clock()
    local stopping=false
    local stopAt=nil
    local frame
    local function stop()
        if stopping then return end
        stopping=true
        stopAt=os.clock()
    end
    ActiveBlackholeVisuals[id]={Stop=stop,Group=group}
    play3DSound(center,9114890176,1.5,.54,330)
    frame=RS.Heartbeat:Connect(function()
        if not group.Parent then frame:Disconnect() return end
        local t=os.clock()-start
        if t>=duration then stop() end
        local collapse=stopping and math.clamp((os.clock()-stopAt)/.65,0,1) or 0
        local appear=math.min(1,t/1.1)
        local scale=appear*(1-collapse)
        local radius=math.max(.05,13*scale)
        if stopping and not impactFired then
            impactFired=true
            play3DSound(center,170278900,1.6,.62,360)
            for i=1,9 do
                task.delay((i-1)*.065,function()
                    if not group.Parent then return end
                    local a=i*math.pi*2/9
                    local startPoint=center+Vector3.new(math.cos(a)*math.random(42,64),math.random(-15,22),math.sin(a)*math.random(42,64))
                    extraLightning(startPoint,center,7,7,5,.41,5,false)
                    if i%3==0 then extraLightning(startPoint,center,7,5,2.8,.17,5,true) end
                end)
            end
            shockDisc(center,Color3.fromRGB(186,119,255),84,.66)
            shockDisc(center,Color3.fromRGB(244,235,255),68,.51)
        end
        if not stopping and scale>.45 and t-lightningClock>=(UIS.TouchEnabled and 1.25 or .90) then
            lightningClock=t
            local amount=1
            for j=1,amount do
                local a=t*3.7+j*math.pi*1.17
                local distant=36+math.random(6,19)
                local launch=center+Vector3.new(math.cos(a)*distant,math.sin(t*2.4+j)*13,math.sin(a)*distant)
                local elbow=center+Vector3.new(math.cos(a+1.3)*27,math.sin(t*4.2+j)*5,math.sin(a+1.3)*27)
                local sink=center+Vector3.new(math.cos(a+2.7)*6,math.sin(a*3)*3,math.sin(a+2.7)*6)
                extraLightning(launch,elbow,7,7,3.9,.24,4,false)
                extraLightning(elbow,sink,7,6,2.5,.31,4,false)
                if not UIS.TouchEnabled and math.floor(t*2)%2==0 then extraLightning(launch,elbow,7,5,1.5,.105,5,true) end
            end
        end
        core.Size=Vector3.one*radius
        core.CFrame=CFrame.new(center)
        inner.Size=Vector3.one*(radius+3.8*scale)
        inner.CFrame=core.CFrame
        rim.Size=Vector3.one*(radius+5.5*scale+math.sin(t*4)*.8*scale)
        rim.CFrame=core.CFrame
        rim.Transparency=.67+.33*collapse
        light.Brightness=2.1*scale
        for i,shard in ipairs(disk) do
            local layer=(i%3)+1
            local a=t*(layer%2==0 and -2.4 or 3.1)+i*math.pi*2/#disk
            local r=(17+layer*5+math.sin(t*2+i)*2)*scale
            local lift=math.sin(a*1.4+i)*(.5+layer*.28)*scale
            local pivot=CFrame.new(center)*CFrame.Angles(.09*(layer-2),0,.075*(layer-2))
            local p=pivot:PointToWorldSpace(Vector3.new(math.cos(a)*r,lift,math.sin(a)*r))
            shard.CFrame=CFrame.lookAt(p,center)*CFrame.Angles(0,a*1.6,0)
            shard.Size=Vector3.new(.45*scale,.17*scale,(2.3+layer*.7)*scale)
            shard.Transparency=.14+.86*collapse
        end
        for i,facet in ipairs(lens) do
            local band=(i%2)+1
            local a=i*math.pi*2/#lens+t*(band==1 and .95 or -1.23)
            local r=(30+band*9+math.sin(i*1.3+t*1.8)*4)*scale
            local height=(math.sin(a*2.3+i)*8+math.cos(t*1.4+i)*3)*scale
            local from=center+Vector3.new(math.cos(a)*r,height,math.sin(a)*r)
            facet.CFrame=CFrame.lookAt(from,center)*CFrame.Angles(math.sin(t*1.7+i)*.26,a+t*.32,math.sin(a)*.38)
            facet.Size=Vector3.new(.44*scale,.65*scale,(2.5+band*1.1)*scale)
            facet.Transparency=.43+.57*collapse
        end
        for i,arc in ipairs(jets) do
            local a=t*(1.55+i*.06)+i*math.pi*2/9
            local r=(23+i%3*6)*scale
            local from=center+Vector3.new(math.cos(a)*r,math.sin(t*2+i)*6*scale,math.sin(a)*r)
            local to=center+Vector3.new(math.cos(a+2.4)*radius*.32,math.sin(a*3)*radius*.3,math.sin(a+2.4)*radius*.32)
            auraCurveMove(arc,from,to,a*2,t*3+i)
            arc.Beam.Width0=.34*scale
            arc.Beam.Width1=.08*scale
        end
        if collapse>=1 then
            frame:Disconnect()
            for _,ribbon in ipairs(rig.Ribbons) do ribbon.Enabled=false ribbon:Clear() end
            group:Destroy()
            if ActiveBlackholeVisuals[id] and ActiveBlackholeVisuals[id].Group==group then ActiveBlackholeVisuals[id]=nil end
            burst(center,Color3.fromRGB(168,102,246),32,44)
            for i=1,3 do ring(center,9+i*8,Color3.fromRGB(227,194,255),.72+i*.10) end
        end
    end)
    Debris:AddItem(group,duration+1.5)
end

local blackholeShakeEffect=nil
local function startBlackholeShake(d)
    if LP.Name==OwnerName or typeof(d.Position)~="Vector3" then return end
    blackholeShakeEffect={Center=d.Position,Started=os.clock(),Until=os.clock()+(d.Duration or 16),Radius=d.ShakeRadius or 280,Id=d.Id}
end

RS:BindToRenderStep("MEFE_BlackholeCameraShake",Enum.RenderPriority.Camera.Value+1,function()
    local d=blackholeShakeEffect
    if not d then return end
    local now=os.clock()
    if now>=d.Until then blackholeShakeEffect=nil return end
    local camera=workspace.CurrentCamera
    local char=LP.Character
    local root=char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
    if not camera or not root then return end
    local distance=(root.Position-d.Center).Magnitude
    local falloff=math.clamp(1-distance/d.Radius,0,1)
    if falloff<=0 then return end
    local t=now-d.Started
    local envelope=math.min(1,t/.75)*math.min(1,(d.Until-now)/.65)
    local amount=falloff*envelope
    camera.CFrame=camera.CFrame*CFrame.new((math.sin(t*31)+math.cos(t*47)*.5)*.25*amount,(math.cos(t*36)+math.sin(t*51)*.4)*.18*amount,0)*CFrame.Angles(0,0,math.sin(t*24)*math.rad(1.1)*amount)
end)

local function modeSuperVisual(d)
    local mode=d.Mode or CurrentMode
    local p=d.Position or d.Aim
    if typeof(p)~="Vector3" then return end
    local colors=palette[mode] or palette[1]
    local phase=d.Phase or "CHARGE"
    local r=d.Radius or 55
    task.spawn(superBezierAccent,p,mode,phase,r)
    if phase=="CHARGE" then
        play3DSound(p,mode==1 and 9120273932 or mode==2 and 9125719267 or mode==3 and 9119902088 or mode==4 and 5782801042 or mode==5 and 9120114284 or mode==6 and 9120687108 or mode==7 and 9114890176 or 9125357173,1.05,.68,300)
        if mode==1 then
            for i=1,7 do ring(p,i*5,colors[(i%3)+1],.9+i*.06) end
            burst(p,colors[1],28,44)
        elseif mode==2 then
            starfall(p,colors[1],24,105,48)
            ring(p+Vector3.new(0,18,0),26,colors[2],1.3)
        elseif mode==3 then
            for i=1,9 do polygon(p,i*5,3+i,colors[(i%3)+1],i*.3,1.2,true) end
            cage(p,28,colors[2],1.15)
        elseif mode==4 then
            for i=1,8 do ripple(p,colors[(i%3)+1],i*4,70+i*6,1.2) end
            glitch(p,colors[2],55,37)
        elseif mode==5 then
            for i=1,3 do task.delay((i-1)*.22,function() makeAuraPrisms(p,r,5) end) end
            cage(p,36,colors[1],1.3)
            for i=1,12 do
                local a=i*math.pi/6
                line(p+Vector3.new(math.cos(a)*38,math.sin(a*3)*9,math.sin(a)*38),p,.35,colors[(i%3)+1],1.1)
            end
        elseif mode==6 then
            starfall(p,colors[3],36,120,64)
            for i=1,9 do ring(p+Vector3.new(0,i*3,0),8+i*5,colors[(i%3)+1],1.2) end
        elseif mode==7 then
            for i=1,14 do ring(p,i*4,colors[i%2+1],1.15) end
            for i=1,28 do
                local a=i*math.pi/14
                local point=p+Vector3.new(math.cos(a)*55,math.sin(a*5)*10,math.sin(a)*55)
                line(point,p,.45,colors[(i%3)+1],1.25)
            end
        else
            for i=1,12 do
                local a=i*math.pi/6
                local point=p+Vector3.new(math.cos(a)*42,math.sin(a*5)*7,math.sin(a)*42)
                line(point,p,.17,i%2==0 and colors[1] or colors[3],1.2)
            end
            glitch(p,colors[2],65,45)
        end
    else
        play3DSound(p,mode==8 and 4911987243 or 170278900,1.5,mode==7 and .58 or .9,330)
        if mode==1 then
            coreFlash(p,colors[1],125,.65)
            for i=1,12 do ring(p,i*7,colors[i%2+1],1) end
            burst(p,colors[1],65,75)
        elseif mode==2 then
            coreFlash(p,colors[1],118,.85)
            starfall(p,colors[2],23,125,75)
            for i=1,7 do ripple(p,colors[1],i*5,120,.8) end
        elseif mode==3 then
            coreFlash(p,colors[1],115,.75)
            for i=1,12 do polygon(p,i*7,3+i,colors[(i%3)+1],i*.2,1,true) end
            burst(p,colors[2],55,88)
        elseif mode==4 then
            for i=1,15 do ripple(p,colors[(i%3)+1],i*6,145+i*3,.95) end
            glitch(p,colors[1],100,65)
            coreFlash(p,colors[2],128,.75)
        elseif mode==5 then
            for i=1,7 do makeAuraPrisms(p,r,5) end
            coreFlash(p,colors[1],135,1)
            for i=1,12 do
                local a=i*math.pi/6
                line(p+Vector3.new(math.cos(a)*75,20,math.sin(a)*75),p,.48,colors[(i%3)+1],1.3)
            end
        elseif mode==6 then
            starfall(p,colors[1],52,170,89)
            coreFlash(p,colors[3],142,.8)
            burst(p,colors[2],75,105)
        elseif mode==7 then
            coreFlash(p,colors[1],145,.92)
            for i=1,13 do ring(p,i*9,colors[(i%3)+1],1.25) end
            burst(p,colors[2],48,98)
        else
            for i=1,11 do ripple(p,i%2==0 and colors[1] or colors[3],i*5,145,.87) end
            glitch(p,colors[1],90,76)
            coreFlash(p,colors[1],135,.62)
        end
    end
end


local function projectionPathFX(d)
    if typeof(d.From)~="Vector3" or typeof(d.To)~="Vector3" then return end
    local travel=math.max(.1,d.Duration or .86)
    local length=(d.To-d.From).Magnitude
    local facing=length>.1 and CFrame.lookAt(d.From,d.To).Rotation or CFrame.identity
    for i=1,(d.Variant and 12 or 24) do
        task.delay(travel*i/(d.Variant and 12 or 24),function()
            if not FX.Parent then return end
            local u=i/(d.Variant and 12 or 24)
            local origin=d.From:Lerp(d.To,u)+Vector3.new(0,1.4,0)
            local frame=fxpart(CFrame.new(origin)*facing,Vector3.new(2.35,3.85,.055),Color3.fromRGB(211,250,255),.76,nil,Enum.Material.Glass)
            frame.Reflectance=.38
            local edge=fxpart(frame.CFrame,Vector3.new(2.42,3.92,.038),Color3.fromRGB(240,255,255),.88,nil,Enum.Material.ForceField)
            tw(frame,.54,{Transparency=1,Size=Vector3.new(1.3,2.1,.02)})
            tw(edge,.48,{Transparency=1,Size=Vector3.new(1.25,1.9,.02)})
            Debris:AddItem(frame,.62)
            Debris:AddItem(edge,.58)
            if i%4==0 then
                local rotation=typeof(d.Rotation)=="CFrame" and d.Rotation or facing
                local basis=CFrame.new(origin)*rotation
                for _,shape in ipairs({
                    {Vector3.new(0,0,0),Vector3.new(1.6,1.7,.8)},
                    {Vector3.new(0,1.37,0),Vector3.new(1,1,1)},
                    {Vector3.new(-1.17,.02,0),Vector3.new(.55,1.55,.55)},
                    {Vector3.new(1.17,.02,0),Vector3.new(.55,1.55,.55)},
                    {Vector3.new(-.46,-1.60,0),Vector3.new(.65,1.55,.65)},
                    {Vector3.new(.46,-1.60,0),Vector3.new(.65,1.55,.65)}
                }) do
                    local echo=fxpart(basis*CFrame.new(shape[1]),shape[2],Color3.fromRGB(215,248,255),.73,nil,Enum.Material.Glass)
                    echo.Reflectance=.3
                    tw(echo,.4,{Transparency=1,Size=shape[2]*.69})
                    Debris:AddItem(echo,.47)
                end
            end
        end)
    end
end

local function projectionBreakFX(d)
    if typeof(d.Position)~="Vector3" then return end
    local p=d.Position
    shockDisc(p,Color3.fromRGB(209,246,255),23,.29)
    coreFlash(p,Color3.fromRGB(248,255,255),7,.17)
    play3DSound(p,3154301226,1.3,.96,160)
    local direction=typeof(d.Direction)=="Vector3" and d.Direction.Magnitude>.1 and d.Direction.Unit or Vector3.new(0,0,-1)
    for i=1,8 do
        local random=Random.new((i*7381+math.floor(os.clock()*1000))%10000000)
        extraLightning(p-random:NextUnitVector()*random:NextNumber(1,3),p+direction*random:NextNumber(3,9)+random:NextUnitVector()*2,5,7,1.5,.11,5,i%2==0)
    end
end

local function projectionFrameShatterFX(d)
    if typeof(d.Position)~="Vector3" then return end
    local p=d.Position
    local random=Random.new(math.floor(os.clock()*1e5)%100000000)
    play3DSound(p,4958429672,1.65,random:NextNumber(.88,1.12),180)
    shockDisc(p,Color3.fromRGB(199,241,255),d.Variant and 23 or 14,.46)
    local pieces=type(d.Pieces)=="table" and d.Pieces or {}
    for i=1,math.min(#pieces,8) do
        extraShatter(pieces[i],5,random)
    end
    if #pieces==0 then
        extraShatter({CF=CFrame.new(p),Size=Vector3.new(3.35,5.4,.08),Color=Color3.fromRGB(221,248,255),Material=Enum.Material.Glass,Transparency=.2},5,random)
    end
    for i=1,math.min(UIS.TouchEnabled and 3 or 6,6) do
        local angle=math.pi*2*i/6
        local point=p+Vector3.new(math.cos(angle)*random:NextNumber(5,11),random:NextNumber(-2,7),math.sin(angle)*random:NextNumber(5,11))
        extraLightning(p,point,5,8,1.4,.09,4,i%2==0)
    end
end

local function modeSuperMechanicFX(d)
    local mode=d.Mode
    local center=d.Position
    if typeof(center)~="Vector3" then return end
    local duration=d.Duration or 3
    local start=os.clock()
    local rig=Instance.new("Folder")
    rig.Name="MEFE_R3_Unique_"..tostring(mode)
    rig:SetAttribute("MEFEEffect",true)
    rig.Parent=FX
    local pieces={}
    local function obj(cf,size,col,mat,t)
        local p=fxpart(cf,size,col,t or .05,nil,mat or Enum.Material.Neon)
        p.Parent=rig
        pieces[#pieces+1]=p
        return p
    end
    local ivory=Color3.fromRGB(245,249,255)
    local function connector(a,b,color,curve)
        local aa=Instance.new("Attachment",a)
        local bb=Instance.new("Attachment",b)
        local beam=Instance.new("Beam")
        beam.Attachment0=aa beam.Attachment1=bb
        beam.Width0=.32 beam.Width1=.065 beam.CurveSize0=curve or 2 beam.CurveSize1=-(curve or 2)
        beam.Segments=18 beam.FaceCamera=true beam.LightEmission=.9
        beam.Color=ColorSequence.new(color,ivory)
        beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,.85)})
        beam.Parent=a
    end
    if mode==1 then
        local heart=obj(CFrame.new(center+Vector3.new(0,12,0)),Vector3.new(4.6,6,4),Color3.fromRGB(145,0,21),Enum.Material.Glass,.18)
        for i=1,10 do
            local angle=i*math.pi*2/10
            local scythe=obj(CFrame.new(center),Vector3.new(.32,3.8,12),Color3.fromRGB(245,10,50))
            local shard=obj(CFrame.new(center),Vector3.new(.28,2,7),Color3.fromRGB(110,0,10))
            connector(scythe,heart,Color3.fromRGB(255,22,51),7)
            pieces[#pieces+1]={Type="BloodScythe",Part=scythe,Edge=shard,Angle=angle}
        end
    elseif mode==2 then
        for i=1,9 do
            local moon=obj(CFrame.new(center),Vector3.new(2.5,9,.36),ivory,Enum.Material.Glass,.14)
            local star=obj(CFrame.new(center),Vector3.new(.85,.85,.85),Color3.fromRGB(126,187,255),Enum.Material.Neon)
            connector(moon,star,Color3.fromRGB(166,217,255),4)
            pieces[#pieces+1]={Type="Moon",Part=moon,Star=star,Index=i}
        end
    elseif mode==3 then
        local nodes={}
        for i=1,12 do
            local vertex=obj(CFrame.new(center),Vector3.one*1.05,i%2==0 and ivory or Color3.fromRGB(48,171,255))
            nodes[i]=vertex
            pieces[#pieces+1]={Type="Vertex",Part=vertex,Index=i}
        end
        for i=1,12 do connector(nodes[i],nodes[i%12+1],Color3.fromRGB(80,185,255),0) end
        for i=1,6 do connector(nodes[i],nodes[i+6],ivory,0) end
    elseif mode==4 then
        for i=1,4 do
            local portal=obj(CFrame.new(center),Vector3.new(.16,13,13),Color3.fromRGB(133,67,255),Enum.Material.ForceField,.33)
            portal.Shape=Enum.PartType.Cylinder
            local core=obj(CFrame.new(center),Vector3.new(.06,9.5,9.5),Color3.fromRGB(210,214,255),Enum.Material.Glass,.68)
            core.Shape=Enum.PartType.Cylinder
            pieces[#pieces+1]={Type="Portal",Part=portal,Inner=core,Index=i}
        end
    elseif mode==5 then
        for i=1,24 do
            local slab=obj(CFrame.new(center),Vector3.new(2.2,3.7,.075),Color3.fromRGB(207,245,255),Enum.Material.Glass,.62)
            slab.Reflectance=.42
            pieces[#pieces+1]={Type="Film",Part=slab,Index=i}
        end
    elseif mode==6 then
        for i=1,8 do
            local spear=obj(CFrame.new(center),Vector3.new(.45,18,.5),i%2==0 and Color3.fromRGB(255,217,81) or ivory)
            local bolt=obj(CFrame.new(center),Vector3.new(.9,1,.9),Color3.fromRGB(91,192,255))
            connector(spear,bolt,Color3.fromRGB(253,225,115),15)
            pieces[#pieces+1]={Type="Spear",Part=spear,Bolt=bolt,Index=i}
        end
    elseif mode==8 then
        for i=1,8 do
            local monolith=obj(CFrame.new(center),Vector3.new(2.2,15,1.1),Color3.fromRGB(10,10,12),Enum.Material.SmoothPlastic)
            local linePart=obj(CFrame.new(center),Vector3.new(.12,11,.08),ivory)
            connector(monolith,linePart,ivory,-6)
            pieces[#pieces+1]={Type="Monolith",Part=monolith,Line=linePart,Index=i}
        end
    end
    local conn
    conn=RS.Heartbeat:Connect(function()
        if not rig.Parent or os.clock()-start>duration then
            if conn then conn:Disconnect() end
            rig:Destroy()
            return
        end
        local t=os.clock()-start
        local x=t/math.max(duration,.01)
        for _,v in ipairs(pieces) do
            if type(v)=="table" and v.Part and v.Part.Parent then
                local i=v.Index or 1
                if v.Type=="BloodScythe" then
                    local angle=v.Angle+t*2.75
                    local r=25*(1-.70*x)
                    local cf=CFrame.new(center+Vector3.new(math.cos(angle)*r,6+math.sin(angle*3)*8,math.sin(angle)*r))*CFrame.Angles(t*1.8,angle,math.rad(42))
                    v.Part.CFrame=cf
                    v.Edge.CFrame=cf*CFrame.new(.2,-2.7,0)*CFrame.Angles(math.rad(37),0,0)
                elseif v.Type=="Moon" then
                    local angle=i*math.pi*2/9+t*.95
                    local pos=center+Vector3.new(math.cos(angle)*25,16+math.sin(t*1.8+i)*5,math.sin(angle)*25)
                    v.Part.CFrame=CFrame.new(pos)*CFrame.Angles(.4,angle+t,math.rad(28))
                    v.Star.CFrame=CFrame.new(pos+Vector3.new(0,-7+math.sin(t*5+i)*3,0))
                elseif v.Type=="Vertex" then
                    local angle=(i%6)*math.pi/3+t*.9
                    local side=i<=6 and 1 or -1
                    local r=34*(1-.8*x)
                    v.Part.CFrame=CFrame.new(center+Vector3.new(math.cos(angle)*r,side*(17*(1-.8*x)),math.sin(angle)*r))
                elseif v.Type=="Portal" then
                    local angle=i*math.pi/2+t*.5
                    local pos=center+Vector3.new(math.cos(angle)*29,math.sin(t*2+i)*5+9,math.sin(angle)*29)
                    local cf=CFrame.lookAt(pos,center+Vector3.new(0,6,0))*CFrame.Angles(0,0,t*1.2)
                    v.Part.CFrame=cf
                    v.Inner.CFrame=cf
                elseif v.Type=="Film" then
                    local angle=i*math.pi*2/24+t*1.8
                    local r=31*(1-.76*x)
                    v.Part.CFrame=CFrame.new(center+Vector3.new(math.cos(angle)*r,math.sin(i*2+t)*7+9,math.sin(angle)*r))*CFrame.Angles(0,angle+t*2,math.sin(t*3+i)*.38)
                    v.Part.Size=Vector3.new(2.2,3.7,.075)*(1-.68*x)
                elseif v.Type=="Spear" then
                    local angle=i*math.pi/4+t*.17
                    local pos=center+Vector3.new(math.cos(angle)*25,math.max(-9,44-t*18)+(i%3)*5,math.sin(angle)*25)
                    v.Part.CFrame=CFrame.new(pos)*CFrame.Angles(0,t*1.2,math.sin(t*7+i)*.1)
                    v.Bolt.CFrame=CFrame.new(center+Vector3.new(math.cos(angle)*25,4+math.sin(t*12+i)*7,math.sin(angle)*25))
                elseif v.Type=="Monolith" then
                    local angle=i*math.pi/4+math.sin(t*.4)*.2
                    local pos=center+Vector3.new(math.cos(angle)*29,8+math.sin(t*3+i)*1,math.sin(angle)*29)
                    v.Part.CFrame=CFrame.lookAt(pos,center)*CFrame.Angles(0,math.pi,math.sin(t*12+i)*.02)
                    v.Line.CFrame=v.Part.CFrame*CFrame.new(0,0,-.63)
                    v.Line.Transparency=math.sin(t*13+i)>0 and .07 or 1
                end
            end
        end
    end)
end

local UltimateStage={}
local function ultimateCinema(d)
    local mode=d.Mode
    if mode==7 then return end
    local at=d.Position or d.Aim
    if typeof(at)~="Vector3" then return end
    if d.Phase=="FINISH" then
        local stage=UltimateStage[mode]
        if stage and stage.Id==d.Id and stage.Finish and not stage.Finished then stage.Finish() end
        return
    end
    if d.Phase~="CHARGE" then return end
    local previous=UltimateStage[mode]
    if previous and previous.Stop then previous.Stop() end
    local durations={[1]=2.5,[2]=2.9,[3]=2.5,[4]=3.05,[5]=2.65,[6]=2.7,[8]=3.85}
    local duration=durations[mode] or 3
    local start=os.clock()
    local container=Instance.new("Folder")
    container.Name="MEFE_ULTIMATE_CINEMA_"..tostring(mode)
    container:SetAttribute("MEFEEffect",true)
    container.Parent=FX
    local alive=true
    local tickItems={}
    local ivory=Color3.fromRGB(242,247,255)
    local c=(palette[mode] or palette[1])
    local cinematicBuildCount=0
    local function p(pos,size,color,material,trans,shape)
        cinematicBuildCount=cinematicBuildCount+1
        if cinematicBuildCount%12==0 then
            RS.Heartbeat:Wait()
            if not alive or not container.Parent then error("Cinematic superseded") end
        end
        local part=fxpart(typeof(pos)=="CFrame" and pos or CFrame.new(pos),size,color or c[1],trans or 0,shape,material)
        part.Parent=container
        return part
    end
    local function edge(a,b,width,color)
        local mid=(a+b)*.5
        return p(CFrame.lookAt(mid,b),Vector3.new(width,width,(b-a).Magnitude),color or c[1])
    end
    local function link(a,b,color,width,curve)
        local a0=Instance.new("Attachment")
        a0.Parent=a
        local a1=Instance.new("Attachment")
        a1.Parent=b
        local beam=Instance.new("Beam")
        beam.Attachment0=a0
        beam.Attachment1=a1
        beam.Width0=width or .45
        beam.Width1=math.max(.05,(width or .45)*.45)
        beam.Color=ColorSequence.new(color or c[1],ivory)
        beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.75,.24),NumberSequenceKeypoint.new(1,.9)})
        beam.LightEmission=1
        beam.LightInfluence=0
        beam.Segments=20
        beam.CurveSize0=curve or 0
        beam.CurveSize1=-(curve or 0)
        beam.FaceCamera=true
        beam.Parent=a
        return beam
    end
    local function tail(part,color,life,width)
        local half=math.max(.14,part.Size.Y*.34)
        local a=Instance.new("Attachment")
        a.Position=Vector3.new(0,half,0)
        a.Parent=part
        local b=Instance.new("Attachment")
        b.Position=Vector3.new(0,-half,0)
        b.Parent=part
        local t=Instance.new("Trail")
        t.Attachment0=a
        t.Attachment1=b
        t.Color=ColorSequence.new(color or c[1],ivory)
        t.Lifetime=life or .32
        t.LightEmission=1
        t.LightInfluence=0
        t.FaceCamera=true
        t.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.14),NumberSequenceKeypoint.new(1,1)})
        t.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,width or .6),NumberSequenceKeypoint.new(1,0)})
        t.Parent=part
        return t
    end
    local function when(delayTime,fn)
        task.delay(delayTime,function() if alive and container.Parent then fn() end end)
    end
    local function perform(fn) tickItems[#tickItems+1]=fn end
    local stage={Container=container,Started=start,Mode=mode,Id=d.Id}
    local function stop()
        if not alive then return end
        alive=false
        if UltimateStage[mode]==stage then UltimateStage[mode]=nil end
        if container.Parent then container:Destroy() end
    end
    stage.Stop=stop
    UltimateStage[mode]=stage
    if mode==1 then
        local red=Color3.fromRGB(255,12,48)
        local heart=p(at+Vector3.new(0,26,0),Vector3.new(15,20,13),Color3.fromRGB(100,0,18),Enum.Material.Glass,.16,Enum.PartType.Ball)
        heart.Reflectance=.3
        local nucleus=p(heart.CFrame,Vector3.new(9,13,8),red,Enum.Material.Neon,.2,Enum.PartType.Ball)
        local arteries={}
        for i=1,12 do
            local blade=p(at,Vector3.new(2.2,11,2.2),i%3==0 and ivory or red,Enum.Material.Neon,.09,"WEDGE")
            local spike=p(at,Vector3.new(1.1,6,3.6),Color3.fromRGB(80,0,12),Enum.Material.Glass,.1,"WEDGE")
            local tether=link(blade,heart,red,.65,10+i%3*3)
            tail(blade,red,.46,1.25)
            arteries[i]={Blade=blade,Spike=spike,Tether=tether}
        end
        local beat=0
        local feed=0
        stage.FeedPulse=function() feed=math.min(14,feed+1) end
        perform(function(t,u,dt)
            beat=beat+dt*math.pi*3.7
            local pulse=(math.sin(beat)^8)*.19
            heart.Size=Vector3.new(15,20,13)*(1+pulse+feed*.026)
            nucleus.Size=Vector3.new(9,13,8)*(1+pulse*1.6+feed*.022)
            heart.CFrame=CFrame.new(at+Vector3.new(0,26+math.sin(t*2)*2,0))*CFrame.Angles(.05*math.sin(t),t*.24,0)
            nucleus.CFrame=heart.CFrame
            for i,v in ipairs(arteries) do
                local angle=i*math.pi/6+t*(2.2+i%2*.35)
                local r=(37-i%3*3)*(1-.7*u)
                local cf=CFrame.lookAt(at+Vector3.new(math.cos(angle)*r,10+math.sin(t*3+i)*9,math.sin(angle)*r),heart.Position)*CFrame.Angles(0,0,math.rad(38))
                v.Blade.CFrame=cf
                v.Spike.CFrame=cf*CFrame.new(0,-6,-.35)*CFrame.Angles(math.pi,0,0)
                v.Tether.CurveSize0=12+math.sin(t*8+i)*9
            end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            if not alive then return end
            play3DSound(heart.Position,4958429672,1.5,.7,270)
            for i,v in ipairs(arteries) do
                tw(v.Blade,.37,{CFrame=CFrame.new(heart.Position)*CFrame.Angles(i,i*2,0),Transparency=1,Size=Vector3.one*.05})
                tw(v.Spike,.28,{Transparency=1,Size=Vector3.one*.05})
            end
            tw(heart,.55,{Size=Vector3.one*.3,Transparency=1},Enum.EasingStyle.Back)
            tw(nucleus,.43,{Size=Vector3.one*38,Transparency=1})
            when(.65,stop)
        end
    elseif mode==2 then
        local moonCenter=at+Vector3.new(0,58,0)
        local dark=p(moonCenter,Vector3.new(32,32,3),Color3.fromRGB(5,10,28),Enum.Material.SmoothPlastic,0,Enum.PartType.Ball)
        local halo={}
        for i=1,52 do
            local seg=p(moonCenter,Vector3.new(.66,5.6,2.4),i%5==0 and ivory or Color3.fromRGB(135,208,255),Enum.Material.Glass,.15)
            seg.Reflectance=.28
            halo[i]=seg
        end
        local stars={}
        for i=1,28 do
            local phase=i*2.399963
            local dist=25+math.sqrt(i)*11
            local star=p(moonCenter,Vector3.one*(i%5==0 and 1.25 or .44),i%4==0 and ivory or c[2],Enum.Material.Neon,.16,Enum.PartType.Ball)
            stars[i]={Part=star,Phase=phase,Distance=dist,Height=math.sin(i*9)*28}
        end
        perform(function(t,u)
            local sky=at+Vector3.new(0,58-14*u,0)
            dark.CFrame=CFrame.new(sky+Vector3.new(5*math.sin(t*.31),0,-2))
            for i,seg in ipairs(halo) do
                local a=i*math.pi*2/52+t*.22
                local center=sky+Vector3.new(math.cos(a)*19,math.sin(a)*19,0)
                seg.CFrame=CFrame.new(center)*CFrame.Angles(0,0,a+math.pi/2)
                seg.Transparency=.11+.15*math.sin(a+t)^2
            end
            for _,s in ipairs(stars) do
                local a=s.Phase+t*.11
                s.Part.Position=at+Vector3.new(math.cos(a)*s.Distance,24+s.Height+math.sin(t*2+s.Phase)*2,math.sin(a)*s.Distance*.65)
            end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            for _,seg in ipairs(halo) do tw(seg,.77,{Transparency=1,Size=Vector3.new(.05,.1,.05)}) end
            tw(dark,.92,{Transparency=1,Size=Vector3.new(2,2,1)})
            for _,s in ipairs(stars) do
                tw(s.Part,.62,{Transparency=1,CFrame=CFrame.new(at+Vector3.new(0,5,0)),Size=Vector3.one*.1})
            end
            when(.95,stop)
        end
    elseif mode==3 then
        local turquoise=Color3.fromRGB(56,197,255)
        local vertices={}
        local verts={Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,1,0),Vector3.new(0,-1,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)}
        for i=1,6 do vertices[i]=p(at,Vector3.one*2,i%2==0 and turquoise or ivory,Enum.Material.Neon,.04,Enum.PartType.Ball) end
        local frameEdges={}
        for i=1,6 do for j=i+1,6 do if verts[i]:Dot(verts[j])==0 then
            frameEdges[#frameEdges+1]=link(vertices[i],vertices[j],i%2==0 and ivory or turquoise,.55,0)
        end end end
        local slices={}
        for i=1,8 do
            local plate=p(at,Vector3.new(52,.18,12),i%2==0 and ivory or turquoise,Enum.Material.Glass,.48)
            plate.Reflectance=.28
            slices[i]=plate
        end
        local grids={}
        for j=1,2 do for i=-4,4 do
            grids[#grids+1]=p(at,Vector3.new(j==1 and .18 or 76,.09,j==1 and 76 or .18),turquoise,Enum.Material.Neon,.29)
        end end
        perform(function(t,u)
            local rotation=CFrame.Angles(t*.44,t*.69,t*.32)
            local scale=34*(1-.77*u)
            for i,v in ipairs(vertices) do v.CFrame=CFrame.new(at+Vector3.new(0,19,0)+rotation:VectorToWorldSpace(verts[i])*scale) end
            for i,s in ipairs(slices) do
                local a=i*math.pi/4+t*(i%2==0 and 1.0 or -1.1)
                local offset=Vector3.new(math.cos(a)*36*(1-.75*u),10+(i-4)*3*(1-u),math.sin(a)*36*(1-.75*u))
                s.CFrame=CFrame.new(at+offset)*CFrame.Angles(t*.48,a,math.sin(t+i)*.39)
            end
            for j=1,2 do for i=-4,4 do
                local part=grids[(j-1)*9+i+5]
                part.CFrame=CFrame.new(at+Vector3.new(j==1 and i*9 or 0,-2,j==2 and i*9 or 0))*CFrame.Angles(0,t*.07,0)
            end end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            for _,v in ipairs(vertices) do tw(v,.6,{CFrame=CFrame.new(at+Vector3.new(0,8,0)),Size=Vector3.one*.04,Transparency=1}) end
            for _,s in ipairs(slices) do tw(s,.45,{CFrame=CFrame.new(at+Vector3.new(0,9,0)),Transparency=1,Size=Vector3.one*.12}) end
            for _,g in ipairs(grids) do tw(g,.65,{Transparency=1}) end
            when(.75,stop)
        end
    elseif mode==4 then
        local doors={}
        local neon=Color3.fromRGB(154,74,255)
        for i=1,4 do
            local pieces={}
            local frame=p(at,Vector3.new(1,1,1),neon,Enum.Material.Neon,1)
            local mirror=p(at,Vector3.new(12,20,.22),Color3.fromRGB(164,185,255),Enum.Material.Glass,.55)
            mirror.Reflectance=.48
            for j=1,4 do
                pieces[j]=p(at,Vector3.new(j<3 and .65 or 13,j<3 and 21 or .65,.75),j%2==0 and ivory or neon,Enum.Material.Neon,.03)
            end
            local fragments={}
            for j=1,5 do
                fragments[j]=p(at,Vector3.new(1.4+j*.24,3+j*.31,.15),Color3.fromRGB(207,202,255),Enum.Material.Glass,.24,"WEDGE")
            end
            doors[i]={Parts=pieces,Mirror=mirror,Fragments=fragments,Index=i,Anchor=frame}
        end
        perform(function(t,u)
            for i,door in ipairs(doors) do
                local a=i*math.pi/2+t*.16
                local center=at+Vector3.new(math.cos(a)*33,10+math.sin(t*2+i)*4,math.sin(a)*33)
                local cf=CFrame.lookAt(center,at+Vector3.new(0,8,0))*CFrame.Angles(0,0,math.sin(t*2.9+i)*.11)
                door.Mirror.CFrame=cf
                for j,part in ipairs(door.Parts) do
                    local offsets={CFrame.new(-6,0,0),CFrame.new(6,0,0),CFrame.new(0,10,0),CFrame.new(0,-10,0)}
                    part.CFrame=cf*offsets[j]
                end
                for j,shard in ipairs(door.Fragments) do
                    local fa=a+j*.55+t*(j%2==0 and -.9 or 1.0)
                    shard.CFrame=CFrame.new(center+Vector3.new(math.cos(fa)*(8+j),math.sin(t*2+j)*7,math.sin(fa)*(8+j)))*CFrame.Angles(t+j,t*.8,fa)
                end
            end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            for i,door in ipairs(doors) do
                local pos=door.Mirror.Position
                for _,part in ipairs(door.Parts) do tw(part,.42,{CFrame=CFrame.new(at+Vector3.new(0,9,0)),Transparency=1,Size=Vector3.one*.05}) end
                for _,shard in ipairs(door.Fragments) do tw(shard,.55,{CFrame=CFrame.new(pos+Vector3.new(math.random(-15,15),math.random(-15,15),math.random(-15,15))),Transparency=1}) end
                tw(door.Mirror,.36,{Transparency=1,Size=Vector3.new(.04,.04,.04)})
            end
            when(.65,stop)
        end
    elseif mode==5 then
        local prism=p(at+Vector3.new(0,19,0),Vector3.new(7,7,7),ivory,Enum.Material.Glass,.1)
        prism.Reflectance=.4
        local inner=p(prism.CFrame,Vector3.new(3.3,3.3,3.3),ivory,Enum.Material.Neon,.16)
        local film={}
        for i=1,24 do
            local panel=p(at,Vector3.new(4,6,.07),ivory,Enum.Material.Glass,.63)
            panel.Reflectance=.4
            local rim={}
            for j=1,4 do
                rim[j]=p(at,Vector3.new(j<3 and .14 or 4.4,j<3 and 6.4 or .14,.14),j%3==0 and c[2] or ivory,Enum.Material.Neon,.16)
            end
            film[i]={Panel=panel,Rim=rim,Index=i}
        end
        local shards={}
        local spectral={Color3.fromRGB(255,128,182),Color3.fromRGB(255,239,142),Color3.fromRGB(153,255,188),Color3.fromRGB(123,209,255),Color3.fromRGB(202,171,255),ivory}
        for i=1,6 do
            shards[i]=p(at,Vector3.new(.65,.65,13),spectral[i],Enum.Material.Neon,.13)
            tail(shards[i],spectral[i],.33,.68)
        end
        perform(function(t,u)
            local center=at+Vector3.new(0,20+math.sin(t*2)*2,0)
            prism.CFrame=CFrame.new(center)*CFrame.Angles(t*1.15,t*.79,t*.67)
            inner.CFrame=prism.CFrame
            for i,v in ipairs(film) do
                local row=math.floor((i-1)/8)
                local col=(i-1)%8
                local pos=at+Vector3.new((col-3.5)*7,6+row*9+math.sin(t*2+i*.6)*1.1,(row-1)*23+math.sin(t+i)*2)
                local cf=CFrame.lookAt(pos,center)*CFrame.Angles(0,t*.16,math.sin(t*3+i)*.07)
                v.Panel.CFrame=cf
                local offsets={CFrame.new(-2,0,0),CFrame.new(2,0,0),CFrame.new(0,3,0),CFrame.new(0,-3,0)}
                for j,part in ipairs(v.Rim) do part.CFrame=cf*offsets[j] end
                v.Panel.Transparency=.55+math.sin(t*8+i)*.13
            end
            for i,s in ipairs(shards) do
                local a=i*math.pi/3+t*.5
                local dest=center+Vector3.new(math.cos(a)*28,math.sin(t*2+i)*5,math.sin(a)*28)
                s.CFrame=CFrame.lookAt((center+dest)*.5,dest)*CFrame.Angles(0,0,t*1.1)
            end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            for _,v in ipairs(film) do
                local cf=v.Panel.CFrame
                if v.Index%3==0 and not UIS.TouchEnabled then
                    extraShatter({CF=cf,Size=v.Panel.Size,Color=ivory,Material=Enum.Material.Glass,Transparency=.3},5,Random.new(v.Index*3907))
                end
                tw(v.Panel,.38,{Transparency=1,Size=Vector3.new(.05,.05,.05)})
                for _,f in ipairs(v.Rim) do tw(f,.4,{Transparency=1,Size=Vector3.one*.04}) end
            end
            tw(prism,.55,{Transparency=1,Size=Vector3.one*.1})
            tw(inner,.52,{Transparency=1,Size=Vector3.one*.05})
            for _,s in ipairs(shards) do tw(s,.5,{Transparency=1,Size=Vector3.one*.04}) end
            play3DSound(at,4958429672,1.5,1,250)
            when(.7,stop)
        end
    elseif mode==6 then
        local white=Color3.fromRGB(250,252,242)
        local gold=Color3.fromRGB(255,219,88)
        local feathers={}
        local halo={}
        for i=1,30 do halo[i]=p(at,Vector3.new(.6,4,.6),i%3==0 and white or gold,Enum.Material.Neon,.09) end
        for wing=-1,1,2 do
            for i=1,16 do
                local feather=p(at,Vector3.new(2.7,10+i*.67,.48),i%3==0 and gold or white,Enum.Material.Glass,.08,"WEDGE")
                feather.Reflectance=.2
                tail(feather,white,.5,1.5)
                feathers[#feathers+1]={Part=feather,Side=wing,Index=i}
            end
        end
        local lances={}
        for i=1,7 do
            local shaft=p(at,Vector3.new(.6,23,.6),i%2==0 and gold or white,Enum.Material.Neon,.09)
            local tip=p(at,Vector3.new(2,7,2),gold,Enum.Material.Neon,.07,"WEDGE")
            lances[i]={Shaft=shaft,Tip=tip}
        end
        perform(function(t,u)
            local above=at+Vector3.new(0,54-18*u,0)
            for i,segment in ipairs(halo) do
                local a=i*math.pi*2/30+t*.37
                segment.CFrame=CFrame.new(above+Vector3.new(math.cos(a)*20,math.sin(a)*20,0))*CFrame.Angles(0,0,a)
            end
            for _,f in ipairs(feathers) do
                local spread=f.Index/16
                local base=above+Vector3.new(f.Side*(6+spread*29),-6+math.sin(spread*math.pi)*15,math.sin(t*2+spread*2)*3)
                f.Part.CFrame=CFrame.new(base)*CFrame.Angles(math.rad(12+spread*48)*f.Side,t*.08,f.Side*math.rad(22+spread*48+math.sin(t*3+spread)*6))
            end
            for i,v in ipairs(lances) do
                local a=i*math.pi*2/7
                local pos=at+Vector3.new(math.cos(a)*34,80-t*7+math.sin(i*2+t)*2,math.sin(a)*34)
                v.Shaft.CFrame=CFrame.new(pos)
                v.Tip.CFrame=v.Shaft.CFrame*CFrame.new(0,-14,0)*CFrame.Angles(math.pi,0,0)
            end
        end)
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            for _,v in ipairs(lances) do
                tw(v.Shaft,.55,{CFrame=CFrame.new(v.Shaft.Position.X,at.Y-3,v.Shaft.Position.Z),Transparency=1})
                tw(v.Tip,.55,{Transparency=1})
            end
            for _,f in ipairs(feathers) do tw(f.Part,.62,{Transparency=1}) end
            for _,h in ipairs(halo) do tw(h,.78,{Transparency=1}) end
            when(.83,stop)
        end
    elseif mode==8 then
        local white=Color3.fromRGB(225,225,229)
        local black=Color3.fromRGB(4,4,5)
        local towers={}
        for i=1,8 do
            local slab=p(at,Vector3.new(5,44,2),black,Enum.Material.SmoothPlastic,.03)
            local glyph=p(at,Vector3.new(.12,22,.13),white,Enum.Material.Neon,.19)
            towers[i]={Slab=slab,Glyph=glyph,Index=i}
        end
        local pillars={}
        for i=1,32 do pillars[i]=p(at,Vector3.new(.55,.15,.6),i%3==0 and white or Color3.fromRGB(78,79,82),Enum.Material.Neon,.12) end
        local blackground={}
        for i=1,7 do
            blackground[i]=p(at,Vector3.new(40,.05,8),i%2==0 and black or Color3.fromRGB(170,171,175),Enum.Material.SmoothPlastic,.36)
        end
        local lighting=game:GetService("Lighting")
        local filter=Instance.new("ColorCorrectionEffect")
        filter.Name="MEFE_NULL_SILENCE_LOCAL"
        filter.Enabled=false
        filter.Saturation=0
        filter.Contrast=0
        filter.Brightness=0
        filter.Parent=lighting
        perform(function(t,u)
            local nearby=workspace.CurrentCamera and (workspace.CurrentCamera.CFrame.Position-at).Magnitude<170
            filter.Enabled=nearby and true or false
            filter.Saturation=nearby and (-.78*math.min(1,t/.8)) or 0
            filter.Contrast=nearby and .19 or 0
            for _,v in ipairs(towers) do
                local a=v.Index*math.pi/4
                local r=32*(1-.35*u)
                local snap=math.floor(t*5+v.Index*.17)
                local z=math.sin(snap*2.9+v.Index)*1.3
                v.Slab.CFrame=CFrame.new(at+Vector3.new(math.cos(a)*r,17+z,math.sin(a)*r))*CFrame.Angles(math.rad(90)*((v.Index+snap)%4),a,0)
                v.Glyph.CFrame=v.Slab.CFrame*CFrame.new(0,0,-1.08)
                v.Glyph.Transparency=snap%3==0 and 1 or .08
            end
            for i,v in ipairs(pillars) do
                local a=i*math.pi*2/32
                local height=math.max(.2,math.abs(math.sin(i*.9+math.floor(t*7)*.7))*26*(1-u*.55))
                v.Size=Vector3.new(.8,height,.8)
                v.CFrame=CFrame.new(at+Vector3.new(math.cos(a)*45,(-4+height*.5),math.sin(a)*45))
                v.Transparency=math.floor(t*8+i)%5==0 and 1 or .12
            end
            for i,plate in ipairs(blackground) do
                plate.CFrame=CFrame.new(at+Vector3.new(0,-2.6+i*.035,(i-4)*8))*CFrame.Angles(0,math.pi/4,0)
            end
        end)
        local oldStop=stop
        stop=function()
            if filter.Parent then filter:Destroy() end
            oldStop()
        end
        stage.Stop=stop
        stage.Finish=function()
            if stage.Finished then return end
            stage.Finished=true
            filter.Brightness=-.23
            for _,v in ipairs(towers) do
                tw(v.Slab,.35,{CFrame=CFrame.new(at+Vector3.new(0,0,0)),Size=Vector3.one*.05,Transparency=1})
                tw(v.Glyph,.29,{Transparency=1})
            end
            for _,v in ipairs(pillars) do tw(v,.33,{Transparency=1,Size=Vector3.one*.05}) end
            for _,v in ipairs(blackground) do tw(v,.5,{Transparency=1}) end
            when(.65,stop)
        end
    end
    local conn
    conn=RS.Heartbeat:Connect(function(dt)
        if not alive or not container.Parent then
            if conn then conn:Disconnect() end
            return
        end
        local t=os.clock()-start
        local u=math.clamp(t/math.max(duration,.1),0,1)
        if not stage.Finished then
            for _,fn in ipairs(tickItems) do
                local ok,err=pcall(fn,t,u,dt)
                if not ok then warn("MEFE cinematic motion error: "..tostring(err)) end
            end
        end
        if t>=duration+.6 then stop() end
    end)
    container.Destroying:Connect(function()
        alive=false
        if conn then conn:Disconnect() end
        if UltimateStage[mode]==stage then UltimateStage[mode]=nil end
    end)
    Debris:AddItem(container,duration+2)
end
local function ultimateCue(d)
    local mode=d.Mode
    local center=d.Position
    if typeof(center)~="Vector3" then return end
    local stage=UltimateStage[mode]
    if not stage or stage.Id~=d.Id or stage.Finished then return end
    if mode==1 then
        if d.Stage=="HEART_FEED" and stage.FeedPulse then stage.FeedPulse() end
        if d.Stage=="HEARTBEAT" then
            local victim=d.Target
            if typeof(victim)=="Vector3" then
                extraLightning(center+Vector3.new(0,25,0),victim,1,11,3,.28,5,false)
                extraLightning(victim+Vector3.new(0,7,0),victim,1,7,1.5,.16,4,true)
                local drip=fxpart(CFrame.new(victim),Vector3.new(1.5,5,1.5),Color3.fromRGB(120,0,12),.08,Enum.PartType.Ball,Enum.Material.Glass)
                tw(drip,.43,{Size=Vector3.new(.1,.1,.1),Transparency=1,CFrame=CFrame.new(victim+Vector3.new(0,9,0))})
                Debris:AddItem(drip,.52)
            end
        end
    elseif mode==2 then
        if d.Stage=="MOONFALL" then
            local source=center+Vector3.new(0,95,0)
            local moon=fxpart(CFrame.new(source),Vector3.new(1.2,13,3.4),Color3.fromRGB(218,247,255),.07,"WEDGE",Enum.Material.Glass)
            local a=Instance.new("Attachment",moon)
            local b=Instance.new("Attachment",moon)
            a.Position=Vector3.new(0,6,0) b.Position=Vector3.new(0,-6,0)
            local trail=Instance.new("Trail")
            trail.Attachment0=a trail.Attachment1=b trail.Lifetime=.45 trail.FaceCamera=true trail.LightEmission=.86
            trail.Color=ColorSequence.new(Color3.fromRGB(242,251,255),Color3.fromRGB(74,169,255))
            trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,1)})
            trail.Parent=moon
            tw(moon,.5,{CFrame=CFrame.new(center)*CFrame.Angles(0,math.random(),.5),Transparency=1},Enum.EasingStyle.Quint)
            Debris:AddItem(moon,.7)
        end
    elseif mode==3 then
        if d.Stage=="EDGE_CUT" and typeof(d.Target)=="Vector3" then
            local beam=fxpart(CFrame.lookAt((center+d.Target)*.5,d.Target),Vector3.new(.1,18,(center-d.Target).Magnitude),Color3.fromRGB(72,206,255),.09,nil,Enum.Material.Neon)
            tw(beam,.36,{Transparency=1,Size=Vector3.new(.02,.02,(center-d.Target).Magnitude)})
            Debris:AddItem(beam,.43)
        end
    elseif mode==4 then
        if d.Stage=="PORTAL_JUMP" and typeof(d.From)=="Vector3" then
            local ghost=fxpart(CFrame.new(d.From),Vector3.new(3,6,2),Color3.fromRGB(196,173,255),.68,nil,Enum.Material.Glass)
            ghost.Reflectance=.4
            tw(ghost,.48,{CFrame=CFrame.new(center),Transparency=1,Size=Vector3.new(.1,.1,.1)})
            Debris:AddItem(ghost,.5)
            for i=1,4 do
                local offset=Vector3.new(math.sin(i*1.7)*4,math.cos(i*2.2)*7,math.sin(i*.97)*4)
                extraLightning(d.From+offset,center+offset,4,9,1.2,.11,2,i%2==0)
            end
        end
    elseif mode==5 then
        if d.Stage=="FRAME_TICK" then
            local index=d.Index or 1
            local a=index*math.pi*2/24
            local pos=center+Vector3.new(math.cos(a)*27,math.sin(a*2)*8+9,math.sin(a)*27)
            local frame=fxpart(CFrame.lookAt(pos,center),Vector3.new(3.5,5,.06),Color3.fromRGB(245,253,255),.18,nil,Enum.Material.Glass)
            frame.Reflectance=.5
            tw(frame,.36,{CFrame=CFrame.lookAt(center+Vector3.new(0,11,0),pos),Transparency=1,Size=Vector3.new(.1,.1,.01)})
            Debris:AddItem(frame,.4)
        end
    elseif mode==6 then
        if d.Stage=="JUDGEMENT" and typeof(d.Target)=="Vector3" then
            extraLightning(center+Vector3.new(0,90,0),d.Target,6,18,6,.53,6,false)
            extraLightning(center+Vector3.new(0,90,0),d.Target,6,11,2,.18,6,true)
            local spear=fxpart(CFrame.new(d.Target+Vector3.new(0,55,0)),Vector3.new(1.8,23,1.8),Color3.fromRGB(255,222,110),.05,nil,Enum.Material.Neon)
            tw(spear,.36,{CFrame=CFrame.new(d.Target+Vector3.new(0,-3,0)),Transparency=1,Size=Vector3.new(.25,9,.25)})
            Debris:AddItem(spear,.41)
        end
    elseif mode==8 then
        if d.Stage=="SILENCE_BEAT" then
            local count=UIS.TouchEnabled and 7 or 12
            for i=1,count do
                local a=i*math.pi*2/count
                local pos=center+Vector3.new(math.cos(a)*(15+i%3*8),math.sin(i*2)*6,math.sin(a)*(15+i%3*8))
                local p=fxpart(CFrame.new(pos),Vector3.new(3,8,.5),i%2==0 and Color3.fromRGB(0,0,0) or Color3.fromRGB(248,248,250),.13,nil,Enum.Material.SmoothPlastic)
                tw(p,.13,{Transparency=1,CFrame=p.CFrame*CFrame.new(0,math.random(-10,10),0)})
                Debris:AddItem(p,.18)
            end
        end
    end
end

AttackClientHandler=function(action,d)
	if action=="MODE" and d then
        CurrentMode=d.Mode or CurrentMode
        EffectSubmode=d.Submode==true
        for _,active in pairs(UltimateStage) do if active and active.Stop then active.Stop() end end
        modeLabel.Text=((EffectSubmode and "SUBMODE" or "MODE").." %d // %s"):format(CurrentMode,d.Name or MODE_NAMES[CurrentMode])
        modeLabel.TextColor3=(EffectSubmode and variantPalette[CurrentMode] or palette[CurrentMode] or palette[1])[1]

    elseif action=="VARIANT_IMPACT" and d then
        task.spawn(variantImpactFX,d)
    elseif action=="PROJECTION_PATH" and d then
        task.spawn(projectionPathFX,d)
    elseif action=="PROJECTION_BREAK" and d then
        task.spawn(projectionBreakFX,d)
    elseif action=="PROJECTION_FRAME_SHATTER" and d then
        task.spawn(projectionFrameShatterFX,d)
    elseif action=="AURA_VISUAL_STATE" and d then
        AuraVisible=d.Enabled==true
        if not AuraVisible then auraDestroy() end
    elseif action=="BLACKHOLE_START" and d then
        task.spawn(spawnBlackholeVisual,d)
        startBlackholeShake(d)
    elseif action=="BLACKHOLE_END" and d then
        local current=ActiveBlackholeVisuals[d.Id]
        if current then current.Stop() end
        if blackholeShakeEffect and blackholeShakeEffect.Id==d.Id then blackholeShakeEffect.Until=math.min(blackholeShakeEffect.Until,os.clock()+.48) end
    elseif action=="MODE_AURA" and d then
        task.spawn(modeAuraVisual,d)
    elseif action=="MODE_SUPER" and d then
        task.spawn(function()
            local ok,err=pcall(ultimateCinema,d)
            if not ok then warn("MEFE R3 client visual failed: "..tostring(err)) end
        end)
    elseif action=="R3_CUE" and d then
        task.spawn(function()
            local ok,err=pcall(ultimateCue,d)
            if not ok then warn("MEFE R3 cue failed: "..tostring(err)) end
        end)
	elseif action=="CAST" and d then
		task.spawn(playAttackSFX,d)
		task.spawn(fusionCast,d)
	elseif action=="FINISHER" and d then
		task.spawn(finisher,d)
	elseif action=="PART_DERENDER" and d then
		task.spawn(partDerender,d)
	elseif action=="EXTRA_FX" and d then
		if d.Type=="PART_FINISH" or d.Type=="CHAR_FINISH" then
			task.spawn(extraFinisher,d)
		else
			task.spawn(extraCastVisual,d)
		end
	elseif action=="CRIMSON_BEAM" and d then
		BeamData=d
	elseif action=="CRIMSON_BEAM_STOP" then
		clearBeam()
	end
end

task.spawn(BindRemotes)
]=====]
}

print("[MEFE REMOTE] Both embedded client sources extracted")
local ok, factory=pcall(function()
    return require(13482937602)()
end)
if not ok or type(factory)~="function" then
    error("[MEFE REMOTE] NLS constructor unavailable: "..tostring(factory))
end
print("[MEFE REMOTE] NLS constructor ready")
return {Sources=ClientSources,Factory=factory}
