local addonName = ...

local VERSION = "1.0.5"
local PREFIX = "|cffd9a441Ravioli Finder:|r "
local WIRE_PREFIX = "[EAF2]"
local CHAT_WIRE_PREFIX = "EAF4:"
local LEGACY_IDENTITY_WIRE_PREFIX = "EAF3:"
local LEGACY_CHAT_WIRE_PREFIX = "EAF2:"
local LISTING_WIRE_PREFIX = "EAFL:"
local REMOVAL_WIRE_PREFIX = "EAFX:"
local REQUEST_WIRE_PREFIX = "EAFR:"
local RESPONSE_WIRE_PREFIX = "EAFA:"
local REFRESH_WIRE_PREFIX = "EAFQ:"
local PRESENCE_WIRE_PREFIX = "EAFP:"
local CHANNEL_NAME = "RavioliFinder"
local HEARTBEAT_SECONDS = 30 * 60
local REMOTE_TIMEOUT_SECONDS = 35 * 60
local PEER_TIMEOUT_SECONDS = 35 * 60
local MANUAL_REFRESH_COOLDOWN_SECONDS = 60
local APPLICATION_COOLDOWN_SECONDS = 2 * 60
local INACTIVE_REMOVAL_SECONDS = 60 * 60
local EXPIRY_VALUES = { 5, 10, 15, 20, 25, 30 }

local COLORS = {
    background = { 0.035, 0.043, 0.055, 0.98 },
    panel = { 0.065, 0.075, 0.095, 0.98 },
    panelLight = { 0.090, 0.102, 0.125, 1 },
    border = { 0.22, 0.25, 0.30, 1 },
    gold = { 0.86, 0.64, 0.25, 1 },
    text = { 0.92, 0.92, 0.92, 1 },
    muted = { 0.58, 0.62, 0.68, 1 },
    green = { 0.35, 0.78, 0.48, 1 },
    red = { 0.88, 0.32, 0.30, 1 },
}

local categories = {
    { key = "ALL", name = "All Activities", short = "All" },
    { key = "RAID", name = "Raids", short = "Raid" },
    { key = "QUEST", name = "Group Quests", short = "Quest" },
    { key = "WORLD", name = "Open World", short = "World" },
    { key = "CUSTOM", name = "Custom", short = "Custom" },
}

local categoryByKey = {}
for _, category in ipairs(categories) do
    categoryByKey[category.key] = category
end

local gameModes = {
    { key = "NORMAL", name = "Normal" },
    { key = "HC1", name = "HC1" },
    { key = "HC2", name = "HC2" },
    { key = "HC3", name = "HC3" },
    { key = "HC4", name = "HC4" },
    { key = "HC5", name = "HC5" },
}

local gameModeByKey = {}
for _, gameMode in ipairs(gameModes) do
    gameModeByKey[gameMode.key] = gameMode
end

local state = {
    category = "ALL",
    search = "",
    selectedID = nil,
    page = 1,
    pageSize = 5,
}

local runtime = {
    remoteListings = {},
    applicants = {},
    declineLockouts = {},
    inviteReservations = {},
    incomingChunks = {},
    seenListings = {},
    requested = {},
    pendingInvites = {},
    peerGameModes = {},
    currentGameMode = nil,
    lastManualRefreshAt = 0,
    lastRefreshResponseAt = 0,
    pendingRefreshBroadcastAt = nil,
    outboundQueue = {},
    outboundCooldown = 0,
    outboundMessagesSent = 0,
    chunkPartsReceived = 0,
    chunkMessagesCompleted = 0,
    compactListingsReceived = 0,
    malformedCompactListings = 0,
    channelID = 0,
    elapsed = 0,
    heartbeatElapsed = 0,
    channelRetryElapsed = 0,
    peers = {},
    lastReceivedAt = 0,
    allChannelEvents = 0,
    finderChannelEvents = 0,
    protocolMessages = 0,
    otherProtocolMessages = 0,
    processedRemotePayloads = 0,
    importedListingPackets = 0,
    outboundListingPackets = 0,
    lastRemoteCommand = "",
    lastChannelLabel = "",
    lastRawSender = "",
    lastTransportSender = "",
    lastTransportSession = "",
    lastOtherSender = "",
    sessionID = "",
}

local defaultSettings = {
    shareListings = true,
    autoClose = true,
    autoInvite = false,
    autoWhisperInviteErrors = true,
    inviteFailureWhisper = "Please go to {group_mode} to join.",
    notifications = true,
    notifyListings = false,
    sounds = true,
    expiryMinutes = 15,
    showLauncher = true,
    lockLauncher = false,
    linkQuestLog = false,
}

local mainFrame
local createFrame
local listingRows = {}
local categoryButtons = {}
local details = {}
local searchBox
local listSummary
local emptyState
local previousButton
local nextButton
local pageText
local questLogHooked = false
local questLogVisibilityHooked = false
local settingsFrame
local applicantsFrame
local launcherButton
local networkStatusText
local refreshButton
local BroadcastListing
local BroadcastRemoval
local BroadcastAllListings
local SendJoinRequest
local RefreshGroupState
local RefreshLauncher
local OpenSettingsFrame
local OpenApplicantsFrame
local AcceptApplicant
local DeclineApplicant
local EnsureChannel
local HandleChannelMessage
local ToggleMainFrame
local ShowMainFrame
local RefreshSharedListings
local QueueDirectAction
local UpdateListings

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message))
end

local function Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function StripChatFormatting(value)
    local text = tostring(value or "")
    text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|[rR]", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

local function KeepAllowedNameCharacters(value)
    local result = {}
    local index = 1
    value = tostring(value or "")
    while index <= #value do
        local byte = value:byte(index)
        if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
            result[#result + 1] = value:sub(index, index)
            index = index + 1
        elseif byte >= 195 and byte <= 197 and index < #value then
            local continuation = value:byte(index + 1)
            if continuation and continuation >= 128 and continuation <= 191 then
                result[#result + 1] = value:sub(index, index + 1)
                index = index + 2
            else
                index = index + 1
            end
        else
            index = index + 1
        end
    end
    return table.concat(result, "")
end

local function SanitizePlayerName(value)
    local raw = tostring(value or "")
    local linkedName = raw:match("|Hplayer:([^:|]+)")
    local text = StripChatFormatting(linkedName or raw)
    local lastBracket
    for bracket in text:gmatch("%[([^%]]+)%]") do lastBracket = bracket end
    text = Trim(text:gsub("%b[]", " "))
    if text == "" then text = lastBracket or "" end
    text = text:gsub(":%s*$", "")
    text = text:match("([^%s]+)%s*$") or text
    text = text:match("^([^-]+)") or text
    local clean = KeepAllowedNameCharacters(text)
    return clean ~= "" and clean or "Unknown"
end

local function IsLocalPlayerName(value)
    local candidate = SanitizePlayerName(value)
    local playerName = SanitizePlayerName(UnitName("player") or "")
    return candidate ~= "Unknown"
        and playerName ~= "Unknown"
        and candidate:lower() == playerName:lower()
end

local function GetSessionID()
    if runtime.sessionID == "" then
        local identity = tostring(UnitGUID and UnitGUID("player") or UnitName("player") or "Unknown")
        local checksum = 0
        for index = 1, #identity do
            checksum = ((checksum * 33) + identity:byte(index)) % 16777216
        end
        runtime.sessionID = string.format("%06X%04X%04X", checksum,
            time() % 65536, math.random(0, 65535))
    end
    return runtime.sessionID
end

local function ContainsFinderChannel(value)
    local text = StripChatFormatting(value):lower()
    return text:find(CHANNEL_NAME:lower(), 1, true) ~= nil
end

local function IsFinderChannelEvent(message, channelString, channelNumber, channelName)
    if runtime.channelID > 0 and tonumber(channelNumber) == runtime.channelID then return true end
    if ContainsFinderChannel(channelString) or ContainsFinderChannel(channelName) then return true end
    local cleanMessage = StripChatFormatting(message)
    for bracket in cleanMessage:gmatch("%[([^%]]+)%]") do
        if ContainsFinderChannel(bracket) then return true end
    end
    return false
end

local function NormalizeExpiryMinutes(value)
    value = tonumber(value)
    for _, allowed in ipairs(EXPIRY_VALUES) do
        if value == allowed then return allowed end
    end
    return 15
end

local function NormalizeGameMode(value)
    value = tostring(value or "NORMAL"):upper():gsub("[%s%-_]", "")
    if value == "NORMAL" or value == "HC1" or value == "HC2" or value == "HC3" or value == "HC4" or value == "HC5" then
        return value
    end
    return "NORMAL"
end

local function GetGameModeName(value)
    local gameMode = gameModeByKey[NormalizeGameMode(value)]
    return gameMode and gameMode.name or "Normal"
end

local function GetEbonholdHardmodeService()
    if ProjectEbonhold and ProjectEbonhold.HardmodeService then
        return ProjectEbonhold.HardmodeService
    end
end

local function ReadEbonholdGameMode()
    local service = GetEbonholdHardmodeService()
    if not service then return nil end

    local tier
    if type(service.GetCurrentDifficulty) == "function" then
        local ok, value = pcall(service.GetCurrentDifficulty)
        if ok then tier = tonumber(value) end
    end
    if not tier and ProjectEbonhold then
        tier = tonumber(ProjectEbonhold.currentHardmodeTier)
    end
    if not tier or tier < 1 or tier > 6 then return nil end
    if tier == 1 then return "NORMAL" end
    return "HC" .. tostring(tier - 1)
end

local function RequestEbonholdGameMode()
    local service = GetEbonholdHardmodeService()
    if service and type(service.RequestHardmodeData) == "function" then
        pcall(service.RequestHardmodeData)
    end
end

local function ApplyDetectedGameMode(mode)
    mode = NormalizeGameMode(mode)
    if not gameModeByKey[mode] then return end
    local previous = runtime.currentGameMode
    runtime.currentGameMode = mode
    if createFrame and createFrame.modeButton then
        createFrame.modeButton.value = mode
        createFrame.modeButton.label:SetText(GetGameModeName(mode) .. " (Detected)")
        if createFrame.error and createFrame.error:GetText() == "Detecting your current game mode..." then
            createFrame.error:SetText("")
        end
    end
    if previous ~= mode and RavioliFamilyActivityFinderDB
        and RavioliFamilyActivityFinderDB.listings then
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
            if listing.status == "OPEN" or listing.status == "FULL" then
                listing.gameMode = mode
                if BroadcastListing then BroadcastListing(listing) end
            end
        end
        if mainFrame then UpdateListings() end
    end
end

local function DetectTaggedGameMode(message, protocolMarker)
    local prefix = tostring(message or "")
    if protocolMarker and protocolMarker > 1 then prefix = prefix:sub(1, protocolMarker - 1) end
    prefix = prefix:upper():gsub("%s+", "")
    local token = prefix:match("%[HC([IV%d]+)%]")
    local modes = {
        ["1"] = "HC1", I = "HC1",
        ["2"] = "HC2", II = "HC2",
        ["3"] = "HC3", III = "HC3",
        ["4"] = "HC4", IV = "HC4",
        ["5"] = "HC5", V = "HC5",
    }
    return modes[token] or "NORMAL"
end

local function GetDetectedGameMode()
    local serviceMode = ReadEbonholdGameMode()
    if serviceMode then ApplyDetectedGameMode(serviceMode) end
    return serviceMode or runtime.currentGameMode or "NORMAL"
end

local function ObserveTransportGameMode(message, marker, sender, transportSession)
    local mode = DetectTaggedGameMode(message, marker)
    local cleanSender = SanitizePlayerName(sender)
    if transportSession ~= "" and transportSession == GetSessionID() then
        mode = ReadEbonholdGameMode() or mode
        ApplyDetectedGameMode(mode)
    end
    runtime.peerGameModes[cleanSender:lower()] = mode
    return mode
end

local function HideOtherSecondaryWindows(keep)
    if createFrame and createFrame ~= keep then createFrame:Hide() end
    if settingsFrame and settingsFrame ~= keep then settingsFrame:Hide() end
    if applicantsFrame and applicantsFrame ~= keep then applicantsFrame:Hide() end
end

local function GetActivePeerCount()
    local count = 0
    local now = time()
    for name, lastSeen in pairs(runtime.peers) do
        if now - lastSeen <= PEER_TIMEOUT_SECONDS then
            count = count + 1
        else
            runtime.peers[name] = nil
        end
    end
    return count
end

local function GetManualRefreshRemaining()
    if runtime.lastManualRefreshAt <= 0 then return 0 end
    return math.max(0, MANUAL_REFRESH_COOLDOWN_SECONDS - (time() - runtime.lastManualRefreshAt))
end

local function UpdateRefreshButton()
    if not refreshButton then return end
    local remaining = GetManualRefreshRemaining()
    refreshButton.label:SetText(remaining > 0 and ("Refresh " .. remaining .. "s") or "Refresh")
    refreshButton:SetButtonEnabled(remaining <= 0)
end

local function UpdateConnectionStatus()
    local connected = runtime.channelID > 0
    local peerCount = GetActivePeerCount()
    if networkStatusText then
        if not connected then
            networkStatusText:SetText("OFFLINE")
            networkStatusText:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
        elseif peerCount == 0 then
            networkStatusText:SetText("NO RAVIOLI")
            networkStatusText:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        else
            networkStatusText:SetText(peerCount .. " RAVIOLI")
            networkStatusText:SetTextColor(COLORS.green[1], COLORS.green[2], COLORS.green[3])
        end
    end
    if settingsFrame and settingsFrame.connection then
        if connected then
            settingsFrame.connection:SetText("RavioliFinder channel " .. runtime.channelID .. " connected - "
                .. peerCount .. " Ravioli online")
        else
            settingsFrame.connection:SetText("Shared channel unavailable - refresh to retry")
        end
    end
end

local function SetColor(texture, color)
    texture:SetTexture(color[1], color[2], color[3], color[4] or 1)
end

local function AddBackground(frame, color, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    borderColor = borderColor or COLORS.border
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local function CreateText(parent, text, size, color, justify)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", size or 12)
    label:SetText(text or "")
    color = color or COLORS.text
    label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    label:SetJustifyH(justify or "LEFT")
    label:SetJustifyV("MIDDLE")
    return label
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    AddBackground(button, COLORS.panelLight, COLORS.border)

    button.label = CreateText(button, text, 12, COLORS.text, "CENTER")
    button.label:SetAllPoints()

    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() == 1 then
            self:SetBackdropColor(0.14, 0.16, 0.20, 1)
            self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.8)
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(COLORS.panelLight[1], COLORS.panelLight[2], COLORS.panelLight[3], COLORS.panelLight[4])
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], COLORS.border[4])
    end)
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() == 1 then
            self.label:ClearAllPoints()
            self.label:SetPoint("CENTER", 1, -1)
        end
    end)
    button:SetScript("OnMouseUp", function(self)
        self.label:ClearAllPoints()
        self.label:SetAllPoints()
    end)

    function button:SetButtonEnabled(enabled)
        if enabled then
            self:Enable()
            self.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
        else
            self:Disable()
            self.label:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        end
    end

    return button
end

local function CreateInput(parent, width, height, maxLetters)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(width)
    holder:SetHeight(height)
    AddBackground(holder, { 0.025, 0.030, 0.040, 1 }, COLORS.border)

    local input = CreateFrame("EditBox", nil, holder)
    input:SetPoint("TOPLEFT", 9, -2)
    input:SetPoint("BOTTOMRIGHT", -9, 2)
    input:SetFont("Fonts\\FRIZQT__.TTF", 12)
    input:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    input:SetAutoFocus(false)
    input:SetJustifyH("LEFT")
    input:SetMaxLetters(maxLetters or 80)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    holder.input = input
    return holder, input
end

local function GetCurrentGroupSize()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then return raidCount end
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    return partyCount > 0 and (partyCount + 1) or 1
end

local function IsPlayerInGroup(name)
    if not name or name == "" then return false end
    local lowered = name:lower()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            if (UnitName("raid" .. index) or ""):lower() == lowered then return true end
        end
    else
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, partyCount do
            if (UnitName("party" .. index) or ""):lower() == lowered then return true end
        end
    end
    return false
end

local function GetStatusLabel(status)
    if status == "FULL" then return "Full" end
    if status == "CLOSED" then return "Closed" end
    if status == "EXPIRED" then return "Expired" end
    return "Open"
end

local function GetListingKey(owner, id)
    return (owner or "Unknown"):lower() .. "#" .. tostring(id or "0")
end

local function Notify(message, sound)
    if not RavioliFamilyActivityFinderDB or not RavioliFamilyActivityFinderDB.settings.notifications then return end
    Print(message)
    if sound and RavioliFamilyActivityFinderDB.settings.sounds and PlaySound then PlaySound("TellMessage") end
end

local function GetListingsSource()
    if not RavioliFamilyActivityFinderDB then return {} end
    local result = {}
    for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
        table.insert(result, listing)
    end
    for _, listing in pairs(runtime.remoteListings) do
        if not IsLocalPlayerName(listing.owner)
            and (listing.status == "OPEN" or listing.status == "FULL") then
            table.insert(result, listing)
        end
    end
    return result
end

local function GetCategoryName(key)
    local category = categoryByKey[key]
    return category and category.name or "Custom"
end

local function GetCategoryShortName(key)
    local category = categoryByKey[key]
    return category and category.short or "Custom"
end

local function GetAgeText(listing)
    if listing.ageText then
        return listing.ageText
    end
    local elapsed = math.max(0, time() - (listing.createdAt or time()))
    if elapsed < 60 then
        return "just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. " min ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. " hr ago"
    end
    return math.floor(elapsed / 86400) .. " days ago"
end

local function MatchesSearch(listing, search)
    if search == "" then return true end
    local haystack = table.concat({
        listing.title or "",
        listing.activity or "",
        listing.owner or "",
        listing.notes or "",
        listing.startTime or "",
        GetGameModeName(listing.gameMode),
        GetCategoryName(listing.category),
    }, " "):lower()
    return haystack:find(search, 1, true) ~= nil
end

local function GetFilteredListings()
    local source = GetListingsSource()
    local filtered = {}
    local search = Trim(state.search):lower()
    for _, listing in ipairs(source) do
        if (state.category == "ALL" or listing.category == state.category) and MatchesSearch(listing, search) then
            table.insert(filtered, listing)
        end
    end
    table.sort(filtered, function(a, b)
        local aOpen = (a.status or "OPEN") == "OPEN" and 1 or 0
        local bOpen = (b.status or "OPEN") == "OPEN" and 1 or 0
        if aOpen ~= bOpen then return aOpen > bOpen end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return filtered
end

local function FindListingByID(id)
    if not id then return nil end
    local source = GetListingsSource()
    for _, listing in ipairs(source) do
        if listing.id == id then return listing end
    end
    return nil
end

local function FindOwnedListingByID(id)
    if not RavioliFamilyActivityFinderDB or not id then return nil end
    for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
        if tostring(listing.id) == tostring(id) then return listing end
    end
    return nil
end

local function IsOwnedListing(listing)
    if not listing then return false end
    if listing.isOwner == true then return true end
    local playerGUID = UnitGUID and UnitGUID("player")
    if playerGUID and listing.ownerGUID then return listing.ownerGUID == playerGUID end
    return IsLocalPlayerName(listing.owner)
end

local function FindActiveOwnedListing(exceptID)
    if not RavioliFamilyActivityFinderDB then return nil end
    for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings or {}) do
        if tostring(listing.id) ~= tostring(exceptID)
            and IsOwnedListing(listing)
            and (listing.status == "OPEN" or listing.status == "FULL") then
            return listing
        end
    end
    return nil
end

local function IsPlayerLeadingCurrentGroup()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        if IsRaidLeader then return IsRaidLeader() and true or false end
        if GetRaidRosterInfo then
            local playerName = (UnitName("player") or ""):lower()
            for index = 1, raidCount do
                local name, rank = GetRaidRosterInfo(index)
                if name and name:lower() == playerName then return rank == 2 end
            end
        end
        return false
    end

    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    if partyCount > 0 then
        if IsPartyLeader then return IsPartyLeader() and true or false end
        if UnitIsPartyLeader then return UnitIsPartyLeader("player") and true or false end
        if GetPartyLeaderIndex then return GetPartyLeaderIndex() == 0 end
        return false
    end
    return true
end

local function IsOwnListedGroup(listing)
    if IsPlayerLeadingCurrentGroup() then return true end
    local reservations = runtime.inviteReservations[tostring(listing.id)] or {}
    for name in pairs(reservations) do
        if IsPlayerInGroup(name) then return true end
    end
    return false
end

local function GetApplicationCooldownRemaining(listingID)
    local requestedAt = runtime.requested[listingID]
    if not requestedAt then return 0 end
    return math.max(0, APPLICATION_COOLDOWN_SECONDS - (time() - requestedAt))
end

local function GetApplicantKey(name)
    return SanitizePlayerName(name):lower()
end

local function RemoveApplicantFromListing(listing, applicant)
    if not listing or not applicant then return end
    local applicants = runtime.applicants[tostring(listing.id)] or {}
    local targetKey = GetApplicantKey(applicant.name)
    for index = #applicants, 1, -1 do
        if applicants[index] == applicant or GetApplicantKey(applicants[index].name) == targetKey then
            table.remove(applicants, index)
            return
        end
    end
end

local function SetDeclineLockout(listing, name)
    if not listing then return end
    local listKey = tostring(listing.id)
    runtime.declineLockouts[listKey] = runtime.declineLockouts[listKey] or {}
    runtime.declineLockouts[listKey][GetApplicantKey(name)] = time()
end

local function HasDeclineLockout(listing, name)
    if not listing then return false end
    local listLockouts = runtime.declineLockouts[tostring(listing.id)]
    if not listLockouts then return false end
    local applicantKey = GetApplicantKey(name)
    local declinedAt = listLockouts[applicantKey]
    if not declinedAt then return false end
    if time() - declinedAt < APPLICATION_COOLDOWN_SECONDS then return true end
    listLockouts[applicantKey] = nil
    return false
end

local function SavePosition()
    if not mainFrame or not RavioliFamilyActivityFinderDB then return end
    local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
    RavioliFamilyActivityFinderDB.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function UpdateCategoryButtons()
    for key, button in pairs(categoryButtons) do
        if key == state.category then
            button.active:Show()
            button.accent:Show()
            button.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        else
            button.active:Hide()
            button.accent:Hide()
            button.label:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        end
    end
end

local function UpdateDetails(listing)
    if not listing then
        details.content:Hide()
        details.empty:Show()
        return
    end

    details.empty:Hide()
    details.content:Show()
    details.category:SetText(GetCategoryName(listing.category):upper() .. "  |  " .. GetGameModeName(listing.gameMode):upper())
    details.title:SetText(listing.title or "Untitled activity")
    details.activity:SetText(listing.activity ~= "" and listing.activity or GetCategoryName(listing.category))
    if listing.questLink and listing.questLink ~= "" then details.quest:Show() else details.quest:Hide() end
    details.owner:SetText(listing.owner or "Unknown")
    details.groupSize:SetText(tostring(listing.currentSize or 1) .. " / " .. tostring(listing.groupSize or 5))
    details.status:SetText(GetStatusLabel(listing.status))
    if (listing.status or "OPEN") == "OPEN" then
        details.status:SetTextColor(COLORS.green[1], COLORS.green[2], COLORS.green[3])
    else
        details.status:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    end
    details.startTime:SetText((listing.startTime and listing.startTime ~= "") and listing.startTime or "Now")
    details.notes:SetText((listing.notes and listing.notes ~= "") and listing.notes or "No additional details provided.")

    if IsOwnedListing(listing) then
        details.edit:Show()
        details.statusButton:Show()
        details.statusButton.label:SetText((listing.status == "CLOSED" or listing.status == "EXPIRED") and "Reopen Listing" or "Close Listing")
        details.applicants:Show()
        local applicantList = runtime.applicants[tostring(listing.id)] or {}
        details.applicants.label:SetText("Applicants (" .. #applicantList .. ")")
        details.remove:Show()
        details.request:Hide()
        details.whisper:Hide()
        details.ownerNotice:Hide()
    else
        details.edit:Hide()
        details.statusButton:Hide()
        details.applicants:Hide()
        details.remove:Hide()
        details.request:Show()
        local requestedBefore = runtime.requested[listing.id] ~= nil
        local cooldown = GetApplicationCooldownRemaining(listing.id)
        if cooldown > 0 then
            details.request.label:SetText("Re-apply in " .. cooldown .. "s")
        else
            details.request.label:SetText(requestedBefore and "Re-apply" or "Request Invite")
        end
        details.request:SetButtonEnabled(cooldown <= 0
            and (listing.status or "OPEN") == "OPEN"
            and (listing.currentSize or 1) < (listing.groupSize or 5))
        details.whisper:Show()
        details.ownerNotice:Hide()
    end
end

UpdateListings = function()
    if not mainFrame then return end

    local filtered = GetFilteredListings()
    local totalPages = math.max(1, math.ceil(#filtered / state.pageSize))
    state.page = math.max(1, math.min(state.page, totalPages))
    local startIndex = ((state.page - 1) * state.pageSize) + 1

    listSummary:SetText(#filtered .. (#filtered == 1 and " listing" or " listings"))
    if #filtered == 0 then emptyState:Show() else emptyState:Hide() end

    for rowIndex, row in ipairs(listingRows) do
        local listing = filtered[startIndex + rowIndex - 1]
        if listing then
            row.listingID = listing.id
            row.title:SetText(listing.title or "Untitled activity")
            row.meta:SetText(GetCategoryShortName(listing.category) .. "  |  " .. GetGameModeName(listing.gameMode) .. "  |  " .. (listing.owner or "Unknown"))
            row.age:SetText(GetAgeText(listing))
            row.count:SetText(tostring(listing.currentSize or 1) .. "/" .. tostring(listing.groupSize or 5))
            row.status:SetText(GetStatusLabel(listing.status))
            if (listing.status or "OPEN") == "OPEN" then
                row.status:SetTextColor(COLORS.green[1], COLORS.green[2], COLORS.green[3])
            else
                row.status:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
            end
            if listing.id == state.selectedID then
                row.selected:Show()
                row:SetBackdropColor(0.105, 0.115, 0.14, 1)
            else
                row.selected:Hide()
                row:SetBackdropColor(COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], COLORS.panel[4])
            end
            row:Show()
        else
            row.listingID = nil
            row:Hide()
        end
    end

    local selectedInFilter = false
    for _, listing in ipairs(filtered) do
        if listing.id == state.selectedID then selectedInFilter = true break end
    end
    if not selectedInFilter then
        state.selectedID = filtered[1] and filtered[1].id or nil
        if state.selectedID then
            return UpdateListings()
        end
    end

    previousButton:SetButtonEnabled(state.page > 1)
    nextButton:SetButtonEnabled(state.page < totalPages)
    pageText:SetText("Page " .. state.page .. " / " .. totalPages)
    UpdateDetails(FindListingByID(state.selectedID))
    UpdateCategoryButtons()
end

local function SelectCategory(key)
    state.category = key
    state.page = 1
    state.selectedID = nil
    UpdateListings()
end

local function RemoveSelectedListing()
    if not RavioliFamilyActivityFinderDB or not state.selectedID then return end
    for index, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
        if tostring(listing.id) == tostring(state.selectedID) then
            if not IsOwnedListing(listing) then return end
            local removedID = listing.id
            table.remove(RavioliFamilyActivityFinderDB.listings, index)
            runtime.applicants[tostring(removedID)] = nil
            runtime.declineLockouts[tostring(removedID)] = nil
            runtime.inviteReservations[tostring(removedID)] = nil
            state.selectedID = nil
            state.page = 1
            UpdateListings()
            if BroadcastRemoval then BroadcastRemoval(removedID) end
            Print("Listing removed.")
            return
        end
    end
end

local function BuildCategoryNavigation(parent)
    local heading = CreateText(parent, "BROWSE", 10, COLORS.muted)
    heading:SetPoint("TOPLEFT", 16, -18)

    for index, category in ipairs(categories) do
        local button = CreateFrame("Button", nil, parent)
        button:SetPoint("TOPLEFT", 8, -38 - ((index - 1) * 40))
        button:SetWidth(136)
        button:SetHeight(34)

        button.active = button:CreateTexture(nil, "BACKGROUND")
        button.active:SetPoint("TOPLEFT", 0, 0)
        button.active:SetPoint("BOTTOMRIGHT", 0, 0)
        SetColor(button.active, { 0.12, 0.115, 0.09, 1 })

        button.accent = button:CreateTexture(nil, "ARTWORK")
        button.accent:SetPoint("TOPLEFT", 0, 0)
        button.accent:SetPoint("BOTTOMLEFT", 0, 0)
        button.accent:SetWidth(3)
        SetColor(button.accent, COLORS.gold)
        button.accent:Hide()

        button.label = CreateText(button, category.name, 12, COLORS.muted)
        button.label:SetPoint("LEFT", 12, 0)

        button:SetScript("OnClick", function() SelectCategory(category.key) end)
        button:SetScript("OnEnter", function(self)
            if category.key ~= state.category then
                self.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
            end
        end)
        button:SetScript("OnLeave", function(self)
            if category.key ~= state.category then
                self.label:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
            end
        end)
        categoryButtons[category.key] = button
    end
end

local function BuildListingRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(375)
    row:SetHeight(58)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 64))
    AddBackground(row, COLORS.panel, { 0.15, 0.17, 0.20, 1 })

    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:SetPoint("TOPLEFT", 0, 0)
    row.selected:SetPoint("BOTTOMLEFT", 0, 0)
    row.selected:SetWidth(3)
    SetColor(row.selected, COLORS.gold)

    row.title = CreateText(row, "", 13, COLORS.text)
    row.title:SetPoint("TOPLEFT", 12, -8)
    row.title:SetPoint("TOPRIGHT", -105, -8)
    row.title:SetHeight(16)
    row.title:SetJustifyH("LEFT")

    row.meta = CreateText(row, "", 10, COLORS.muted)
    row.meta:SetPoint("BOTTOMLEFT", 12, 8)
    row.meta:SetWidth(260)
    row.meta:SetHeight(14)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWordWrap(false)

    row.age = CreateText(row, "", 9, COLORS.muted, "RIGHT")
    row.age:SetPoint("BOTTOMRIGHT", -10, 7)

    row.status = CreateText(row, "", 9, COLORS.green, "RIGHT")
    row.status:SetPoint("TOPRIGHT", -10, -8)

    row.count = CreateText(row, "", 11, COLORS.text, "RIGHT")
    row.count:SetPoint("RIGHT", -10, -1)

    row:SetScript("OnClick", function(self)
        state.selectedID = self.listingID
        UpdateListings()
    end)
    row:SetScript("OnEnter", function(self)
        if self.listingID ~= state.selectedID then
            self:SetBackdropColor(0.085, 0.095, 0.12, 1)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.listingID ~= state.selectedID then
            self:SetBackdropColor(COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], COLORS.panel[4])
        end
    end)
    return row
end

local function BuildDetailsPanel(parent)
    local heading = CreateText(parent, "DETAILS", 10, COLORS.muted)
    heading:SetPoint("TOPLEFT", 16, -18)

    details.empty = CreateText(parent, "Select a listing to see its details.", 12, COLORS.muted, "CENTER")
    details.empty:SetPoint("CENTER", 0, 20)
    details.empty:SetWidth(220)
    details.empty:SetHeight(50)

    details.content = CreateFrame("Frame", nil, parent)
    details.content:SetPoint("TOPLEFT", 16, -42)
    details.content:SetPoint("BOTTOMRIGHT", -16, 16)

    details.category = CreateText(details.content, "", 10, COLORS.gold)
    details.category:SetPoint("TOPLEFT", 0, 0)

    details.title = CreateText(details.content, "", 17, COLORS.text)
    details.title:SetPoint("TOPLEFT", 0, -22)
    details.title:SetWidth(232)
    details.title:SetHeight(42)
    details.title:SetJustifyV("TOP")
    details.title:SetWordWrap(true)

    local activityLabel = CreateText(details.content, "ACTIVITY", 9, COLORS.muted)
    activityLabel:SetPoint("TOPLEFT", 0, -76)
    details.activity = CreateText(details.content, "", 12, COLORS.text)
    details.activity:SetPoint("TOPLEFT", 0, -91)

    details.quest = CreateButton(details.content, "Quest", 54, 22)
    details.quest:SetPoint("TOPRIGHT", 0, -83)
    details.quest:SetScript("OnEnter", function(self)
        local listing = FindListingByID(state.selectedID)
        if listing and listing.questLink and listing.questLink ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(listing.questLink)
            GameTooltip:Show()
        end
    end)
    details.quest:SetScript("OnLeave", function() GameTooltip:Hide() end)
    details.quest:SetScript("OnClick", function()
        local listing = FindListingByID(state.selectedID)
        if not listing or not listing.questLink or not SetItemRef then return end
        local linkType = listing.questLink:match("|H(.-)|h")
        if linkType then SetItemRef(linkType, listing.questLink, "LeftButton") end
    end)

    local ownerLabel = CreateText(details.content, "ORGANIZER", 9, COLORS.muted)
    ownerLabel:SetPoint("TOPLEFT", 0, -124)
    details.owner = CreateText(details.content, "", 12, COLORS.text)
    details.owner:SetPoint("TOPLEFT", 0, -139)

    local sizeLabel = CreateText(details.content, "GROUP", 9, COLORS.muted)
    sizeLabel:SetPoint("TOPLEFT", 130, -124)
    details.groupSize = CreateText(details.content, "", 12, COLORS.text)
    details.groupSize:SetPoint("TOPLEFT", 130, -139)

    local statusLabel = CreateText(details.content, "STATUS", 9, COLORS.muted)
    statusLabel:SetPoint("TOPLEFT", 0, -170)
    details.status = CreateText(details.content, "", 11, COLORS.green)
    details.status:SetPoint("TOPLEFT", 0, -185)

    local startLabel = CreateText(details.content, "START", 9, COLORS.muted)
    startLabel:SetPoint("TOPLEFT", 130, -170)
    details.startTime = CreateText(details.content, "", 11, COLORS.text)
    details.startTime:SetPoint("TOPLEFT", 130, -185)

    local notesLabel = CreateText(details.content, "NOTES", 9, COLORS.muted)
    notesLabel:SetPoint("TOPLEFT", 0, -214)
    details.notes = CreateText(details.content, "", 11, { 0.76, 0.78, 0.82, 1 })
    details.notes:SetPoint("TOPLEFT", 0, -230)
    details.notes:SetWidth(232)
    details.notes:SetHeight(106)
    details.notes:SetJustifyV("TOP")
    details.notes:SetWordWrap(true)

    details.ownerNotice = CreateText(details.content, "Only the organizer can edit this listing.", 9, COLORS.muted, "CENTER")
    details.ownerNotice:SetPoint("BOTTOM", 0, 14)
    details.ownerNotice:SetWidth(230)

    details.edit = CreateButton(details.content, "Edit", 112, 28)
    details.edit:SetPoint("BOTTOMLEFT", 0, 31)
    details.edit:SetFrameLevel(details.content:GetFrameLevel() + 3)
    details.edit.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    details.edit:SetScript("OnClick", function()
        local listing = FindOwnedListingByID(state.selectedID)
        if not IsOwnedListing(listing) then return end
        createFrame.editingID = listing.id
        createFrame:Show()
    end)

    details.statusButton = CreateButton(details.content, "Close Listing", 112, 28)
    details.statusButton:SetPoint("BOTTOMRIGHT", 0, 31)
    details.statusButton:SetFrameLevel(details.content:GetFrameLevel() + 3)
    details.statusButton:SetScript("OnClick", function()
        local listing = FindOwnedListingByID(state.selectedID)
        if not IsOwnedListing(listing) then return end
        if listing.status == "CLOSED" or listing.status == "EXPIRED" then
            local activeListing = FindActiveOwnedListing(listing.id)
            if activeListing then
                Print("You already have an active listing. Close or remove it before reopening another.")
                return
            end
            if GetCurrentGroupSize() > 1 and not IsPlayerLeadingCurrentGroup() then
                Print("You cannot reopen a listing while grouped under another leader.")
                return
            end
            listing.status = "OPEN"
            listing.closedAt = nil
            listing.createdAt = time()
            listing.updatedAt = time()
            listing.expiresAt = time() + (NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes) * 60)
        else
            listing.status = "CLOSED"
            listing.closedAt = time()
        end
        UpdateListings()
        if BroadcastListing then BroadcastListing(listing) end
        Print(listing.status == "OPEN" and "Listing reopened." or "Listing closed.")
    end)

    details.applicants = CreateButton(details.content, "Applicants (0)", 112, 28)
    details.applicants:SetPoint("BOTTOMLEFT", 0, 0)
    details.applicants:SetFrameLevel(details.content:GetFrameLevel() + 3)
    details.applicants:SetScript("OnClick", function()
        local listing = FindOwnedListingByID(state.selectedID)
        if IsOwnedListing(listing) and OpenApplicantsFrame then OpenApplicantsFrame(listing) end
    end)

    details.remove = CreateButton(details.content, "Remove", 112, 28)
    details.remove:SetPoint("BOTTOMRIGHT", 0, 0)
    details.remove:SetFrameLevel(details.content:GetFrameLevel() + 3)
    details.remove.label:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    details.remove:SetScript("OnClick", RemoveSelectedListing)

    details.request = CreateButton(details.content, "Request Invite", 232, 30)
    details.request:SetPoint("BOTTOM", 0, 31)
    details.request.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    details.request:SetScript("OnClick", function()
        local listing = FindListingByID(state.selectedID)
        if listing and not IsOwnedListing(listing) and SendJoinRequest then SendJoinRequest(listing) end
    end)

    details.whisper = CreateButton(details.content, "Whisper", 232, 26)
    details.whisper:SetPoint("BOTTOM", 0, 0)
    details.whisper:SetScript("OnClick", function()
        local listing = FindListingByID(state.selectedID)
        if listing and ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. (listing.owner or "") .. " ") end
    end)

end

local function CreateCategoryDropdown(parent)
    local values = { "RAID", "QUEST", "WORLD", "CUSTOM" }
    local dropdown = CreateButton(parent, "Raids", 184, 30)
    dropdown.value = "RAID"

    dropdown.arrow = CreateText(dropdown, "v", 11, COLORS.gold, "CENTER")
    dropdown.arrow:SetPoint("RIGHT", -10, 0)
    dropdown.arrow:SetWidth(14)

    dropdown.menu = CreateFrame("Frame", nil, parent)
    dropdown.menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    dropdown.menu:SetWidth(184)
    dropdown.menu:SetHeight((#values * 28) + 4)
    dropdown.menu:SetFrameLevel(parent:GetFrameLevel() + 20)
    AddBackground(dropdown.menu, COLORS.panel, COLORS.gold)
    dropdown.menu:Hide()

    for index, key in ipairs(values) do
        local option = CreateFrame("Button", nil, dropdown.menu)
        option:SetPoint("TOPLEFT", 2, -2 - ((index - 1) * 28))
        option:SetWidth(180)
        option:SetHeight(28)
        option.value = key

        option.highlight = option:CreateTexture(nil, "BACKGROUND")
        option.highlight:SetAllPoints()
        SetColor(option.highlight, { 0.14, 0.16, 0.20, 1 })
        option.highlight:Hide()

        option.label = CreateText(option, GetCategoryName(key), 11, COLORS.text)
        option.label:SetPoint("LEFT", 10, 0)

        option:SetScript("OnEnter", function(self) self.highlight:Show() end)
        option:SetScript("OnLeave", function(self) self.highlight:Hide() end)
        option:SetScript("OnClick", function(self)
            dropdown.value = self.value
            dropdown.label:SetText(GetCategoryName(self.value))
            dropdown.menu:Hide()
        end)
    end

    dropdown:SetScript("OnClick", function(self)
        if createFrame and createFrame.modeButton then createFrame.modeButton.menu:Hide() end
        if self.menu:IsShown() then self.menu:Hide() else self.menu:Show() end
    end)
    return dropdown
end

local function CreateGameModeDropdown(parent)
    local dropdown = CreateButton(parent, "Detecting...", 184, 30)
    dropdown.value = GetDetectedGameMode()
    dropdown.menu = CreateFrame("Frame", nil, parent)
    dropdown.menu:Hide()
    dropdown:SetButtonEnabled(false)
    dropdown.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    return dropdown
end

local function EnableQuestLogClickCapture()
    if questLogHooked or type(QuestLogTitleButton_OnClick) ~= "function" then return end

    local originalQuestLogTitleButton_OnClick = QuestLogTitleButton_OnClick
    QuestLogTitleButton_OnClick = function(self, button)
        if createFrame and createFrame:IsShown()
            and IsShiftKeyDown()
            and self
            and not self.isHeader
            and (button == "LeftButton" or button == nil) then
            local questIndex = self:GetID()
            local questTitle = GetQuestLogTitle(questIndex)
            if questTitle and questTitle ~= "" then
                createFrame.titleInput:SetText(Trim(questTitle))
                createFrame.titleInput:HighlightText()
                createFrame.questLink = GetQuestLink and GetQuestLink(questIndex) or nil
                createFrame.error:SetText("")
                if QuestLog_SetSelection then QuestLog_SetSelection(questIndex) end
                return
            end
        end
        return originalQuestLogTitleButton_OnClick(self, button)
    end
    questLogHooked = true
end

local function EnableQuestLogVisibilityLink()
    if questLogVisibilityHooked or not QuestLogFrame or not QuestLogFrame.HookScript then return end
    QuestLogFrame:HookScript("OnShow", function()
        if RavioliFamilyActivityFinderDB
            and RavioliFamilyActivityFinderDB.settings.linkQuestLog
            and mainFrame
            and not mainFrame:IsShown()
            and (not createFrame or not createFrame:IsShown())
            and ShowMainFrame then
            ShowMainFrame(false)
        end
    end)
    QuestLogFrame:HookScript("OnHide", function()
        if RavioliFamilyActivityFinderDB
            and RavioliFamilyActivityFinderDB.settings.linkQuestLog
            and mainFrame
            and mainFrame:IsShown() then
            mainFrame:Hide()
        end
    end)
    questLogVisibilityHooked = true
end

local function ShowLinkedQuestLog()
    EnableQuestLogVisibilityLink()
    if QuestLogFrame and not QuestLogFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(QuestLogFrame) else QuestLogFrame:Show() end
    elseif not QuestLogFrame and ToggleQuestLog then
        ToggleQuestLog()
        EnableQuestLogVisibilityLink()
    end
end

local function HideLinkedQuestLog()
    if QuestLogFrame and QuestLogFrame:IsShown() then
        if HideUIPanel then HideUIPanel(QuestLogFrame) else QuestLogFrame:Hide() end
    end
end

local function BuildCreateFrame()
    createFrame = CreateFrame("Frame", "RavioliFamilyActivityFinderCreateFrame", UIParent)
    createFrame:SetWidth(430)
    createFrame:SetHeight(490)
    createFrame:SetPoint("CENTER")
    createFrame:SetFrameStrata("DIALOG")
    createFrame:EnableMouse(true)
    AddBackground(createFrame, COLORS.background, COLORS.gold)
    createFrame:Hide()
    table.insert(UISpecialFrames, "RavioliFamilyActivityFinderCreateFrame")

    createFrame.heading = CreateText(createFrame, "Create a Listing", 18, COLORS.text)
    createFrame.heading:SetPoint("TOPLEFT", 20, -18)
    createFrame.subtitle = CreateText(createFrame, "Type a title, or shift-click a quest in your quest log.", 10, COLORS.muted)
    createFrame.subtitle:SetPoint("TOPLEFT", 20, -43)

    local close = CreateButton(createFrame, "X", 28, 28)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() createFrame:Hide() end)

    local categoryLabel = CreateText(createFrame, "CATEGORY", 9, COLORS.muted)
    categoryLabel:SetPoint("TOPLEFT", 20, -79)

    local categoryButton = CreateCategoryDropdown(createFrame)
    categoryButton:SetPoint("TOPLEFT", 20, -94)
    createFrame.categoryButton = categoryButton

    local sizeLabel = CreateText(createFrame, "TARGET GROUP SIZE", 9, COLORS.muted)
    sizeLabel:SetPoint("TOPLEFT", 226, -79)
    local sizeHolder, sizeInput = CreateInput(createFrame, 184, 30, 2)
    sizeHolder:SetPoint("TOPLEFT", 226, -94)
    sizeInput:SetNumeric(true)
    sizeInput:SetText("10")
    createFrame.sizeInput = sizeInput

    local titleLabel = CreateText(createFrame, "LISTING TITLE", 9, COLORS.muted)
    titleLabel:SetPoint("TOPLEFT", 20, -139)
    local titleHolder, titleInput = CreateInput(createFrame, 390, 30, 60)
    titleHolder:SetPoint("TOPLEFT", 20, -154)
    createFrame.titleInput = titleInput

    local activityLabel = CreateText(createFrame, "ACTIVITY OR LOCATION", 9, COLORS.muted)
    activityLabel:SetPoint("TOPLEFT", 20, -199)
    local activityHolder, activityInput = CreateInput(createFrame, 390, 30, 60)
    activityHolder:SetPoint("TOPLEFT", 20, -214)
    createFrame.activityInput = activityInput

    local startLabel = CreateText(createFrame, "START TIME", 9, COLORS.muted)
    startLabel:SetPoint("TOPLEFT", 20, -259)
    local startHolder, startInput = CreateInput(createFrame, 184, 30, 30)
    startHolder:SetPoint("TOPLEFT", 20, -274)
    createFrame.startInput = startInput

    local modeLabel = CreateText(createFrame, "GAME MODE", 9, COLORS.muted)
    modeLabel:SetPoint("TOPLEFT", 226, -259)
    local modeButton = CreateGameModeDropdown(createFrame)
    modeButton:SetPoint("TOPLEFT", 226, -274)
    createFrame.modeButton = modeButton

    local notesLabel = CreateText(createFrame, "NOTES", 9, COLORS.muted)
    notesLabel:SetPoint("TOPLEFT", 20, -319)
    local notesHolder, notesInput = CreateInput(createFrame, 390, 80, 180)
    notesHolder:SetPoint("TOPLEFT", 20, -334)
    notesInput:SetMultiLine(true)
    notesInput:SetJustifyV("TOP")
    createFrame.notesInput = notesInput

    createFrame.error = CreateText(createFrame, "", 10, COLORS.red)
    createFrame.error:SetPoint("BOTTOMLEFT", 20, 57)
    createFrame.error:SetWidth(250)

    local cancel = CreateButton(createFrame, "Cancel", 90, 30)
    cancel:SetPoint("BOTTOMRIGHT", -142, 18)
    cancel:SetScript("OnClick", function() createFrame:Hide() end)

    createFrame.submitButton = CreateButton(createFrame, "Create Listing", 122, 30)
    createFrame.submitButton:SetPoint("BOTTOMRIGHT", -20, 18)
    createFrame.submitButton.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    createFrame.submitButton:SetScript("OnClick", function()
        local listingTitle = Trim(createFrame.titleInput:GetText())
        local activity = Trim(createFrame.activityInput:GetText())
        local groupSize = tonumber(createFrame.sizeInput:GetText()) or 0
        if listingTitle == "" then
            createFrame.error:SetText("Enter a title for your listing.")
            return
        elseif groupSize < 2 or groupSize > 40 then
            createFrame.error:SetText("Group size must be between 2 and 40.")
            return
        elseif not runtime.currentGameMode then
            createFrame.error:SetText("Detecting your current game mode...")
            QueueDirectAction(PRESENCE_WIRE_PREFIX)
            return
        end

        local listing = FindListingByID(createFrame.editingID)
        local wasEditing = listing ~= nil
        if listing and not IsOwnedListing(listing) then return end
        if not listing and FindActiveOwnedListing(nil) then
            createFrame.error:SetText("You already have an active listing. Close or remove it first.")
            return
        elseif GetCurrentGroupSize() > 1 and not IsPlayerLeadingCurrentGroup() then
            createFrame.error:SetText("You cannot advertise while grouped under another leader.")
            return
        end

        if listing then
            listing.category = createFrame.categoryButton.value
            listing.title = listingTitle
            listing.activity = activity
            listing.groupSize = groupSize
            listing.gameMode = GetDetectedGameMode()
            listing.startTime = Trim(createFrame.startInput:GetText())
            listing.notes = Trim(createFrame.notesInput:GetText())
            listing.questLink = createFrame.questLink or listing.questLink
            listing.expiresAt = time() + (NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes) * 60)
            listing.updatedAt = time()
        else
            local id = RavioliFamilyActivityFinderDB.nextID
            RavioliFamilyActivityFinderDB.nextID = id + 1
            listing = {
                id = id,
                category = createFrame.categoryButton.value,
                title = listingTitle,
                activity = activity,
                owner = UnitName("player") or "You",
                ownerGUID = UnitGUID and UnitGUID("player"),
                isOwner = true,
                groupSize = groupSize,
                currentSize = GetCurrentGroupSize(),
                gameMode = GetDetectedGameMode(),
                startTime = Trim(createFrame.startInput:GetText()),
                notes = Trim(createFrame.notesInput:GetText()),
                questLink = createFrame.questLink,
                status = "OPEN",
                autoClose = RavioliFamilyActivityFinderDB.settings.autoClose,
                autoInvite = RavioliFamilyActivityFinderDB.settings.autoInvite,
                expiresAt = time() + (NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes) * 60),
                createdAt = time(),
            }
            table.insert(RavioliFamilyActivityFinderDB.listings, 1, listing)
        end

        state.category = "ALL"
        state.search = ""
        state.page = 1
        searchBox:SetText("")
        state.selectedID = listing.id
        createFrame:Hide()
        Print((wasEditing and "Updated listing: " or "Created listing: ") .. listingTitle)
        if BroadcastListing then BroadcastListing(listing) end
        UpdateListings()
    end)

    createFrame:SetScript("OnShow", function(self)
        if mainFrame and not mainFrame:IsShown() and ShowMainFrame then ShowMainFrame(true) end
        HideOtherSecondaryWindows(self)
        EnableQuestLogClickCapture()
        self.categoryButton.menu:Hide()
        self.modeButton.menu:Hide()
        local listing = FindListingByID(self.editingID)
        if listing and IsOwnedListing(listing) then
            self.heading:SetText("Edit Listing")
            self.subtitle:SetText("Update your listing, or shift-click a quest to replace its title.")
            self.submitButton.label:SetText("Save Changes")
            self.categoryButton.value = listing.category or "CUSTOM"
            self.categoryButton.label:SetText(GetCategoryName(self.categoryButton.value))
            self.sizeInput:SetText(tostring(listing.groupSize or 5))
            self.modeButton.value = GetDetectedGameMode()
            self.modeButton.label:SetText(runtime.currentGameMode
                and (GetGameModeName(self.modeButton.value) .. " (Detected)") or "Detecting...")
            self.titleInput:SetText(listing.title or "")
            self.activityInput:SetText(listing.activity or "")
            self.startInput:SetText(listing.startTime or "Now")
            self.notesInput:SetText(listing.notes or "")
            self.questLink = listing.questLink
        else
            self.editingID = nil
            self.heading:SetText("Create a Listing")
            self.subtitle:SetText("Type a title, or shift-click a quest in your quest log.")
            self.submitButton.label:SetText("Create Listing")
            self.categoryButton.value = "RAID"
            self.categoryButton.label:SetText("Raids")
            self.sizeInput:SetText("10")
            self.modeButton.value = GetDetectedGameMode()
            self.modeButton.label:SetText(runtime.currentGameMode
                and (GetGameModeName(self.modeButton.value) .. " (Detected)") or "Detecting...")
            self.titleInput:SetText("")
            self.activityInput:SetText("")
            self.startInput:SetText("Now")
            self.notesInput:SetText("")
            self.questLink = nil
        end
        self.error:SetText("")
        if not runtime.currentGameMode then QueueDirectAction(PRESENCE_WIRE_PREFIX) end
        self.titleInput:SetFocus()
        self.titleInput:HighlightText()
    end)
    createFrame:SetScript("OnHide", function(self)
        self.categoryButton.menu:Hide()
        self.modeButton.menu:Hide()
        self.editingID = nil
    end)
end

local function BuildMainFrame()
    mainFrame = CreateFrame("Frame", "RavioliFamilyActivityFinderFrame", UIParent)
    mainFrame:SetWidth(860)
    mainFrame:SetHeight(540)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    AddBackground(mainFrame, COLORS.background, COLORS.border)
    mainFrame:Hide()
    table.insert(UISpecialFrames, "RavioliFamilyActivityFinderFrame")
    mainFrame:SetScript("OnHide", function()
        HideOtherSecondaryWindows(nil)
        if RavioliFamilyActivityFinderDB
            and RavioliFamilyActivityFinderDB.settings.linkQuestLog then
            HideLinkedQuestLog()
        end
    end)

    local header = CreateFrame("Frame", nil, mainFrame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(60)
    local headerTexture = header:CreateTexture(nil, "BACKGROUND")
    headerTexture:SetAllPoints()
    SetColor(headerTexture, { 0.055, 0.062, 0.078, 1 })

    local title = CreateText(header, "Ravioli Family Activity Finder", 19, COLORS.text)
    title:SetPoint("TOPLEFT", 18, -13)
    local subtitle = CreateText(header, "Community group listings", 10, COLORS.muted)
    subtitle:SetPoint("TOPLEFT", 18, -38)

    local localBadge = CreateFrame("Frame", nil, header)
    localBadge:SetWidth(100)
    localBadge:SetHeight(20)
    localBadge:SetPoint("LEFT", title, "RIGHT", 12, 0)
    AddBackground(localBadge, { 0.11, 0.10, 0.065, 1 }, { 0.35, 0.29, 0.15, 1 })
    networkStatusText = CreateText(localBadge, "CONNECTING", 8, COLORS.gold, "CENTER")
    networkStatusText:SetAllPoints()

    refreshButton = CreateButton(header, "Refresh", 84, 28)
    refreshButton:SetPoint("TOPRIGHT", -132, -12)
    refreshButton:SetScript("OnClick", function()
        if RefreshSharedListings then RefreshSharedListings(true) end
    end)

    local settings = CreateButton(header, "Settings", 76, 28)
    settings:SetPoint("TOPRIGHT", -48, -12)
    settings:SetScript("OnClick", function() if OpenSettingsFrame then OpenSettingsFrame() end end)

    local close = CreateButton(header, "X", 28, 28)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() mainFrame:Hide() end)

    local nav = CreateFrame("Frame", nil, mainFrame)
    nav:SetPoint("TOPLEFT", 1, -61)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(152)
    AddBackground(nav, { 0.045, 0.052, 0.066, 1 }, { 0.10, 0.11, 0.14, 1 })
    BuildCategoryNavigation(nav)

    local createButton = CreateButton(nav, "+  Create Listing", 124, 32)
    createButton:SetPoint("BOTTOM", 0, 18)
    createButton.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    createButton:SetScript("OnClick", function()
        local activeListing = FindActiveOwnedListing(nil)
        if activeListing then
            state.category = "ALL"
            state.search = ""
            state.selectedID = activeListing.id
            state.page = 1
            searchBox:SetText("")
            UpdateListings()
            Print("You already have an active listing. Edit, close, or remove it before creating another.")
            return
        end
        createFrame.editingID = nil
        createFrame:Show()
    end)

    local listPanel = CreateFrame("Frame", nil, mainFrame)
    listPanel:SetPoint("TOPLEFT", 153, -61)
    listPanel:SetPoint("BOTTOMLEFT", 153, 1)
    listPanel:SetWidth(426)

    local searchLabel = CreateText(listPanel, "SEARCH", 9, COLORS.muted)
    searchLabel:SetPoint("TOPLEFT", 18, -15)
    local searchHolder
    searchHolder, searchBox = CreateInput(listPanel, 375, 30, 80)
    searchHolder:SetPoint("TOPLEFT", 18, -30)
    searchBox:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        state.page = 1
        state.selectedID = nil
        UpdateListings()
    end)

    listSummary = CreateText(listPanel, "0 listings", 10, COLORS.muted)
    listSummary:SetPoint("TOPLEFT", 18, -72)

    local rowsParent = CreateFrame("Frame", nil, listPanel)
    rowsParent:SetPoint("TOPLEFT", 18, -90)
    rowsParent:SetWidth(375)
    rowsParent:SetHeight(378)
    for index = 1, state.pageSize do
        listingRows[index] = BuildListingRow(rowsParent, index)
    end

    emptyState = CreateText(rowsParent, "No listings found.\n\nCreate one to get a group started.", 12, COLORS.muted, "CENTER")
    emptyState:SetPoint("CENTER", 0, 20)
    emptyState:SetWidth(300)
    emptyState:SetHeight(80)

    previousButton = CreateButton(listPanel, "<", 28, 24)
    previousButton:SetPoint("BOTTOMRIGHT", -92, 10)
    previousButton:SetScript("OnClick", function()
        state.page = math.max(1, state.page - 1)
        state.selectedID = nil
        UpdateListings()
    end)
    pageText = CreateText(listPanel, "Page 1 / 1", 9, COLORS.muted, "CENTER")
    pageText:SetPoint("BOTTOMRIGHT", -35, 10)
    pageText:SetWidth(58)
    pageText:SetHeight(24)
    nextButton = CreateButton(listPanel, ">", 28, 24)
    nextButton:SetPoint("BOTTOMRIGHT", -5, 10)
    nextButton:SetScript("OnClick", function()
        state.page = state.page + 1
        state.selectedID = nil
        UpdateListings()
    end)

    local detailsPanel = CreateFrame("Frame", nil, mainFrame)
    detailsPanel:SetPoint("TOPLEFT", 579, -61)
    detailsPanel:SetPoint("BOTTOMRIGHT", -1, 1)
    AddBackground(detailsPanel, { 0.047, 0.054, 0.068, 1 }, { 0.10, 0.11, 0.14, 1 })
    BuildDetailsPanel(detailsPanel)

    if RavioliFamilyActivityFinderDB and RavioliFamilyActivityFinderDB.position then
        local position = RavioliFamilyActivityFinderDB.position
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or "CENTER", position.x or 0, position.y or 0)
    end
end

local function EscapeField(value)
    return tostring(value or ""):gsub("[%%|~\r\n]", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function UnescapeField(value)
    return (value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function SplitPayload(payload)
    local fields = {}
    for field in (payload .. "|"):gmatch("(.-)|") do table.insert(fields, UnescapeField(field)) end
    return fields
end

local function CompactText(value, maximumLength)
    local text = tostring(value or ""):gsub("[%%%^|~\r\n]", " ")
    return Trim(text):sub(1, maximumLength or 40)
end

local function SplitCompactPayload(payload)
    local fields = {}
    for field in ((payload or "") .. "~"):gmatch("(.-)~") do
        table.insert(fields, field)
    end
    return fields
end

local function QueueChannelMessage(message)
    if runtime.channelID == 0 or not SendChatMessage then return false end
    if type(message) ~= "string" or message == "" or #message > 245 then return false end
    if #runtime.outboundQueue >= 80 then return false end
    table.insert(runtime.outboundQueue, message)
    return true
end

QueueDirectAction = function(prefix, values)
    local fields = {
        SanitizePlayerName(UnitName("player") or "Unknown"),
        GetSessionID(),
    }
    for _, value in ipairs(values or {}) do
        table.insert(fields, CompactText(value, 60))
    end
    return QueueChannelMessage(prefix .. table.concat(fields, "~"))
end

local function SendTransportMessage(message)
    if runtime.channelID == 0 or not SendChatMessage then return false end
    if type(message) ~= "string" or message:sub(1, #WIRE_PREFIX) ~= WIRE_PREFIX then return false end

    -- Raw pipes are chat escape characters and can make SendChatMessage reject
    -- the packet. Fields escape literal tildes, so tilde is a safe wire separator.
    local transportSender = EscapeField(SanitizePlayerName(UnitName("player") or "Unknown"))
    local transportSession = EscapeField(GetSessionID())
    local payload = (transportSender .. "|" .. transportSession .. "|"
        .. message:sub(#WIRE_PREFIX + 1)):gsub("|", "~")
    return QueueChannelMessage(CHAT_WIRE_PREFIX .. payload)
end

local function SendWirePayload(payload)
    if #payload <= 200 then
        return SendTransportMessage(WIRE_PREFIX .. payload)
    end

    local messageID = tostring(time()) .. tostring(math.random(100, 999))
    local chunkSize = 180
    local total = math.ceil(#payload / chunkSize)
    local queued = true
    for index = 1, total do
        local chunk = payload:sub(((index - 1) * chunkSize) + 1, index * chunkSize)
        if not SendTransportMessage(WIRE_PREFIX .. "C|" .. messageID .. "|" .. index .. "|" .. total .. "|" .. chunk) then
            queued = false
        end
    end
    return queued
end

local function FindOwnedListingByWireID(id)
    return FindOwnedListingByID(id)
end

local function SendCompactListing(listing)
    local fields = {
        SanitizePlayerName(UnitName("player") or "Unknown"),
        GetSessionID(),
        tostring(listing.id or "0"),
        (listing.category and listing.category ~= "ALL" and categoryByKey[listing.category])
            and listing.category or "CUSTOM",
        CompactText(listing.title, 50),
        CompactText(listing.activity, 35),
        tostring(listing.currentSize or 1),
        tostring(listing.groupSize or 5),
        listing.status or "OPEN",
        CompactText(listing.startTime or "Now", 15),
        tostring(listing.createdAt or time()),
        tostring(listing.expiresAt or 0),
        NormalizeGameMode(listing.gameMode),
        CompactText(listing.notes, 40),
    }
    return QueueChannelMessage(LISTING_WIRE_PREFIX .. table.concat(fields, "~"))
end

BroadcastListing = function(listing)
    if not listing or not IsOwnedListing(listing) then return end
    if listing.status ~= "OPEN" and listing.status ~= "FULL" then
        if BroadcastRemoval then BroadcastRemoval(listing.id) end
        return
    end
    if not RavioliFamilyActivityFinderDB.settings.shareListings then return end
    listing.currentSize = GetCurrentGroupSize()
    if SendCompactListing(listing) then
        runtime.outboundListingPackets = runtime.outboundListingPackets + 1
    end
    if (listing.notes and listing.notes ~= "") or (listing.questLink and listing.questLink ~= "") then
        local metadata = { "M", listing.id, listing.notes or "", listing.questLink or "" }
        for index, value in ipairs(metadata) do metadata[index] = EscapeField(value) end
        SendWirePayload(table.concat(metadata, "|"))
    end
end

BroadcastRemoval = function(id)
    return QueueDirectAction(REMOVAL_WIRE_PREFIX, { id })
end

BroadcastAllListings = function()
    if not RavioliFamilyActivityFinderDB or not RavioliFamilyActivityFinderDB.settings.shareListings then return end
    for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
        if listing.status == "OPEN" or listing.status == "FULL" then BroadcastListing(listing) end
    end
end

AcceptApplicant = function(listing, applicant)
    if not listing or not applicant or not IsOwnedListing(listing) then return end
    if listing.status ~= "OPEN" then
        Print("Reopen the listing before inviting applicants.")
        return
    end
    local listKey = tostring(listing.id)
    local pendingInvites = 0
    for _, existing in ipairs(runtime.applicants[listKey] or {}) do
        if existing.status == "Inviting"
            or (existing.status == "Invited" and time() - (existing.invitedAt or time()) < 120) then
            pendingInvites = pendingInvites + 1
        end
    end
    runtime.inviteReservations[listKey] = runtime.inviteReservations[listKey] or {}
    for name, invitedAt in pairs(runtime.inviteReservations[listKey]) do
        if time() - invitedAt < 120 and not IsPlayerInGroup(name) then
            pendingInvites = pendingInvites + 1
        else
            runtime.inviteReservations[listKey][name] = nil
        end
    end
    if (listing.currentSize or GetCurrentGroupSize()) + pendingInvites >= (listing.groupSize or 5) then
        applicant.status = "Full"
        return
    end
    if not InviteUnit then
        Print("This game client does not provide the group invite function.")
        return
    end
    local inviteKey = (applicant.name or "Unknown"):lower()
    applicant.status = "Inviting"
    runtime.pendingInvites[inviteKey] = {
        applicant = applicant,
        listing = listing,
        attemptedAt = GetTime and GetTime() or time(),
    }
    InviteUnit(applicant.name)
    if applicantsFrame and applicantsFrame:IsShown() and OpenApplicantsFrame then OpenApplicantsFrame(listing) end
end

local function IsLikelyInviteFailure(message)
    local text = tostring(message or ""):lower()
    local markers = {
        "cannot", "can't", "could not", "failed", "not found", "not online",
        "already in", "declines", "declined", "not the party leader",
        "not the raid leader", "group is full", "party is full", "raid is full",
        "hardcore", "hc level", "hc mode", "different hc", "prestige",
        "incompatible", "unable to invite", "may not invite",
    }
    for _, marker in ipairs(markers) do
        if text:find(marker, 1, true) then return true end
    end
    return false
end

local function ContainsAnyInviteError(text, markers)
    for _, marker in ipairs(markers) do
        if text:find(marker, 1, true) then return true end
    end
    return false
end

local function ExpandInviteFailureTemplate(template, cleanError, applicantMode, groupMode)
    local whisper = template:gsub("{applicant_mode}", applicantMode)
    whisper = whisper:gsub("{applicant mode}", applicantMode)
    whisper = whisper:gsub("{group_mode}", groupMode)
    whisper = whisper:gsub("{group mode}", groupMode)
    whisper = whisper:gsub("{error}", cleanError)
    return CompactText(whisper, 220)
end

local function BuildSmartInviteFailureWhisper(cleanError, applicant, listing)
    local text = tostring(cleanError or ""):lower()
    if ContainsAnyInviteError(text, {
        "already in your group", "already in the group", "already in this group",
    }) then
        return "You are already in this group."
    end
    if ContainsAnyInviteError(text, {
        "already in a group", "already in a party", "already in a raid",
        "is in a group", "is in a party", "is in a raid",
    }) then
        return "You are already in a group."
    end
    if ContainsAnyInviteError(text, {
        "group is full", "party is full", "raid is full", "too many players",
    }) then
        return "This group is already full."
    end
    if ContainsAnyInviteError(text, { "not the party leader", "not the raid leader" }) then
        return "I cannot invite you because I am not the group leader."
    end

    local applicantMode = GetGameModeName(applicant.gameMode
        or runtime.peerGameModes[GetApplicantKey(applicant.name)] or "NORMAL")
    local groupMode = GetGameModeName((listing and listing.gameMode) or GetDetectedGameMode())
    local explicitModeError = ContainsAnyInviteError(text, {
        "hardcore", "hardmode", "hc level", "hc mode", "different hc",
        "different mode", "same mode", "game mode", "difficulty", "prestige",
        "incompatible mode",
    })
    local ambiguousModeError = ContainsAnyInviteError(text, {
        "cannot invite", "can't invite", "could not invite", "unable to invite",
        "may not invite", "incompatible",
    })
    if explicitModeError or (applicantMode ~= groupMode and ambiguousModeError) then
        local template = Trim(RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper or "")
        if template == "" then return nil end
        return ExpandInviteFailureTemplate(template, cleanError, applicantMode, groupMode)
    end

    return CompactText("Invite failed: " .. cleanError, 220)
end

local function FindPendingInvite(message)
    local text = tostring(message or ""):lower()
    local now = GetTime and GetTime() or time()
    local newestKey
    local newestAttempt = 0
    for key, pending in pairs(runtime.pendingInvites) do
        local age = now - (pending.attemptedAt or now)
        if age <= 4 then
            if text:find(key, 1, true) then return key, pending end
            if (pending.attemptedAt or 0) >= newestAttempt then
                newestKey = key
                newestAttempt = pending.attemptedAt or 0
            end
        end
    end
    return newestKey, newestKey and runtime.pendingInvites[newestKey] or nil
end

local function HandleInviteFailureMessage(message, trustMessage)
    if type(message) ~= "string" or message == "" then return end
    if not trustMessage and not IsLikelyInviteFailure(message) then return end
    local inviteKey, pending = FindPendingInvite(message)
    if not pending then return end

    runtime.pendingInvites[inviteKey] = nil
    local applicant = pending.applicant
    local listing = pending.listing
    if applicant then applicant.status = "Invite Failed" end
    local cleanError = CompactText(message, 150)
    if RavioliFamilyActivityFinderDB.settings.autoWhisperInviteErrors
        and SendChatMessage and applicant and applicant.name then
        local whisper = BuildSmartInviteFailureWhisper(cleanError, applicant, listing)
        if whisper and whisper ~= "" then
            SendChatMessage(whisper, "WHISPER", nil, applicant.name)
        end
    end
    Print("Invite to " .. ((applicant and applicant.name) or "the applicant")
        .. " failed: " .. cleanError)
    if applicantsFrame and applicantsFrame:IsShown() and listing and OpenApplicantsFrame then
        OpenApplicantsFrame(listing)
    end
end

local function CompletePendingInvites()
    local now = GetTime and GetTime() or time()
    local refreshListing
    for key, pending in pairs(runtime.pendingInvites) do
        if now - (pending.attemptedAt or now) >= 1.5 then
            runtime.pendingInvites[key] = nil
            local applicant = pending.applicant
            local listing = pending.listing
            if applicant and listing then
                applicant.status = IsPlayerInGroup(applicant.name) and "Joined" or "Invited"
                applicant.invitedAt = time()
                local listKey = tostring(listing.id)
                runtime.inviteReservations[listKey] = runtime.inviteReservations[listKey] or {}
                runtime.inviteReservations[listKey][GetApplicantKey(applicant.name)] = time()
                QueueDirectAction(RESPONSE_WIRE_PREFIX,
                    { applicant.name, "A", listing.id, listing.title or "Activity" })
                Notify("Invitation sent to " .. applicant.name .. ".", false)
                refreshListing = listing
            end
        end
    end
    if refreshListing then
        UpdateListings()
        if applicantsFrame and applicantsFrame:IsShown() and OpenApplicantsFrame then
            OpenApplicantsFrame(refreshListing)
        end
    end
end

DeclineApplicant = function(listing, applicant)
    if not listing or not applicant or not IsOwnedListing(listing) then return end
    runtime.pendingInvites[(applicant.name or "Unknown"):lower()] = nil
    SetDeclineLockout(listing, applicant.name)
    QueueDirectAction(RESPONSE_WIRE_PREFIX,
        { applicant.name, "D", listing.id, listing.title or "Activity" })
    RemoveApplicantFromListing(listing, applicant)
    UpdateListings()
    if applicantsFrame and applicantsFrame:IsShown() and OpenApplicantsFrame then OpenApplicantsFrame(listing) end
end

SendJoinRequest = function(listing)
    if not listing then return end
    if IsOwnedListing(listing) or IsLocalPlayerName(listing.owner) then
        Print("You cannot apply to your own listing.")
        return
    end
    local cooldown = GetApplicationCooldownRemaining(listing.id)
    if cooldown > 0 then
        Print("You can re-apply to this listing in " .. cooldown .. " seconds.")
        return
    end
    local playerLevel = UnitLevel("player") or 1
    local className = UnitClass("player") or "Unknown"
    local queued = QueueDirectAction(REQUEST_WIRE_PREFIX,
        { listing.owner, listing.remoteID or listing.id, playerLevel, className })
    if queued then
        runtime.requested[listing.id] = time()
        Print("Invite request sent to " .. (listing.owner or "the organizer") .. ".")
        UpdateListings()
    else
        Print("Invite request could not be sent. Refresh the finder and try again.")
    end
end

local function ProcessWirePayload(payload, sender, transportSession)
    local fields = SplitPayload(payload)
    local command = fields[1]
    local playerName = UnitName("player") or ""
    local cleanSender = SanitizePlayerName(sender)

    local isSelf
    if transportSession and transportSession ~= "" then
        isSelf = transportSession == GetSessionID()
    else
        isSelf = cleanSender:lower() == playerName:lower()
    end
    if isSelf then return end
    runtime.processedRemotePayloads = runtime.processedRemotePayloads + 1
    runtime.lastRemoteCommand = tostring(command or "")
    local peerKey = cleanSender:lower()
    local wasKnownPeer = runtime.peers[peerKey]
        and time() - runtime.peers[peerKey] <= PEER_TIMEOUT_SECONDS
    runtime.peers[peerKey] = time()
    runtime.lastReceivedAt = time()
    UpdateConnectionStatus()

    if command == "L" then
        local wireID = fields[2]
        local key = GetListingKey(cleanSender, wireID)
        local isNew = runtime.remoteListings[key] == nil
        for existingKey, existing in pairs(runtime.remoteListings) do
            if existingKey ~= key and (existing.owner or ""):lower() == cleanSender:lower() then
                runtime.remoteListings[existingKey] = nil
            end
        end
        local remoteCategory = (fields[3] and fields[3] ~= "ALL" and categoryByKey[fields[3]]) and fields[3] or "CUSTOM"
        local targetSize = math.max(2, math.min(40, tonumber(fields[7]) or 5))
        local currentSize = math.max(1, math.min(targetSize, tonumber(fields[6]) or 1))
        local remoteStatus = fields[8]
        if remoteStatus ~= "OPEN" and remoteStatus ~= "FULL" then
            runtime.remoteListings[key] = nil
            UpdateListings()
            return
        end
        local remoteCreatedAt = tonumber(fields[13]) or time()
        if remoteCreatedAt <= 0 or remoteCreatedAt > time() + 60 then remoteCreatedAt = time() end
        local remoteExpiresAt = tonumber(fields[14]) or 0
        local maximumRemoteExpiry = remoteCreatedAt + (30 * 60)
        if remoteExpiresAt <= 0 or remoteExpiresAt > maximumRemoteExpiry then
            remoteExpiresAt = maximumRemoteExpiry
        end
        local remoteListing = {
            id = key,
            remoteID = wireID,
            remote = true,
            isOwner = false,
            category = remoteCategory,
            title = (fields[4] or "Untitled activity"):sub(1, 60),
            activity = (fields[5] or ""):sub(1, 60),
            owner = cleanSender,
            currentSize = currentSize,
            groupSize = targetSize,
            status = remoteStatus,
            startTime = (fields[10] or "Now"):sub(1, 30),
            notes = (fields[12] or ""):sub(1, 180),
            createdAt = remoteCreatedAt,
            expiresAt = remoteExpiresAt,
            questLink = fields[15] or "",
            gameMode = NormalizeGameMode(fields[16]),
            lastSeen = time(),
        }
        runtime.remoteListings[key] = remoteListing
        runtime.importedListingPackets = runtime.importedListingPackets + 1
        local matchesCurrentView = (state.category == "ALL" or remoteListing.category == state.category)
            and MatchesSearch(remoteListing, Trim(state.search):lower())
        if isNew and matchesCurrentView and RavioliFamilyActivityFinderDB.settings.notifyListings and remoteListing.status == "OPEN" then
            Notify("New " .. GetCategoryShortName(remoteListing.category) .. " listing: " .. remoteListing.title, true)
        end
        UpdateListings()
    elseif command == "M" then
        local listing = runtime.remoteListings[GetListingKey(cleanSender, fields[2])]
        if not listing then return end
        listing.notes = (fields[3] or ""):sub(1, 180)
        listing.questLink = fields[4] or ""
        listing.lastSeen = time()
        UpdateListings()
    elseif command == "X" then
        runtime.remoteListings[GetListingKey(cleanSender, fields[2])] = nil
        UpdateListings()
    elseif command == "Q" then
        local now = GetTime and GetTime() or time()
        if (runtime.lastRefreshResponseAt == 0
            or now - runtime.lastRefreshResponseAt >= MANUAL_REFRESH_COOLDOWN_SECONDS)
            and not runtime.pendingRefreshBroadcastAt then
            runtime.pendingRefreshBroadcastAt = now + (math.random(0, 50) / 10)
        end
    elseif command == "H" then
        if not wasKnownPeer then
            QueueDirectAction(PRESENCE_WIRE_PREFIX)
        end
        return
    elseif command == "R" then
        local target = fields[2] or ""
        if target:lower() ~= playerName:lower() then return end
        local listing = FindOwnedListingByWireID(fields[3])
        if not listing or listing.status ~= "OPEN" then return end
        local applicantName = cleanSender
        if IsLocalPlayerName(applicantName) then return end
        if HasDeclineLockout(listing, applicantName) then return end
        local listKey = tostring(listing.id)
        runtime.applicants[listKey] = runtime.applicants[listKey] or {}
        local applicants = runtime.applicants[listKey]
        local applicant
        for _, existing in ipairs(applicants) do
            if existing.name:lower() == applicantName:lower() then applicant = existing break end
        end
        if not applicant then
            applicant = {
                name = applicantName,
                level = tonumber(fields[5]) or 1,
                className = fields[6] or "Unknown",
                gameMode = runtime.peerGameModes[applicantName:lower()] or "NORMAL",
                createdAt = time(),
                status = "Waiting",
            }
            table.insert(applicants, 1, applicant)
            Notify(applicantName .. " requested an invite for " .. (listing.title or "your activity") .. ".", true)
        end
        if listing.autoInvite and applicant.status == "Waiting" then AcceptApplicant(listing, applicant) end
        UpdateListings()
    elseif command == "A" or command == "D" then
        local target = fields[2] or ""
        if target:lower() ~= playerName:lower() then return end
        if command == "A" then
            Notify("You were invited to " .. (fields[4] or "an activity") .. ".", true)
        else
            Notify("Your request for " .. (fields[4] or "an activity") .. " was declined.", true)
        end
    end
end

HandleChannelMessage = function(message, sender, channelString, channelNumber, channelName)
    if type(message) ~= "string" then return end
    if not IsFinderChannelEvent(message, channelString, channelNumber, channelName) then return end

    runtime.finderChannelEvents = runtime.finderChannelEvents + 1
    runtime.lastChannelLabel = tostring(channelName or channelString or channelNumber or "")
    runtime.lastRawSender = tostring(sender or "")

    local cleanMessage = StripChatFormatting(message)

    local presenceMarker = cleanMessage:find(PRESENCE_WIRE_PREFIX, 1, true)
    if presenceMarker then
        local fields = SplitCompactPayload(cleanMessage:sub(presenceMarker + #PRESENCE_WIRE_PREFIX))
        if #fields < 2 then return end
        local cleanSender = SanitizePlayerName(fields[1])
        local transportSession = fields[2]
        ObserveTransportGameMode(cleanMessage, presenceMarker, cleanSender, transportSession)
        if transportSession == "" or transportSession == GetSessionID() then return end
        runtime.peers[cleanSender:lower()] = time()
        runtime.lastReceivedAt = time()
        UpdateConnectionStatus()
        return
    end

    local refreshMarker = cleanMessage:find(REFRESH_WIRE_PREFIX, 1, true)
    if refreshMarker then
        local fields = SplitCompactPayload(cleanMessage:sub(refreshMarker + #REFRESH_WIRE_PREFIX))
        if #fields < 2 then return end
        local cleanSender = SanitizePlayerName(fields[1])
        local transportSession = fields[2]
        ObserveTransportGameMode(cleanMessage, refreshMarker, cleanSender, transportSession)
        if transportSession == "" or transportSession == GetSessionID() then return end
        runtime.peers[cleanSender:lower()] = time()
        runtime.lastReceivedAt = time()
        UpdateConnectionStatus()
        local now = GetTime and GetTime() or time()
        if (runtime.lastRefreshResponseAt == 0
            or now - runtime.lastRefreshResponseAt >= MANUAL_REFRESH_COOLDOWN_SECONDS)
            and not runtime.pendingRefreshBroadcastAt then
            runtime.pendingRefreshBroadcastAt = now + (math.random(0, 50) / 10)
        end
        return
    end

    local removalMarker = cleanMessage:find(REMOVAL_WIRE_PREFIX, 1, true)
    if removalMarker then
        local fields = SplitCompactPayload(cleanMessage:sub(removalMarker + #REMOVAL_WIRE_PREFIX))
        if #fields < 3 then return end
        local cleanSender = SanitizePlayerName(fields[1])
        local transportSession = fields[2]
        local applicantMode = ObserveTransportGameMode(cleanMessage, requestMarker, cleanSender, transportSession)
        if transportSession == "" or transportSession == GetSessionID() then return end
        runtime.remoteListings[GetListingKey(cleanSender, fields[3])] = nil
        if state.selectedID == GetListingKey(cleanSender, fields[3]) then state.selectedID = nil end
        UpdateListings()
        return
    end

    local requestMarker = cleanMessage:find(REQUEST_WIRE_PREFIX, 1, true)
    if requestMarker then
        local fields = SplitCompactPayload(cleanMessage:sub(requestMarker + #REQUEST_WIRE_PREFIX))
        if #fields < 6 then return end
        local cleanSender = SanitizePlayerName(fields[1])
        local transportSession = fields[2]
        if transportSession == "" or transportSession == GetSessionID() then return end
        if IsLocalPlayerName(cleanSender) then return end
        local playerName = SanitizePlayerName(UnitName("player") or "Unknown")
        if SanitizePlayerName(fields[3]):lower() ~= playerName:lower() then return end
        local listing = FindOwnedListingByWireID(fields[4])
        if not listing or listing.status ~= "OPEN" then return end
        if HasDeclineLockout(listing, cleanSender) then return end

        local listKey = tostring(listing.id)
        runtime.applicants[listKey] = runtime.applicants[listKey] or {}
        local applicants = runtime.applicants[listKey]
        local applicant
        for _, existing in ipairs(applicants) do
            if (existing.name or ""):lower() == cleanSender:lower() then
                applicant = existing
                break
            end
        end
        if not applicant then
            applicant = {
                name = cleanSender,
                level = tonumber(fields[5]) or 1,
                className = fields[6] or "Unknown",
                gameMode = applicantMode,
                createdAt = time(),
                status = "Waiting",
            }
            table.insert(applicants, 1, applicant)
            Notify(cleanSender .. " requested an invite for " .. (listing.title or "your activity") .. ".", true)
        elseif applicant.status ~= "Joined" then
            applicant.status = "Waiting"
            applicant.gameMode = applicantMode
            applicant.createdAt = time()
            applicant.declinedAt = nil
            Notify(cleanSender .. " re-applied for " .. (listing.title or "your activity") .. ".", true)
        end
        if listing.autoInvite and applicant.status == "Waiting" then AcceptApplicant(listing, applicant) end
        UpdateListings()
        return
    end

    local responseMarker = cleanMessage:find(RESPONSE_WIRE_PREFIX, 1, true)
    if responseMarker then
        local fields = SplitCompactPayload(cleanMessage:sub(responseMarker + #RESPONSE_WIRE_PREFIX))
        if #fields < 6 then return end
        if fields[2] == "" or fields[2] == GetSessionID() then return end
        local playerName = SanitizePlayerName(UnitName("player") or "Unknown")
        if SanitizePlayerName(fields[3]):lower() ~= playerName:lower() then return end
        local cleanSender = SanitizePlayerName(fields[1])
        if fields[4] == "A" then
            Notify("You were invited to " .. (fields[6] or "an activity") .. ".", true)
        elseif fields[4] == "D" then
            runtime.requested[GetListingKey(cleanSender, fields[5])] = time()
            Notify("Your request for " .. (fields[6] or "an activity") .. " was declined.", true)
            UpdateListings()
        end
        return
    end

    local listingMarker = cleanMessage:find(LISTING_WIRE_PREFIX, 1, true)
    if listingMarker then
        runtime.compactListingsReceived = runtime.compactListingsReceived + 1
        local compactPayload = cleanMessage:sub(listingMarker + #LISTING_WIRE_PREFIX)
        local compactFields = SplitCompactPayload(compactPayload)
        if #compactFields < 13 then
            runtime.malformedCompactListings = runtime.malformedCompactListings + 1
            return
        end

        local cleanSender = SanitizePlayerName(compactFields[1])
        local transportSession = compactFields[2]
        local observedMode = ObserveTransportGameMode(cleanMessage, listingMarker, cleanSender, transportSession)
        runtime.protocolMessages = runtime.protocolMessages + 1
        runtime.lastTransportSender = cleanSender
        runtime.lastTransportSession = transportSession

        if IsLocalPlayerName(cleanSender) then
            for existingKey, existing in pairs(runtime.remoteListings) do
                if IsLocalPlayerName(existing.owner) then
                    runtime.remoteListings[existingKey] = nil
                    if state.selectedID == existingKey then state.selectedID = nil end
                end
            end
            UpdateListings()
            return
        end

        if transportSession ~= "" and transportSession ~= GetSessionID() then
            runtime.otherProtocolMessages = runtime.otherProtocolMessages + 1
            runtime.lastOtherSender = cleanSender
            runtime.peers[cleanSender:lower()] = time()
            runtime.lastReceivedAt = time()
            UpdateConnectionStatus()
        end

        if transportSession == "" or transportSession == GetSessionID() then return end

        runtime.processedRemotePayloads = runtime.processedRemotePayloads + 1
        runtime.lastRemoteCommand = "L"
        local wireID = compactFields[3]
        local key = GetListingKey(cleanSender, wireID)
        local isNew = runtime.remoteListings[key] == nil
        for existingKey, existing in pairs(runtime.remoteListings) do
            if existingKey ~= key and (existing.owner or ""):lower() == cleanSender:lower() then
                runtime.remoteListings[existingKey] = nil
            end
        end

        local remoteStatus = compactFields[9]
        if remoteStatus ~= "OPEN" and remoteStatus ~= "FULL" then
            runtime.remoteListings[key] = nil
            UpdateListings()
            return
        end
        local remoteCreatedAt = tonumber(compactFields[11]) or time()
        if remoteCreatedAt <= 0 or remoteCreatedAt > time() + 60 then remoteCreatedAt = time() end
        local remoteExpiresAt = tonumber(compactFields[12]) or 0
        local maximumRemoteExpiry = remoteCreatedAt + (30 * 60)
        if remoteExpiresAt <= 0 or remoteExpiresAt > maximumRemoteExpiry then
            remoteExpiresAt = maximumRemoteExpiry
        end
        local remoteCategory = compactFields[4]
        if remoteCategory == "ALL" or not categoryByKey[remoteCategory] then remoteCategory = "CUSTOM" end
        local targetSize = math.max(2, math.min(40, tonumber(compactFields[8]) or 5))
        local currentSize = math.max(1, math.min(targetSize, tonumber(compactFields[7]) or 1))
        local remoteListing = {
            id = key,
            remoteID = wireID,
            remote = true,
            isOwner = false,
            category = remoteCategory,
            title = (compactFields[5] or "Untitled activity"):sub(1, 60),
            activity = (compactFields[6] or ""):sub(1, 60),
            owner = cleanSender,
            currentSize = currentSize,
            groupSize = targetSize,
            status = remoteStatus,
            startTime = (compactFields[10] or "Now"):sub(1, 30),
            notes = (compactFields[14] or ""):sub(1, 180),
            createdAt = remoteCreatedAt,
            expiresAt = remoteExpiresAt,
            questLink = "",
            gameMode = observedMode,
            lastSeen = time(),
        }
        runtime.remoteListings[key] = remoteListing
        runtime.importedListingPackets = runtime.importedListingPackets + 1
        local matchesCurrentView = (state.category == "ALL" or remoteListing.category == state.category)
            and MatchesSearch(remoteListing, Trim(state.search):lower())
        if isNew and matchesCurrentView and RavioliFamilyActivityFinderDB.settings.notifyListings then
            Notify("New " .. GetCategoryShortName(remoteListing.category) .. " listing: " .. remoteListing.title, true)
        end
        UpdateListings()
        return
    end

    local payload
    local chatMarker = cleanMessage:find(CHAT_WIRE_PREFIX, 1, true)
    local identityMarker = cleanMessage:find(LEGACY_IDENTITY_WIRE_PREFIX, 1, true)
    local legacyChatMarker = cleanMessage:find(LEGACY_CHAT_WIRE_PREFIX, 1, true)
    local legacyMarker = cleanMessage:find(WIRE_PREFIX, 1, true)
    local hasEmbeddedSender = false
    local hasEmbeddedSession = false
    if chatMarker then
        payload = cleanMessage:sub(chatMarker + #CHAT_WIRE_PREFIX):gsub("~", "|")
        hasEmbeddedSender = true
        hasEmbeddedSession = true
    elseif identityMarker then
        payload = cleanMessage:sub(identityMarker + #LEGACY_IDENTITY_WIRE_PREFIX):gsub("~", "|")
        hasEmbeddedSender = true
    elseif legacyChatMarker then
        payload = cleanMessage:sub(legacyChatMarker + #LEGACY_CHAT_WIRE_PREFIX):gsub("~", "|")
    elseif legacyMarker then
        payload = cleanMessage:sub(legacyMarker + #WIRE_PREFIX)
    else
        return
    end
    runtime.protocolMessages = runtime.protocolMessages + 1
    local cleanSender = SanitizePlayerName(sender)
    local transportSession
    if hasEmbeddedSession then
        local encodedSender, encodedSession, packetPayload = payload:match("^([^|]+)|([^|]+)|(.*)$")
        if not encodedSender or not encodedSession then return end
        cleanSender = SanitizePlayerName(UnescapeField(encodedSender))
        transportSession = UnescapeField(encodedSession)
        payload = packetPayload
    elseif hasEmbeddedSender then
        local encodedSender, packetPayload = payload:match("^([^|]+)|(.*)$")
        if not encodedSender then return end
        cleanSender = SanitizePlayerName(UnescapeField(encodedSender))
        payload = packetPayload
    end
    runtime.lastTransportSender = cleanSender
    runtime.lastTransportSession = transportSession or ""
    ObserveTransportGameMode(cleanMessage,
        chatMarker or identityMarker or legacyChatMarker or legacyMarker,
        cleanSender, transportSession or "")
    local packetIsOther = transportSession and transportSession ~= ""
        and transportSession ~= GetSessionID()
        or (not transportSession or transportSession == "")
            and cleanSender:lower() ~= (UnitName("player") or ""):lower()
    if packetIsOther then
        runtime.otherProtocolMessages = runtime.otherProtocolMessages + 1
        runtime.lastOtherSender = cleanSender
        local peerKey = cleanSender:lower()
        runtime.peers[peerKey] = time()
        runtime.lastReceivedAt = time()
        UpdateConnectionStatus()
    end
    if payload:sub(1, 2) == "C|" then
        local messageID, part, total, chunk = payload:match("^C|([^|]+)|(%d+)|(%d+)|(.*)$")
        if not messageID then return end
        part, total = tonumber(part), tonumber(total)
        if not part or not total or total < 1 or total > 10 or part < 1 or part > total then return end
        runtime.chunkPartsReceived = runtime.chunkPartsReceived + 1
        local key = (transportSession or cleanSender) .. ":" .. messageID
        local buffer = runtime.incomingChunks[key] or { parts = {}, total = total, updatedAt = time() }
        if buffer.total ~= total then runtime.incomingChunks[key] = nil return end
        buffer.parts[part] = chunk:sub(1, 200)
        buffer.updatedAt = time()
        runtime.incomingChunks[key] = buffer
        for index = 1, buffer.total do if not buffer.parts[index] then return end end
        local complete = table.concat(buffer.parts, "")
        runtime.incomingChunks[key] = nil
        runtime.chunkMessagesCompleted = runtime.chunkMessagesCompleted + 1
        ProcessWirePayload(complete, cleanSender, transportSession)
    else
        ProcessWirePayload(payload, cleanSender, transportSession)
    end
end

EnsureChannel = function()
    local wasConnected = runtime.channelID > 0
    local channelID = GetChannelName and GetChannelName(CHANNEL_NAME) or 0
    if not channelID or channelID == 0 then
        if JoinChannelByName then
            local chatFrameID = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetID and DEFAULT_CHAT_FRAME:GetID() or 1
            JoinChannelByName(CHANNEL_NAME, nil, chatFrameID)
        end
        channelID = GetChannelName and GetChannelName(CHANNEL_NAME) or 0
    end
    runtime.channelID = tonumber(channelID) or 0
    UpdateConnectionStatus()
    if runtime.channelID > 0 then
        if DEFAULT_CHAT_FRAME and ChatFrame_AddChannel then
            ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, CHANNEL_NAME)
        end
        if not wasConnected then
            QueueDirectAction(PRESENCE_WIRE_PREFIX)
            QueueDirectAction(REFRESH_WIRE_PREFIX)
        end
    end
    return runtime.channelID > 0
end

RefreshSharedListings = function(showMessage)
    local connected = EnsureChannel()
    if connected then
        if showMessage then
            local remaining = GetManualRefreshRemaining()
            if remaining > 0 then
                Print("Refresh is available again in " .. remaining .. " seconds.")
                UpdateRefreshButton()
                return
            end
        end
        local queued = QueueDirectAction(REFRESH_WIRE_PREFIX)
        if showMessage and queued then
            runtime.lastManualRefreshAt = time()
            UpdateRefreshButton()
        end
        if showMessage then
            local peerCount = GetActivePeerCount()
            if queued then
                Print("Refresh sent on RavioliFinder channel " .. runtime.channelID .. ". "
                    .. peerCount .. " Ravioli currently detected.")
            else
                Print("Refresh could not be queued. Please try again.")
            end
        end
    elseif showMessage then
        Print("Joining the RavioliFinder channel. Refresh will run automatically once connected.")
    end
end

RefreshGroupState = function()
    if not RavioliFamilyActivityFinderDB then return end
    local currentSize = GetCurrentGroupSize()
    local now = time()
    local changed = false
    local refreshApplicantsListing
    for index = #RavioliFamilyActivityFinderDB.listings, 1, -1 do
        local listing = RavioliFamilyActivityFinderDB.listings[index]
        local inactive = listing.status == "CLOSED" or listing.status == "EXPIRED"
        local inactiveSince = listing.closedAt or listing.updatedAt or listing.expiresAt or listing.createdAt or now
        if inactive and now - inactiveSince >= INACTIVE_REMOVAL_SECONDS then
            BroadcastRemoval(listing.id)
            runtime.applicants[tostring(listing.id)] = nil
            runtime.declineLockouts[tostring(listing.id)] = nil
            runtime.inviteReservations[tostring(listing.id)] = nil
            if tostring(state.selectedID) == tostring(listing.id) then state.selectedID = nil end
            table.remove(RavioliFamilyActivityFinderDB.listings, index)
            changed = true
        else
            local listingChanged = listing.currentSize ~= currentSize
            listing.currentSize = currentSize
            local abandonedListing = (listing.status == "OPEN" or listing.status == "FULL")
                and currentSize > 1 and not IsOwnListedGroup(listing)
            if abandonedListing then
                listing.status = "CLOSED"
                listing.closedAt = now
                listingChanged = true
                runtime.applicants[tostring(listing.id)] = {}
                runtime.inviteReservations[tostring(listing.id)] = {}
                for key, pending in pairs(runtime.pendingInvites) do
                    if pending.listing == listing then runtime.pendingInvites[key] = nil end
                end
                Print("Your active listing was closed because you joined another leader's group.")
            else
                local applicants = runtime.applicants[tostring(listing.id)] or {}
                for applicantIndex = #applicants, 1, -1 do
                    local applicant = applicants[applicantIndex]
                    if IsPlayerInGroup(applicant.name) then
                        table.remove(applicants, applicantIndex)
                        refreshApplicantsListing = listing
                        changed = true
                    end
                end
                local reservations = runtime.inviteReservations[tostring(listing.id)] or {}
                for name, invitedAt in pairs(reservations) do
                    if IsPlayerInGroup(name) or now - invitedAt >= 120 then reservations[name] = nil end
                end
                if listing.status ~= "EXPIRED" and listing.expiresAt and listing.expiresAt > 0 and now >= listing.expiresAt then
                    listing.status = "EXPIRED"
                    listing.closedAt = listing.closedAt or now
                    listingChanged = true
                elseif listing.status == "OPEN" and currentSize >= (listing.groupSize or 5) then
                    if listing.autoClose then
                        listing.status = "CLOSED"
                        listing.closedAt = now
                    else
                        listing.status = "FULL"
                    end
                    listingChanged = true
                elseif listing.status == "FULL" and currentSize < (listing.groupSize or 5) then
                    listing.status = "OPEN"
                    listing.closedAt = nil
                    listingChanged = true
                end
            end
            if listingChanged then BroadcastListing(listing) end
            changed = changed or listingChanged
        end
    end
    if changed then UpdateListings() end
    if refreshApplicantsListing and applicantsFrame and applicantsFrame:IsShown()
        and OpenApplicantsFrame then
        OpenApplicantsFrame(refreshApplicantsListing)
    end
end

local function CreateSettingToggle(parent, label, key, y, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", 20, y)
    button:SetWidth(340)
    button:SetHeight(28)
    button.box = CreateFrame("Frame", nil, button)
    button.box:SetPoint("LEFT", 0, 0)
    button.box:SetWidth(20)
    button.box:SetHeight(20)
    AddBackground(button.box, COLORS.panelLight, COLORS.border)
    button.mark = CreateText(button.box, "", 12, COLORS.gold, "CENTER")
    button.mark:SetAllPoints()
    button.label = CreateText(button, label, 11, COLORS.text)
    button.label:SetPoint("LEFT", 30, 0)
    button.key = key
    function button:Refresh()
        local enabled = RavioliFamilyActivityFinderDB.settings[self.key] == true
        self.mark:SetText(enabled and "X" or "")
        self.box:SetBackdropBorderColor(enabled and COLORS.gold[1] or COLORS.border[1], enabled and COLORS.gold[2] or COLORS.border[2], enabled and COLORS.gold[3] or COLORS.border[3], 1)
    end
    button:SetScript("OnClick", function(self)
        RavioliFamilyActivityFinderDB.settings[self.key] = not RavioliFamilyActivityFinderDB.settings[self.key]
        self:Refresh()
        if callback then callback(RavioliFamilyActivityFinderDB.settings[self.key]) end
    end)
    return button
end

local function BuildSettingsFrame()
    settingsFrame = CreateFrame("Frame", "RavioliFamilyActivityFinderSettingsFrame", UIParent)
    settingsFrame:SetWidth(400)
    settingsFrame:SetHeight(620)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:EnableMouse(true)
    AddBackground(settingsFrame, COLORS.background, COLORS.gold)
    settingsFrame:Hide()
    table.insert(UISpecialFrames, "RavioliFamilyActivityFinderSettingsFrame")

    local heading = CreateText(settingsFrame, "Ravioli Family Activity Finder Settings", 18, COLORS.text)
    heading:SetPoint("TOPLEFT", 20, -18)
    settingsFrame.connection = CreateText(settingsFrame, "Shared channel unavailable", 10, COLORS.muted)
    settingsFrame.connection:SetPoint("TOPLEFT", 20, -44)

    local close = CreateButton(settingsFrame, "X", 28, 28)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() settingsFrame:Hide() end)

    settingsFrame.toggles = {}
    settingsFrame.whisperMessageLabel = CreateText(settingsFrame,
        "HC MISMATCH MESSAGE: {applicant_mode}  {group_mode}  {error}", 9, COLORS.muted)
    settingsFrame.whisperMessageLabel:SetPoint("TOPLEFT", 50, -214)
    settingsFrame.whisperMessageHolder, settingsFrame.whisperMessageInput =
        CreateInput(settingsFrame, 330, 30, 180)
    settingsFrame.whisperMessageHolder:SetPoint("TOPLEFT", 50, -228)
    settingsFrame.whisperMessageInput:SetScript("OnTextChanged", function(self)
        RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper = self:GetText() or ""
    end)

    local function RefreshWhisperMessageEditor()
        local visible = RavioliFamilyActivityFinderDB.settings.autoWhisperInviteErrors == true
        if visible then
            settingsFrame.whisperMessageLabel:Show()
            settingsFrame.whisperMessageHolder:Show()
        else
            settingsFrame.whisperMessageLabel:Hide()
            settingsFrame.whisperMessageHolder:Hide()
        end
    end

    local function AddToggle(label, key, y, callback)
        local toggle = CreateSettingToggle(settingsFrame, label, key, y, callback)
        table.insert(settingsFrame.toggles, toggle)
    end
    AddToggle("Share my active listing with other addon users", "shareListings", -78, function(enabled)
        if enabled then BroadcastAllListings() else for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do BroadcastRemoval(listing.id) end end
    end)
    AddToggle("Automatically close my listing when the group is full", "autoClose", -112, function(enabled)
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do listing.autoClose = enabled end
        RefreshGroupState()
    end)
    AddToggle("Automatically invite eligible applicants", "autoInvite", -146, function(enabled)
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
            listing.autoInvite = enabled
            if enabled and listing.status == "OPEN" then
                for _, applicant in ipairs(runtime.applicants[tostring(listing.id)] or {}) do
                    if applicant.status == "Waiting" then AcceptApplicant(listing, applicant) end
                end
            end
        end
    end)
    AddToggle("Whisper applicants when an invite fails", "autoWhisperInviteErrors", -180, function()
        RefreshWhisperMessageEditor()
    end)
    AddToggle("Show finder notifications", "notifications", -270)
    AddToggle("Notify me about newly discovered listings", "notifyListings", -304)
    AddToggle("Play notification sounds", "sounds", -338)
    AddToggle("Show the floating finder button", "showLauncher", -372, function() RefreshLauncher() end)
    AddToggle("Lock the floating finder button", "lockLauncher", -406, function() RefreshLauncher() end)
    AddToggle("Keep the Ravioli Finder and Quest Log synchronized", "linkQuestLog", -440, function(enabled)
        if enabled and mainFrame and mainFrame:IsShown() then ShowLinkedQuestLog() end
    end)

    local expiryLabel = CreateText(settingsFrame, "AUTO-EXPIRE MY LISTING", 9, COLORS.muted)
    expiryLabel:SetPoint("TOPLEFT", 20, -480)
    settingsFrame.expiry = CreateButton(settingsFrame, "15 minutes", 360, 28)
    settingsFrame.expiry:SetPoint("TOPLEFT", 20, -495)
    settingsFrame.expiry:SetScript("OnClick", function(self)
        local current = NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes)
        local nextValue = EXPIRY_VALUES[1]
        for index, value in ipairs(EXPIRY_VALUES) do
            if value == current then nextValue = EXPIRY_VALUES[(index % #EXPIRY_VALUES) + 1] break end
        end
        RavioliFamilyActivityFinderDB.settings.expiryMinutes = nextValue
        self.label:SetText(nextValue .. " minutes")
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
            if listing.status ~= "EXPIRED" then
                listing.expiresAt = time() + (nextValue * 60)
                BroadcastListing(listing)
            end
        end
    end)

    local warning = CreateText(settingsFrame, "Listings expire after 5-30 minutes. Synchronized windows open and close together.", 9, COLORS.muted)
    warning:SetPoint("BOTTOMLEFT", 20, 18)
    warning:SetWidth(350)

    settingsFrame:SetScript("OnShow", function(self)
        if mainFrame and not mainFrame:IsShown() and ShowMainFrame then ShowMainFrame(true) end
        HideOtherSecondaryWindows(self)
        EnsureChannel()
        for _, toggle in ipairs(self.toggles) do toggle:Refresh() end
        self.whisperMessageInput:SetText(RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper or "")
        RefreshWhisperMessageEditor()
        local expiry = NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes)
        RavioliFamilyActivityFinderDB.settings.expiryMinutes = expiry
        self.expiry.label:SetText(expiry .. " minutes")
    end)
end

OpenSettingsFrame = function()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        if mainFrame and not mainFrame:IsShown() and ShowMainFrame then ShowMainFrame(true) end
        HideOtherSecondaryWindows(settingsFrame)
        settingsFrame:Show()
    end
end

local function BuildApplicantsFrame()
    applicantsFrame = CreateFrame("Frame", "RavioliFamilyActivityFinderApplicantsFrame", UIParent)
    applicantsFrame:SetWidth(490)
    applicantsFrame:SetHeight(390)
    applicantsFrame:SetPoint("CENTER")
    applicantsFrame:SetFrameStrata("DIALOG")
    applicantsFrame:EnableMouse(true)
    AddBackground(applicantsFrame, COLORS.background, COLORS.gold)
    applicantsFrame:Hide()
    table.insert(UISpecialFrames, "RavioliFamilyActivityFinderApplicantsFrame")
    applicantsFrame:SetScript("OnShow", function(self)
        if mainFrame and not mainFrame:IsShown() and ShowMainFrame then ShowMainFrame(true) end
        HideOtherSecondaryWindows(self)
    end)

    applicantsFrame.heading = CreateText(applicantsFrame, "Applicants", 18, COLORS.text)
    applicantsFrame.heading:SetPoint("TOPLEFT", 20, -18)
    applicantsFrame.summary = CreateText(applicantsFrame, "", 10, COLORS.muted)
    applicantsFrame.summary:SetPoint("TOPLEFT", 20, -44)
    local close = CreateButton(applicantsFrame, "X", 28, 28)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() applicantsFrame:Hide() end)

    applicantsFrame.rows = {}
    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, applicantsFrame)
        row:SetPoint("TOPLEFT", 20, -76 - ((index - 1) * 48))
        row:SetWidth(450)
        row:SetHeight(42)
        AddBackground(row, COLORS.panel, COLORS.border)
        row.name = CreateText(row, "", 12, COLORS.text)
        row.name:SetPoint("TOPLEFT", 10, -6)
        row.meta = CreateText(row, "", 9, COLORS.muted)
        row.meta:SetPoint("BOTTOMLEFT", 10, 6)
        row.status = CreateText(row, "", 9, COLORS.gold, "RIGHT")
        row.status:SetPoint("RIGHT", -224, 0)
        row.invite = CreateButton(row, "Invite", 64, 26)
        row.invite:SetPoint("RIGHT", -150, 0)
        row.decline = CreateButton(row, "Decline", 68, 26)
        row.decline:SetPoint("RIGHT", -76, 0)
        row.whisper = CreateButton(row, "Whisper", 70, 26)
        row.whisper:SetPoint("RIGHT", -4, 0)
        row.invite:SetScript("OnClick", function() AcceptApplicant(applicantsFrame.listing, row.applicant) end)
        row.decline:SetScript("OnClick", function() DeclineApplicant(applicantsFrame.listing, row.applicant) end)
        row.whisper:SetScript("OnClick", function()
            if row.applicant and ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. row.applicant.name .. " ") end
        end)
        applicantsFrame.rows[index] = row
    end
end

OpenApplicantsFrame = function(listing)
    if mainFrame and not mainFrame:IsShown() and ShowMainFrame then ShowMainFrame(true) end
    HideOtherSecondaryWindows(applicantsFrame)
    applicantsFrame.listing = listing
    applicantsFrame.heading:SetText("Applicants - " .. (listing.title or "Activity"))
    local applicants = runtime.applicants[tostring(listing.id)] or {}
    applicantsFrame.summary:SetText(#applicants .. (#applicants == 1 and " applicant" or " applicants"))
    for index, row in ipairs(applicantsFrame.rows) do
        local applicant = applicants[index]
        if applicant then
            row.applicant = applicant
            row.name:SetText(applicant.name)
            row.meta:SetText("Level " .. tostring(applicant.level or 1) .. " " .. (applicant.className or "Unknown"))
            row.status:SetText(applicant.status or "Waiting")
            row:Show()
        else
            row.applicant = nil
            row:Hide()
        end
    end
    applicantsFrame:Show()
end

local function BuildLauncherButton()
    launcherButton = CreateFrame("Button", "RavioliFamilyActivityFinderLauncher", UIParent)
    launcherButton:SetWidth(44)
    launcherButton:SetHeight(44)
    launcherButton:SetPoint("RIGHT", UIParent, "RIGHT", -24, 80)
    launcherButton:SetMovable(true)
    launcherButton:SetClampedToScreen(true)
    launcherButton:EnableMouse(true)
    launcherButton:RegisterForDrag("LeftButton")
    AddBackground(launcherButton, COLORS.panel, COLORS.gold)
    launcherButton.icon = launcherButton:CreateTexture(nil, "ARTWORK")
    launcherButton.icon:SetPoint("TOPLEFT", 5, -5)
    launcherButton.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    launcherButton.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    launcherButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    launcherButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    launcherButton:SetScript("OnDragStart", function(self)
        if not RavioliFamilyActivityFinderDB.settings.lockLauncher then
            self.dragging = true
            self:StartMoving()
        end
    end)
    launcherButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RavioliFamilyActivityFinderDB.launcherPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
        if self.dragging then self.justDraggedAt = GetTime() end
        self.dragging = false
    end)
    launcherButton:SetScript("OnClick", function(_, button)
        if launcherButton.justDraggedAt and GetTime() - launcherButton.justDraggedAt < 0.25 then return end
        if button == "RightButton" then OpenSettingsFrame() else ToggleMainFrame() end
    end)
    launcherButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    launcherButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ravioli Family Activity Finder", 1, 0.82, 0.3)
        GameTooltip:AddLine("Left-click: open finder", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine(RavioliFamilyActivityFinderDB.settings.lockLauncher and "Position locked" or "Drag to move", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    launcherButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if RavioliFamilyActivityFinderDB.launcherPosition then
        local position = RavioliFamilyActivityFinderDB.launcherPosition
        launcherButton:ClearAllPoints()
        launcherButton:SetPoint(position.point or "RIGHT", UIParent, position.relativePoint or "RIGHT", position.x or -24, position.y or 80)
    end
end

RefreshLauncher = function()
    if not launcherButton or not RavioliFamilyActivityFinderDB then return end
    if RavioliFamilyActivityFinderDB.settings.showLauncher then launcherButton:Show() else launcherButton:Hide() end
end

ShowMainFrame = function(openLinkedQuestLog)
    if not mainFrame then return end
    mainFrame:Show()
    UpdateListings()
    if openLinkedQuestLog ~= false
        and RavioliFamilyActivityFinderDB.settings.linkQuestLog then
        ShowLinkedQuestLog()
    end
end

ToggleMainFrame = function()
    if not mainFrame then return end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        ShowMainFrame(true)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
local initialized = false

local function FilterProtocolMessages(_, _, message)
    if type(message) ~= "string" then return false end
    local cleanMessage = StripChatFormatting(message)
    return cleanMessage:find(WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(CHAT_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(LEGACY_IDENTITY_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(LEGACY_CHAT_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(LISTING_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(REMOVAL_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(REQUEST_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(RESPONSE_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(REFRESH_WIRE_PREFIX, 1, true) ~= nil
        or cleanMessage:find(PRESENCE_WIRE_PREFIX, 1, true) ~= nil
end

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not initialized then return end
    CompletePendingInvites()
    local preciseNow = GetTime and GetTime() or time()
    if runtime.pendingRefreshBroadcastAt and preciseNow >= runtime.pendingRefreshBroadcastAt then
        runtime.pendingRefreshBroadcastAt = nil
        runtime.lastRefreshResponseAt = preciseNow
        QueueDirectAction(PRESENCE_WIRE_PREFIX)
        BroadcastAllListings()
    end
    runtime.outboundCooldown = math.max(0, runtime.outboundCooldown - elapsed)
    if runtime.channelID > 0 and runtime.outboundCooldown <= 0 and #runtime.outboundQueue > 0 then
        local outgoingMessage = table.remove(runtime.outboundQueue, 1)
        SendChatMessage(outgoingMessage, "CHANNEL", nil, runtime.channelID)
        runtime.outboundMessagesSent = runtime.outboundMessagesSent + 1
        runtime.outboundCooldown = 0.5
    end
    runtime.elapsed = runtime.elapsed + elapsed
    runtime.heartbeatElapsed = runtime.heartbeatElapsed + elapsed
    runtime.channelRetryElapsed = runtime.channelRetryElapsed + elapsed
    if runtime.elapsed < 1 then return end
    runtime.elapsed = 0
    local serviceMode = ReadEbonholdGameMode()
    if serviceMode then ApplyDetectedGameMode(serviceMode) end
    UpdateRefreshButton()
    local selectedListing = FindListingByID(state.selectedID)
    if selectedListing and not IsOwnedListing(selectedListing)
        and runtime.requested[selectedListing.id] then
        UpdateDetails(selectedListing)
    end

    if runtime.channelID == 0 and runtime.channelRetryElapsed >= 5 then
        runtime.channelRetryElapsed = 0
        EnsureChannel()
    end
    RefreshGroupState()
    if runtime.heartbeatElapsed >= HEARTBEAT_SECONDS then
        runtime.heartbeatElapsed = 0
        EnsureChannel()
        if runtime.channelID > 0 then
            QueueDirectAction(PRESENCE_WIRE_PREFIX)
            BroadcastAllListings()
        end
        UpdateConnectionStatus()
    end

    local now = time()
    local changed = false
    for key, listing in pairs(runtime.remoteListings) do
        if (listing.lastSeen and now - listing.lastSeen > REMOTE_TIMEOUT_SECONDS)
            or (listing.expiresAt and listing.expiresAt > 0 and now >= listing.expiresAt) then
            runtime.remoteListings[key] = nil
            if state.selectedID == key then state.selectedID = nil end
            changed = true
        end
    end
    for key, buffer in pairs(runtime.incomingChunks) do
        if now - (buffer.updatedAt or now) > 30 then runtime.incomingChunks[key] = nil end
    end
    if changed then UpdateListings() end
end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            if initialized then EnableQuestLogVisibilityLink() end
            return
        end

        if type(RavioliFamilyActivityFinderDB) ~= "table" then RavioliFamilyActivityFinderDB = {} end
        if type(RavioliFamilyActivityFinderDB.listings) ~= "table" then RavioliFamilyActivityFinderDB.listings = {} end
        if type(RavioliFamilyActivityFinderDB.settings) ~= "table" then RavioliFamilyActivityFinderDB.settings = {} end
        -- Ignore-list support was removed in 0.4.5; clear legacy saved entries.
        RavioliFamilyActivityFinderDB.blocked = nil
        for key, value in pairs(defaultSettings) do
            if RavioliFamilyActivityFinderDB.settings[key] == nil then RavioliFamilyActivityFinderDB.settings[key] = value end
        end
        if RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper
                == "Sorry, I couldn't invite you because: {error}"
            or RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper
                == "Sorry, I couldn't invite you: your mode is {applicant_mode}, while this group is {group_mode}." then
            RavioliFamilyActivityFinderDB.settings.inviteFailureWhisper = defaultSettings.inviteFailureWhisper
        end
        RavioliFamilyActivityFinderDB.settings.expiryMinutes = NormalizeExpiryMinutes(RavioliFamilyActivityFinderDB.settings.expiryMinutes)
        local maximumLocalExpiry = time() + (RavioliFamilyActivityFinderDB.settings.expiryMinutes * 60)
        local activeListingFound = false
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
            if listing.category == "PVP" then listing.category = "CUSTOM" end
            listing.roles = nil
            listing.isOwner = true
            listing.ownerGUID = listing.ownerGUID or (UnitGUID and UnitGUID("player"))
            listing.currentSize = listing.currentSize or GetCurrentGroupSize()
            listing.minimumLevel = nil
            listing.startTime = listing.startTime or "Now"
            listing.gameMode = NormalizeGameMode(listing.gameMode)
            listing.tags = nil
            listing.status = listing.status or "OPEN"
            if listing.status == "OPEN" or listing.status == "FULL" then
                if activeListingFound then
                    listing.status = "CLOSED"
                    listing.closedAt = listing.closedAt or listing.updatedAt or listing.createdAt or time()
                else
                    activeListingFound = true
                end
            end
            listing.autoClose = listing.autoClose == nil and RavioliFamilyActivityFinderDB.settings.autoClose or listing.autoClose
            listing.autoInvite = listing.autoInvite == nil and RavioliFamilyActivityFinderDB.settings.autoInvite or listing.autoInvite
            listing.expiresAt = tonumber(listing.expiresAt) or 0
            if listing.status ~= "EXPIRED"
                and (listing.expiresAt <= 0 or listing.expiresAt > maximumLocalExpiry) then
                listing.expiresAt = maximumLocalExpiry
            end
            if listing.status == "CLOSED" then
                listing.closedAt = tonumber(listing.closedAt) or listing.updatedAt or listing.createdAt or time()
            elseif listing.status == "EXPIRED" then
                listing.closedAt = tonumber(listing.closedAt)
                    or (listing.expiresAt > 0 and listing.expiresAt)
                    or listing.updatedAt or listing.createdAt or time()
            else
                listing.closedAt = nil
            end
        end
        RavioliFamilyActivityFinderDB.nextID = tonumber(RavioliFamilyActivityFinderDB.nextID) or 1

        BuildCreateFrame()
        BuildMainFrame()
        BuildSettingsFrame()
        BuildApplicantsFrame()
        BuildLauncherButton()
        EnableQuestLogVisibilityLink()
        RefreshLauncher()
        UpdateListings()

        if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", FilterProtocolMessages) end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("CHAT_MSG_CHANNEL")
        self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
        self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        self:RegisterEvent("RAID_ROSTER_UPDATE")
        self:RegisterEvent("UI_ERROR_MESSAGE")
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        initialized = true
        RequestEbonholdGameMode()
        local serviceMode = ReadEbonholdGameMode()
        if serviceMode then ApplyDetectedGameMode(serviceMode) end
        EnsureChannel()
    elseif not initialized then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnableQuestLogVisibilityLink()
        RequestEbonholdGameMode()
        local serviceMode = ReadEbonholdGameMode()
        if serviceMode then ApplyDetectedGameMode(serviceMode) end
        EnsureChannel()
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        EnsureChannel()
    elseif event == "CHAT_MSG_CHANNEL" then
        local message, sender, language, channelString, target, flags, unknown, channelNumber, channelName = ...
        runtime.allChannelEvents = runtime.allChannelEvents + 1
        HandleChannelMessage(message, sender, channelString, channelNumber, channelName)
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        RefreshGroupState()
    elseif event == "UI_ERROR_MESSAGE" then
        local first, second = ...
        local message = type(second) == "string" and second or first
        HandleInviteFailureMessage(message, true)
    elseif event == "CHAT_MSG_SYSTEM" then
        HandleInviteFailureMessage((...), false)
    end
end)

SLASH_RAVIOLIFAMILYACTIVITYFINDER1 = "/rav"
SLASH_RAVIOLIFAMILYACTIVITYFINDER2 = "/ravioli"
SLASH_RAVIOLIFAMILYACTIVITYFINDER3 = "/ravfinder"
SlashCmdList.RAVIOLIFAMILYACTIVITYFINDER = function(message)
    local command = Trim(message):lower()
    if command == "reset" then
        RavioliFamilyActivityFinderDB.position = nil
        RavioliFamilyActivityFinderDB.launcherPosition = nil
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER")
        end
        if launcherButton then
            launcherButton:ClearAllPoints()
            launcherButton:SetPoint("RIGHT", UIParent, "RIGHT", -24, 80)
        end
        Print("Window and launcher positions reset.")
    elseif command == "clear" then
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do BroadcastRemoval(listing.id) end
        RavioliFamilyActivityFinderDB.listings = {}
        state.selectedID = nil
        state.page = 1
        UpdateListings()
        Print("Local listings cleared.")
    elseif command == "settings" then
        OpenSettingsFrame()
    elseif command == "channel" then
        EnsureChannel()
        local channelID, channelName = 0, nil
        if GetChannelName then channelID, channelName = GetChannelName(CHANNEL_NAME) end
        Print("Version " .. VERSION .. "; channel: " .. tostring(channelName or CHANNEL_NAME) .. " (local number " .. tostring(channelID or 0) .. ").")
        Print("Detected Ravioli: " .. GetActivePeerCount() .. ".")
        Print("All channel events: " .. runtime.allChannelEvents .. "; RavioliFinder events: "
            .. runtime.finderChannelEvents .. "; protocol packets: " .. runtime.protocolMessages .. ".")
        Print("Packets from other addon sessions: " .. runtime.otherProtocolMessages
            .. (runtime.lastOtherSender ~= "" and "; last: " .. runtime.lastOtherSender .. "." or "."))
        local remoteListingCount = 0
        for _ in pairs(runtime.remoteListings) do remoteListingCount = remoteListingCount + 1 end
        local activeLocalListings = 0
        for _, listing in ipairs(RavioliFamilyActivityFinderDB.listings) do
            if listing.status == "OPEN" or listing.status == "FULL" then
                activeLocalListings = activeLocalListings + 1
            end
        end
        Print("Listing sharing: " .. (RavioliFamilyActivityFinderDB.settings.shareListings and "enabled" or "disabled")
            .. "; active local listings: " .. activeLocalListings
            .. "; listing broadcasts sent: " .. runtime.outboundListingPackets .. ".")
        Print("Transport messages sent: " .. runtime.outboundMessagesSent
            .. "; currently queued: " .. #runtime.outboundQueue .. ".")
        Print("Chunk parts received: " .. runtime.chunkPartsReceived
            .. "; complete chunked messages: " .. runtime.chunkMessagesCompleted .. ".")
        Print("Direct listing messages received: " .. runtime.compactListingsReceived
            .. "; malformed: " .. runtime.malformedCompactListings .. ".")
        Print("Decoded remote payloads: " .. runtime.processedRemotePayloads
            .. "; last command: " .. (runtime.lastRemoteCommand ~= "" and runtime.lastRemoteCommand or "none") .. ".")
        Print("Listing packets imported: " .. runtime.importedListingPackets
            .. "; remote listings currently stored: " .. remoteListingCount .. ".")
        if runtime.lastRawSender ~= "" then
            Print("Last event sender: " .. SanitizePlayerName(runtime.lastRawSender)
                .. "; packet sender: " .. (runtime.lastTransportSender ~= "" and runtime.lastTransportSender or "unknown") .. ".")
            if runtime.lastTransportSession ~= "" then
                Print("Last packet session: " .. (runtime.lastTransportSession == GetSessionID() and "self." or "other."))
            end
            Print("Last channel label: " .. (runtime.lastChannelLabel ~= "" and runtime.lastChannelLabel or "unknown") .. ".")
        end
    elseif command == "lock" then
        RavioliFamilyActivityFinderDB.settings.lockLauncher = not RavioliFamilyActivityFinderDB.settings.lockLauncher
        RefreshLauncher()
        Print("Floating button " .. (RavioliFamilyActivityFinderDB.settings.lockLauncher and "locked." or "unlocked."))
    elseif command == "help" then
        Print("/rav - toggle the window")
        Print("/rav reset - reset the window position")
        Print("/rav clear - clear local listings")
        Print("/rav settings - open settings")
        Print("/rav channel - show channel and Ravioli status")
        Print("/rav lock - lock or unlock the floating button")
    else
        ToggleMainFrame()
    end
end
