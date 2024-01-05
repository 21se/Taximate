script_author("21se")
script_moonloader(026)
script_version("1.3.7")
script_version_number(58)
script_url("github.com/21se/Taximate")
script_name(string.format("Taximate v%s (%d)", thisScript().version, thisScript().version_num))
local script_updates = {update = false}
local script_branch = "master"

local moonloader = require "moonloader"
local inicfg = require "inicfg"
local encoding = require "encoding"
local vkeys = require "vkeys"
local sampev = require "samp.events"
local imgui = require "imgui"

encoding.default = "CP1251"
local u8 = encoding.UTF8
local chat, orders, vehicle
local player, sounds, binds, ini
local notificationsQueue = {}
local fastMapKey = 0

local VEHICLE_MODEL_IDS = {
    ["Premier"] = 420,
    ["Cabbie"] = 438,
    ["Sentinel"] = 405,
    ["Sultan"] = 560,
    ["Buffalo"] = 402
}

local COLOR_LIST = {
    "[0] Без цвета",
    "[1] Зелёный",
    "[2] Светло-зелёный",
    "[3] Ярко-зелёный",
    "[4] Бирюзовый",
    "[5] Жёлто-зелёный",
    "[6] Тёмно-зелёный",
    "[7] Серо-зелёный",
    "[8] Красный",
    "[9] Ярко-красный",
    "[10] Оранжевый",
    "[11] Коричневый",
    "[12] Тёмно-красный",
    "[13] Серо-красный",
    "[14] Жёлто-оранжевый",
    "[15] Малиновый",
    "[16] Розовый",
    "[17] Синий",
    "[18] Голубой",
    "[19] Синяя сталь",
    "[20] Cине-зелёный",
    "[21] Тёмно-синий",
    "[22] Фиолетовый",
    "[23] Индиго",
    "[24] Серо-синий",
    "[25] Жёлтый",
    "[26] Кукурузный",
    "[27] Золотой",
    "[28] Старое золото",
    "[29] Оливковый",
    "[30] Серый",
    "[31] Серебро",
    "[32] Чёрный",
    "[33] Белый"
}

local MESSAGES = {
    newOrder = "^ %[Такси%] Диспетчер: Вызов от [a-zA-Z0-9_]+%[%d+%] .+%. Примерное расстояние .+м$",
    newOrderFormat = "^ %[Такси%] Диспетчер: Вызов от (.+)%[(%d+)%] .+%. Примерное расстояние (.+)$",
    orderAccepted = "^ %[Такси%] Диспетчер: [a-zA-Z0-9_]+%[%d+%] принял[а]? вызов от [a-zA-Z0-9_]+%[%d+%]$",
    orderAcceptedFormat = "^ %[Такси%] Диспетчер: (.+)%[%d+%] принял[а]? вызов от (.+)%[%d+%]$",
    wrongPerson = " ^%[Такси%] Диспетчер: Вызов от этого человека не поступал$",
    orderCanceled = "^ %[Такси%] Диспетчер: [a-zA-Z0-9_]+%[%d+%] отменил вызов$",
    orderCanceledFormat = "^ %[Такси%] Диспетчер: (.+)%[%d+%] отменил вызов$",
    orderCanceledByTaxi = "^ %[Такси%] Диспетчер: Вы отказались от вызова$",
    orderCanceledByQuit = "^ %[Такси%] Диспетчер: (.+) отменил вызов %(Выход из игры%)$",
    noOrders1 = "^ Вызовов не поступало$",
    noOrders2 = " ^%[Такси%] Диспетчер: От вас вызовов не поступало$",
    enterService1 = "^ Введите: /service$",
    enterService2 = "^ Введите: /service %[call / ac / cancel / chat%] %[police / medic / mechanic / food / taxi%]$",
    clist = "^ Цвет выбран$",
    payCheck = "^ Вы заработали .+ вирт. Деньги будут зачислены на ваш банковский счет в .+$",
    payCheckFormat = "^ Вы заработали (.+) / (.+) вирт. Деньги будут зачислены на ваш банковский счет в .+$",
    service = "^ %(%( Введите '/service' чтобы принять вызов %)%)$",
    GPS = "^ '.+' помечено на карте красной меткой. Дистанция .+ метров$",
    finishWork = "^ {00A86B}Используйте телефон {FFFFFF}%(%( /call %)%){00A86B} чтобы вызвать механика / таксиста$",
    passengerOut = "^ Пассажир вышел из такси. Использован купон на бесплатный проезд$",
    passengerOutFree = "^ Пассажир вышел из такси. Деньги будут зачислены во время зарплаты$",
    pay = "^ Вы получили (%d+) вирт, от [a-zA-Z0-9_]+%[%d+%]$",
    payFormat = "Вы получили (%d+) вирт, от (.+)%[",
    payDay = "^=.+=%[.+:.+%]=.+=$",
    antiFlood = "^ Не флуди!$",
    taxiChecker = "<< Бесплатное такси >>",
    skill = "Скилл: (%d+)	Опыт: .+ (%d+%.%d+)%%",
    rank = "Ранг: (%d+)  	Опыт: .+ (%d+%.%d+)%%",
    order = "([a-zA-Z0-9_]+)%[ID:(%d+)%](.+[^%d.])(%d.+).+%(",
    repair = "^ Механик [a-zA-Z0-9_]+ хочет отремонтировать ваш автомобиль за %d+ вирт{FFFFFF} %(%( Нажмите Y/N для принятия/отмены %)%)$",
    refill = "^ Механик [a-zA-Z0-9_]+ хочет заправить ваш автомобиль за %d+ вирт{FFFFFF} %(%( Нажмите Y/N для принятия/отмены %)%)$",
    refillFormat = "^ Механик .+ хочет заправить ваш автомобиль за (%d+) вирт{FFFFFF} %(%( Нажмите Y/N для принятия/отмены %)%)$",
    fuelClassic = "FUEL ~w~%d+",
    fuelClassicFormat = "FUEL ~w~(%d+)",
    currentOrderTextdraw = "([a-zA-Z0-9_]+)~n~distance: (%d+)m"
}

local FORMAT_NOTIFICATIONS = {
    newOrder = "Вызов от {4296f9}%s[%s]{ffffff} (%s)\nДистанция: {4296f9}%s",
    orderAccepted = "Принят вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s",
    cruiseControlEnabled = "Круиз-контроль {42ff96}включён",
    cruiseControlDisabled = "Круиз-контроль {d44331}выключен"
}

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then
        return
    end

    while not isSampAvailable() do
        wait(100)
    end

    repeat
        wait(100)
    until sampGetCurrentServerName() ~= "SA-MP"

    addEventHandler("onReceiveRpc", onReceiveRpc)
    local _, playerID = sampGetPlayerIdByCharHandle(PLAYER_PED)
    player.nickname = sampGetPlayerNickname(playerID)
    player.id = playerID

    chat.sendMessage("Меню настроек скрипта - {00CED1}/tm{FFFFFF}, страница скрипта: {00CED1}" .. thisScript().url)

    repeat
        wait(100)
    until sampGetPlayerScore(player.id) ~= 0

    if not doesDirectoryExist(getWorkingDirectory() .. "/config") then
        createDirectory(getWorkingDirectory() .. "/config")
    end
    if not doesDirectoryExist(getWorkingDirectory() .. "/config/Taximate") then
        createDirectory(getWorkingDirectory() .. "/config/Taximate")
    end

    ini = inicfg.load({settings = ini.settings}, "Taximate/settings.ini")
    imgui.initBuffers()
    sounds.loadSound("new_order")
    sounds.loadSound("correct_order")
    sounds.loadSound("new_passenger")
    imgui.ApplyCustomStyle()
    imgui.GetIO().Fonts:AddFontFromFileTTF(
        "C:/Windows/Fonts/arial.ttf",
        toScreenX(6),
        nil,
        imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    )
    binds.list = binds.get()
    blacklist.players = blacklist.get()
    blacklist.sortNicknames()

    imgui.Process = true
    chat.initQueue()
    player.connected = true

    lua_thread.create(binds.pressProcessingThread)
    lua_thread.create(chat.checkQueueThread)
    lua_thread.create(chat.disableFrozenMessagesProcessingThread)
    lua_thread.create(vehicle.refreshInfoThread)
    lua_thread.create(orders.deleteOrdersThread)
    lua_thread.create(updateTextdrawInfoThread)

    sampRegisterChatCommand(
        "taximate",
        function()
            imgui.showSettings.v = not imgui.showSettings.v
        end
    )
    sampRegisterChatCommand(
        "tm",
        function()
            imgui.showSettings.v = not imgui.showSettings.v
        end
    )
    sampRegisterChatCommand(
        "tmup",
        function()
            checkUpdates(false)
            update()
        end
    )
    sampRegisterChatCommand("tmblacklist", blacklist.command)
    sampRegisterChatCommand("tmbl", blacklist.command)

    if ini.settings.checkUpdates then
        lua_thread.create(checkUpdates)
    end

    if doesFileExist(getGameDirectory() .. "/map.asi") and doesFileExist(getGameDirectory() .. "/map.ini") then
        local fastMap = inicfg.load(_, getGameDirectory() .. "/map.ini")
        fastMapKey = fastMap.MAP.key
        fastMap = nil
    end

    while true do
        wait(0)

        imgui.ShowCursor = false

        if player.onWork then
            local result, orderNickname, orderDistance, orderClock = orders.get()
            if result then
                orders.handle(orderNickname, orderDistance, orderClock)
            end

            orders.autoAccept = table.isEmpty(vehicle.passengersList) and not orders.currentOrder

            orders.refreshCurrentOrder()

            if ini.settings.ordersDistanceUpdate then
                orders.updateOrdersDistance()
            end

            if isKeysPressed(ini.settings.key3, ini.settings.key3add, false) and ini.settings.hotKeys then
                player.onWork = false
                if ini.settings.autoClist then
                    chat.addMessageToQueue("/clist 0", true, true)
                end
                if orders.currentOrder then
                    orders.startOrderCanceling()
                end
            end

            if isKeyJustPressed(vkeys.VK_2) then
                if vehicle.name then
                    chat.antifloodClock = os.clock()
                end
            end

            if not orders.currentOrder then
                if orders.lastCorrectOrderNickname then
                    if isKeysPressed(ini.settings.key2, ini.settings.key2add, false) and ini.settings.hotKeys then
                        orders.accept(orders.lastCorrectOrderNickname, orders.lastCorrectOrderClock)
                    end
                end
            else
                if isKeysPressed(ini.settings.key2, ini.settings.key2add, false) and ini.settings.hotKeys then
                    orders.startOrderCanceling()
                end
            end
        elseif orders.currentOrder then
            if os.clock() - orders.lastOrderCanceling > 2 then
                orders.startOrderCanceling()
                orders.lastOrderCanceling = os.clock()
            end
        else
            orders.autoAccept = false
            if isKeysPressed(ini.settings.key3, ini.settings.key3add, false) and ini.settings.hotKeys then
                player.onWork = true
                if ini.settings.autoClist and ini.settings.workClist ~= 0 then
                    chat.addMessageToQueue("/clist " .. ini.settings.workClist, true, true)
                end
            end
        end

        if ini.settings.markers and vehicle.name then
            vehicle.drawMarkers()
        else
            vehicle.clearMarkers()
        end

        if ini.settings.cruiseControl then
            vehicle.cruiseControl()
        else
            vehicle.cruiseControlEnabled = false
        end
    end
end

chat = {
    queue = {},
    queueSize = 10,
    antifloodClock = os.clock(),
    lastMessage = "",
    antifloodDelay = 0.6,
    dialogClock = os.clock(),
    hiddenMessages = {
        ["/service"] = {bool = false, dialog = true, clock = os.clock()},
        ["/paycheck"] = {bool = false, dialog = false, clock = os.clock()},
        ["/clist"] = {bool = false, dialog = false, clock = os.clock()},
        ["/jskill"] = {bool = false, dialog = true, clock = os.clock()},
        ["/gps"] = {bool = false, dialog = true, clock = os.clock()}
    }
}

function chat.sendMessage(...)
    local message = ""
    local pack = table.pack(...)
    for i = 1, pack.n do
        message = message .. tostring(pack[i]) .. " "
    end
    sampAddChatMessage(
        u8:decode("\
				{00CED1}[Taximate v" .. thisScript().version .. "]{FFFFFF} " .. message),
        0xFFFFFF
    )
end

function chat.updateAntifloodClock()
    chat.antifloodClock = os.clock()
    if string.sub(chat.lastMessage, 1, 5) == "/sms " or string.sub(chat.lastMessage, 1, 3) == "/t " then
        chat.antifloodClock = chat.antifloodClock + 0.5
    end
end

function chat.disableFrozenMessagesProcessingThread()
    while true do
        wait(1000)
        for key, value in pairs(chat.hiddenMessages) do
            if os.clock() - value.clock > 5 and value.bool then
                value.bool = false
            end
        end
        if os.clock() - orders.lastAcceptedOrderClock > 5 and orders.acceptedNickname ~= nil then
            orders.acceptedNickname = nil
        end
    end
end

function chat.checkQueueThread()
    while true do
        wait(0)
        for messageIndex = 1, chat.queueSize do
            local message = chat.queue[messageIndex]
            if message.message ~= "" then
                if string.sub(chat.lastMessage, 1, 1) ~= "/" and string.sub(message.message, 1, 1) ~= "/" then
                    chat.antifloodDelay = chat.antifloodDelay + 0.5
                end
                if os.clock() - chat.antifloodClock > chat.antifloodDelay then
                    local sendMessage = true

                    local command = string.match(message.message, "^(/[^ ]*).*")

                    if message.hideResult then
                        if chat.hiddenMessages[command] then
                            if chat.hiddenMessages[command].bool then
                                chat.hiddenMessages[command].bool = false
                                sendMessage = false
                            else
                                chat.hiddenMessages[command].bool =
                                    (not sampIsDialogActive() or not chat.hiddenMessages[command].dialog) and
                                    chat.dialogClock < os.clock()
                                chat.hiddenMessages[command].clock = os.clock()
                                sendMessage = chat.hiddenMessages[command].bool
                            end
                        end
                    end

                    if sendMessage then
                        if message.message == "/en" then
                            sendMessage = vehicle.maxPassengers and not isCarEngineOn(vehicle.handle)
                        elseif message.message:find("/service ac taxi") then
                            sendMessage = not orders.currentOrder
                        end
                    end

                    if sendMessage then
                        chat.lastMessage = u8:decode(message.message)
                        sampSendChat(u8:decode(message.message))
                    end

                    message.hideResult = false
                    message.message = ""
                end
                chat.antifloodDelay = 0.6
            end
        end
    end
end

function chat.subSMSText(prefix, text)
    if text:find("{zone}") then
        local posX, posY = getCharCoordinates(PLAYER_PED)
        text = text:gsub("{zone}", getZone(posX, posY))
    end
    if orders.currentOrder then
        text = text:gsub("{distance}", metersToString(orders.currentOrder.currentDistance, false))
    else
        text = text:gsub("{distance}", "123 м")
    end
    if vehicle.name then
        text = text:gsub("{carname}", vehicle.name)
    else
        text = text:gsub("{carname}", "Sentinel")
    end
    if prefix ~= "" then
        prefix = prefix .. " "
    end
    return prefix .. text
end

function chat.sendNotification(order)
    if ini.settings.sendSMS then
        if not order.arrived and order.showMark then
            if order.currentDistance < 30 and ini.settings.SMSArrival ~= "" then
                chat.addMessageToQueue(
                    string.format(
                        "/service chat %s", chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSArrival)
                    )
                )
                order.arrived = true
            elseif order.SMSClock < os.clock() and order.updateDistance and ini.settings.SMSText ~= "" then
                chat.addMessageToQueue(
                    string.format("/service chat %s", chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSText))
                )
                if
                    order.firstSMS and vehicle.maxPassengers == 1 and ini.settings.seatsNotify and
                        ini.settings.SMSSeats ~= ""
                 then
                    chat.addMessageToQueue(
                        string.format(
                            "/service chat %s", chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSSeats)
                        )
                    )
                    order.firstSMS = false
                end
                order.SMSClock = os.clock() + ini.settings.SMSTimer
            end
        end
    end
end

function chat.handleInputMessage(message)
    lua_thread.create(
        function()
            if string.find(message, MESSAGES.newOrder) then
                local time = os.clock()
                local nickname, id, distance = string.match(message, MESSAGES.newOrderFormat)
                distance = stringToMeters(distance)
                orders.add(nickname, id, distance, time)
            elseif string.find(message, MESSAGES.orderCanceled) then
                local nickname = string.match(message, MESSAGES.orderCanceledFormat)
                if orders.currentOrder then
                    if orders.currentOrder.nickname == nickname then
                        orders.cancelCurrentOrder(false)
                    end
                end
            elseif string.find(message, MESSAGES.orderCanceledByTaxi) then
                orders.cancelCurrentOrder(true)
            elseif string.find(message, MESSAGES.orderCanceledByQuit) then
                local nickname = string.match(message, MESSAGES.orderCanceledByQuit)
                if orders.currentOrder then
                    if orders.currentOrder.nickname == nickname then
                        orders.cancelCurrentOrder(false)
                    end
                end
            elseif string.find(message, MESSAGES.orderAccepted) then
                local driverNickname, passengerNickname = string.match(message, MESSAGES.orderAcceptedFormat)
                if driverNickname == player.nickname and player.onWork then
                    if vehicle.maxPassengers and ini.settings.startEngine then
                        if not isCarEngineOn(vehicle.handle) then
                            chat.addMessageToQueue("/en")
                        end
                    end
                    if orders.currentOrder then
                        if orders.currentOrder.nickname ~= passengerNickname then
                            if ini.settings.notifications and ini.settings.sounds then
                                sounds.play("new_order")
                            end
                            if ini.settings.notifications then
                                imgui.addNotification(
                                    string.format(
                                        FORMAT_NOTIFICATIONS.orderAccepted,
                                        orders.list[passengerNickname].nickname,
                                        orders.list[passengerNickname].id,
                                        metersToString(orders.list[passengerNickname].distance)
                                    ),
                                    10
                                )
                            end
                        end
                    elseif orders.list[passengerNickname] then
                        if ini.settings.notifications and ini.settings.sounds then
                            sounds.play("new_order")
                        end
                        if ini.settings.notifications then
                            imgui.addNotification(
                                string.format(
                                    FORMAT_NOTIFICATIONS.orderAccepted,
                                    orders.list[passengerNickname].nickname,
                                    orders.list[passengerNickname].id,
                                    metersToString(orders.list[passengerNickname].distance)
                                ),
                                10
                            )
                        end
                        orders.currentOrder = orders.list[passengerNickname]
                        orders.currentOrder.SMSClock = os.clock()
                    end
                end
                orders.delete(passengerNickname)
            elseif string.find(message, MESSAGES.GPS) and player.onWork and not orders.currentOrder then
                local text = "Метка на карте обновлена"
                local result, x, y = getGPSMarkCoords3d()
                if result then
                    text = text .. "\nРайон: {4296f9}" .. getZone(x, y)
                    if ini.settings.notifications and ini.settings.sounds then
                        sounds.play("correct_order")
                    end
                    if ini.settings.notifications then
                        imgui.addNotification(text, 5)
                    end
                end
            elseif
                string.find(message, MESSAGES.finishWork) and player.onWork and ini.settings.finishWork and
                    not orders.currentOrder
             then
                player.onWork = false
                if ini.settings.autoClist and not chat.hiddenMessages["/clist"].bool then
                    chat.addMessageToQueue("/clist 0", true, true)
                end
            elseif string.find(message, MESSAGES.passengerOut) or string.find(message, MESSAGES.passengerOutFree) then
                player.refresh()
            elseif string.find(message, MESSAGES.pay) then
                local sum, nickname = string.match(message, MESSAGES.payFormat)
                if table.contains(nickname, vehicle.lastPassengersList) then
                    player.tips = player.tips + sum
                end
            elseif string.find(message, MESSAGES.payDay) then
                player.tips = 0
                player.refresh()
            elseif string.find(message, MESSAGES.antiFlood) then
                chat.updateAntifloodClock()
                for qMessage in pairs(chat.hiddenMessages) do
                    chat.hiddenMessages[qMessage].bool = false
                end
                orders.acceptedNickname = nil
            elseif string.find(message, MESSAGES.repair) and ini.settings.autoRepair then
                if isCharInAnyCar(PLAYER_PED) then
                    local vehicleHandle = storeCarCharIsInNoSave(PLAYER_PED)

                    if getCarHealth(vehicleHandle) ~= 1000 then
                        chat.addMessageToQueue("/ac repair")
                    else
                        chat.addMessageToQueue("/cancel repair")
                    end
                end
            elseif string.find(message, MESSAGES.refill) and ini.settings.autoRefill and vehicle.fuel then
                local cost = tonumber(string.match(message, MESSAGES.refillFormat))
                if cost <= ini.settings.maxAutoRefillCost and vehicle.fuel <= ini.settings.autoRefillGauge then
                    chat.addMessageToQueue("/ac refill")
                else
                    chat.addMessageToQueue("/cancel refill")
                end
            end
        end
    )
end

function chat.initQueue()
    chat.queue[1] = {message = "/jskill", hideResult = true}
    chat.queue[2] = {message = "/paycheck", hideResult = true}
    for messageIndex = 3, chat.queueSize do
        chat.queue[messageIndex] = {message = "", hideResult = false}
    end
end

function chat.addMessageToQueue(string, nonRepeat, hideResult)
    local isRepeat = false
    local nonRepeat = nonRepeat or false
    local hideResult = hideResult or false

    if nonRepeat then
        for messageIndex = 1, chat.queueSize do
            if string == chat.queue[messageIndex].message then
                isRepeat = true
            end
        end
    end

    if not isRepeat then
        for messageIndex = 1, chat.queueSize - 1 do
            chat.queue[messageIndex].message = chat.queue[messageIndex + 1].message
            chat.queue[messageIndex].hideResult = chat.queue[messageIndex + 1].hideResult
        end
        chat.queue[chat.queueSize].message = string
        chat.queue[chat.queueSize].hideResult = hideResult
    end
end

orders = {
    list = {},
    canceled = {},
    GPSMark = nil,
    autoAccept = false,
    lastAcceptedOrderClock = os.clock(),
    lastCorrectOrderNickname = nil,
    lastCorrectOrderClock = os.clock(),
    acceptedNickname = nil,
    updateOrdersDistanceClock = os.clock(),
    currentOrder = nil,
    currentOrderBlip = nil,
    currentOrderCheckpoint = nil,
    lastOrderCanceling = os.clock()
}

function orders.startOrderCanceling()
    chat.addMessageToQueue(
        string.format("/service chat %s", chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSCancel))
    )
    chat.addMessageToQueue("/service cancel taxi", true, true)
end

function orders.cancelCurrentOrder(canceledByTaxi)
    if ini.settings.notifications and ini.settings.sounds then
        sounds.play("correct_order")
    end
    if ini.settings.notifications then
        imgui.addNotification("Вызов отменён\nМетка на карте удалена", 5)
    end
    if canceledByTaxi then
        orders.canceled[orders.currentOrder.nickname] = os.clock()
        orders.removeGPSMark()
    end
    orders.currentOrder = nil
end

function orders.removeGPSMark()
    if orders.currentOrderBlip then
        deleteCheckpoint(orders.currentOrderCheckpoint)
        removeBlip(orders.currentOrderBlip)
        orders.currentOrderBlip = nil
        orders.currentOrderCheckpoint = nil
    end
    chat.addMessageToQueue("/gps", true, true)
end

function orders.calculate2dCoords(circle1, circle2, circle3)
    local dX = circle2.x - circle1.x
    local dY = circle2.y - circle1.y

    local d = math.sqrt((dY * dY) + (dX * dX))

    if d > (circle1.radius + circle2.radius) then
        return false
    end

    if d < math.abs(circle1.radius - circle2.radius) then
        return false
    end

    local a = ((circle1.radius * circle1.radius) - (circle2.radius * circle2.radius) + (d * d)) / (2.0 * d)

    local point2X = circle1.x + (dX * a / d)
    local point2Y = circle1.y + (dY * a / d)

    local h = math.sqrt((circle1.radius * circle1.radius) - (a * a))

    local rX = -dY * (h / d)
    local rY = dX * (h / d)

    local intersectionPoint1X = point2X + rX
    local intersectionPoint2X = point2X - rX
    local intersectionPoint1Y = point2Y + rY
    local intersectionPoint2Y = point2Y - rY

    dX = intersectionPoint1X - circle3.x
    dY = intersectionPoint1Y - circle3.y

    local d1 = math.sqrt((dY * dY) + (dX * dX))

    dX = intersectionPoint2X - circle3.x
    dY = intersectionPoint2Y - circle3.y

    local d2 = math.sqrt((dY * dY) + (dX * dX))

    if math.abs(d1 - circle3.radius) < math.abs(d2 - circle3.radius) then
        return true, intersectionPoint1X, intersectionPoint1Y
    else
        return true, intersectionPoint2X, intersectionPoint2Y
    end
end

function orders.updateOrdersDistance()
    if vehicle.name then
        if orders.updateOrdersDistanceClock < os.clock() then
            if not orders.currentOrder then
                if not chat.hiddenMessages["/service"].bool then
                    chat.addMessageToQueue("/service", true, true)
                    orders.updateOrdersDistanceClock = os.clock() + ini.settings.ordersDistanceUpdateTimer
                end
            end
        end
    end
end

function orders.add(nickname, id, distance, time)
    local posX, posY = getCharCoordinates(PLAYER_PED)
    local level = sampGetPlayerScore(id)
    orders.list[nickname] = {
        nickname = nickname,
        id = id,
        distance = distance,
        pos = {x = nil, y = nil, z = nil},
        currentDistance = distance,
        time = time,
        correct = false,
        showMark = false,
        SMSClock = os.clock() - ini.settings.SMSTimer,
        firstSMS = true,
        arrived = false,
        updateDistance = true,
        direction = 0,
        tempCircles = {{x = posX, y = posY, radius = distance}, nil, nil},
        zone = "Неизвестно",
        level = level
    }
end

function orders.refreshCurrentOrder()
    if orders.currentOrder then
        if sampIsPlayerConnected(orders.currentOrder.id) then
            if vehicle.maxPassengers then
                chat.sendNotification(orders.currentOrder)
                local charInStream, charHandle = sampGetCharHandleBySampPlayerId(orders.currentOrder.id)
                if charInStream and ini.settings.updateOrderMark then
                    orders.currentOrder.pos.x, orders.currentOrder.pos.y, orders.currentOrder.pos.z =
                        getCharCoordinates(charHandle)
                    orders.currentOrder.zone = getZone(orders.currentOrder.pos.x, orders.currentOrder.pos.y)
                    if orders.currentOrder.showMark then
                        if not orders.currentOrderBlip then
                            orders.currentOrderBlip =
                                addBlipForCoord(
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z
                            )
                            changeBlipColour(orders.currentOrderBlip, 0xBB0000FF)
                            orders.currentOrderCheckpoint =
                                createCheckpoint(
                                1,
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z,
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z,
                                2.99
                            )
                            chat.addMessageToQueue("/gps", true, true)
                            if ini.settings.notifications then
                                imgui.addNotification("Клиент поблизости\nМетка на карте обновлена", 5)
                            end
                            if ini.settings.notifications and ini.settings.sounds then
                                sounds.play("correct_order")
                            end
                        else
                            removeBlip(orders.currentOrderBlip)
                            orders.currentOrderBlip =
                                addBlipForCoord(
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z
                            )
                            changeBlipColour(orders.currentOrderBlip, 0xBB0000FF)
                            setCheckpointCoords(
                                orders.currentOrderCheckpoint,
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z
                            )
                        end

                        if orders.currentOrderBlip then
                            local distance =
                                getDistanceToCoords3d(
                                orders.currentOrder.pos.x,
                                orders.currentOrder.pos.y,
                                orders.currentOrder.pos.z
                            )
                            if distance <= 3 then
                                removeBlip(orders.currentOrderBlip)
                                deleteCheckpoint(orders.currentOrderCheckpoint)
                                orders.currentOrderBlip = nil
                                orders.currentOrderCheckpoint = nil
                                orders.currentOrder.showMark = false
                            end
                        end
                    end
                end

                if orders.currentOrder.pos.x then
                    orders.currentOrder.currentDistance =
                        getDistanceToCoords3d(
                        orders.currentOrder.pos.x,
                        orders.currentOrder.pos.y,
                        orders.currentOrder.pos.z
                    )
                    orders.currentOrder.updateDistance = true
                end

                if vehicle.isPassengerIn(vehicle.handle, orders.currentOrder.nickname) then
                    orders.currentOrder = nil
                end
            end
        else
            if ini.settings.notifications then
                imgui.addNotification("Клиент оффлайн\nВызов отменён", 5)
            end
            if ini.settings.notifications and ini.settings.sounds then
                sounds.play("correct_order")
            end
            orders.currentOrder = nil
            orders.removeGPSMark()
        end
    else
        removeBlip(orders.currentOrderBlip)
        deleteCheckpoint(orders.currentOrderCheckpoint)
        orders.currentOrderBlip = nil
        orders.currentOrderCheckpoint = nil
    end
end

function orders.delete(nickname)
    orders.list[nickname] = nil
end

function orders.accept(nickname, orderClock)
    if orders.canceled[nickname] and ini.settings.ignoreCanceledOrder then
        return
    end
    if orders.list[nickname] then
        if orderClock then
            if orders.lastAcceptedOrderClock ~= orderClock then
                if orders.acceptedNickname == nil then
                    orders.lastAcceptedOrderClock = orders.list[nickname].time
                    orders.acceptedNickname = nickname
                    chat.addMessageToQueue("/service ac taxi " .. orders.list[nickname].id)
                end
            end
        end
    end
end

function orders.deleteOrdersThread()
    while true do
        wait(1000)
        for nickname, order in pairs(orders.list) do
            if os.clock() - order.time > 600 or not sampIsPlayerConnected(order.id) then
                orders.delete(nickname)
            end
        end
        for nickname, clock in pairs(orders.canceled) do
            if os.clock() - clock > ini.settings.canceledOrderDelay then
                orders.canceled[nickname] = nil
            end
        end
    end
end

function orders.get()
    for keyIndex, key in ipairs(table.getTableKeysSortedByValue(orders.list, "time", false)) do
        if orders.list[key] then
            return true, key, orders.list[key].distance, orders.list[key].time
        end
    end
    return false, nil, nil, nil
end

function orders.handle(orderNickname, orderDistance, orderClock)
    if not orders.currentOrder then
        local level = orders.list[orderNickname].level

        if not table.contains(orderNickname, vehicle.lastPassengersList) then
            if table.isEmpty(vehicle.passengersList) then
                local acceptByLevel =
                    level == 0 or (level >= 1 and level <= 2 and ini.settings.autoAccept1_2) or
                    (level >= 3 and level <= 5 and ini.settings.autoAccept3_5) or
                    (level >= 6 and ini.settings.autoAccept6)
                local ignoreByBlacklist = ini.settings.blacklistIgnore and blacklist.check(orderNickname)
                if orders.autoAccept and acceptByLevel and not ignoreByBlacklist then
                    if orderDistance <= ini.settings.maxDistanceToAcceptOrder and os.clock() - 60 < orderClock then
                        orders.accept(orderNickname, orderClock)
                    end
                end
            else
                if orderDistance <= ini.settings.maxDistanceToGetOrder and os.clock() - 60 < orderClock then
                    if not orders.list[orderNickname].correct then
                        orders.list[orderNickname].correct = true
                        orders.lastCorrectOrderNickname = orderNickname
                        orders.lastCorrectOrderClock = os.clock()
                        lua_thread.create(
                            function()
                                wait(500)
                                if orders.list[orderNickname] then
                                    if ini.settings.notifications and ini.settings.sounds then
                                        sounds.play("correct_order")
                                    end
                                    if ini.settings.notifications then
                                        imgui.addNotificationWithButton(
                                            string.format(
                                                FORMAT_NOTIFICATIONS.newOrder,
                                                orderNickname,
                                                orders.list[orderNickname].id,
                                                orders.list[orderNickname].level,
                                                orderDistance,
                                                orders.list[orderNickname].zone
                                            ),
                                            15,
                                            orderNickname
                                        )
                                    end
                                end
                            end
                        )
                    end
                end
            end
        end
    end
end

vehicle = {
    lastPassengersList = {},
    lastPassengersListSize = 3,
    passengersList = {},
    maxPassengers = nil,
    name = nil,
    handle = nil,
    markers = {},
    cruiseControlEnabled = false,
    gasPressed = false
}

function vehicle.refreshInfoThread()
    while true do
        wait(0)
        vehicle.name, vehicle.handle, vehicle.maxPassengers = vehicle.getInfo()
        vehicle.refreshPassengersList()
    end
end

function vehicle.addPassenger(passengerNickname)
    local isPassengerInVehicle = false

    for passengerIndex = 1, vehicle.lastPassengersListSize do
        if passengerNickname == vehicle.lastPassengersList[passengerIndex] then
            isPassengerInVehicle = true
            break
        end
    end

    if not isPassengerInVehicle then
        for passengerindex = vehicle.lastPassengersListSize, 1, -1 do
            vehicle.lastPassengersList[passengerindex] = vehicle.lastPassengersList[passengerindex - 1]
        end
        vehicle.lastPassengersList[1] = passengerNickname
        if ini.settings.notifications and ini.settings.sounds then
            sounds.play("new_passenger")
        end
    end
end

function updateTextdrawInfoThread()
    while true do
        wait(0)
        
        if os.clock() - player.textdrawUpdateClock > 1 then

            for textdrawId = 0, 2100 do
                if sampTextdrawIsExists(textdrawId) then

                    local textdrawString = sampTextdrawGetString(textdrawId)
                    
                    -- Обновление количества топлива
                    if ini.settings.autoRefill then
                        vehicle.fuel = nil
                        if textdrawString == "Fuel" and sampTextdrawIsExists(textdrawId - 1) then
                            vehicle.fuel = tonumber(sampTextdrawGetString(textdrawId - 1))
                        elseif string.find(textdrawString, MESSAGES.fuelClassic) then
                            vehicle.fuel = tonumber(string.match(textdrawString, MESSAGES.fuelClassicFormat))
                        end
                    end

                    -- Обновление активного вызова 
                    if vehicle.maxPassengers then
                        if string.find(textdrawString, MESSAGES.currentOrderTextdraw) then
                            local nickname, distance = string.match(textdrawString, MESSAGES.currentOrderTextdraw)
                            distance = tonumber(distance)
                            id = getPlayerIdByNickname(nickname)
                            if type(id) == "number" then
                                local accept = true
                                if orders.currentOrder and orders.currentOrder.nickname == nickname then
                                    accept = false
                                end
                                if accept then
                                    orders.add(nickname, id, distance, os.clock())
                                    orders.currentOrder = orders.list[nickname]
                                    orders.list[nickname] = nil
                                    player.onWork = true
                                end
                            end
                        end
                    end
                        
                end
            end

            player.textdrawUpdateClock = os.clock()

        end   
    end
end

function vehicle.refreshPassengersList()
    if vehicle.maxPassengers then
        for passengerIndex = 0, vehicle.maxPassengers - 1 do
            vehicle.passengersList[passengerIndex] = nil
        end

        for seatIndex = 0, vehicle.maxPassengers - 1 do
            if not isCarPassengerSeatFree(vehicle.handle, seatIndex) then
                local passengerHandle = getCharInCarPassengerSeat(vehicle.handle, seatIndex)
                local result, passengerID = sampGetPlayerIdByCharHandle(passengerHandle)
                if result then
                    local passengerNickname = sampGetPlayerNickname(passengerID)
                    vehicle.passengersList[seatIndex] = {
                        nickname = passengerNickname,
                        id = passengerID
                    }
                    vehicle.addPassenger(passengerNickname)
                end
            end
        end
    end
end

function vehicle.getInfo()
    for vehicleName, vehicleModelID in pairs(VEHICLE_MODEL_IDS) do
        if isCharInModel(PLAYER_PED, vehicleModelID) then
            local vehicleHandle = storeCarCharIsInNoSave(PLAYER_PED)
            if PLAYER_PED == getDriverOfCar(vehicleHandle) then
                if vehicle.isTaxi(vehicleHandle) then
                    local maxPassengers = vehicle.getMaxPassengers()
                    return vehicleName, vehicleHandle, maxPassengers
                end
            end
        end
    end

    return nil, nil, nil
end

function vehicle.isTaxi(vehicleHandle)
    local result, id = sampGetVehicleIdByCarHandle(vehicleHandle)
    if result then
        for textId = 0, 2048 do
            if sampIs3dTextDefined(textId) then
                local string, _, _, _, _, _, _, _, vehicleId = sampGet3dTextInfoById(textId)
                if string.find(string, MESSAGES.taxiChecker) and vehicleId == id then
                    return true
                end
            end
        end
    end

    return false
end

function vehicle.isPassengerIn(vehicleHandle, nickname)
    for seatIndex = 0, vehicle.maxPassengers - 1 do
        if not isCarPassengerSeatFree(vehicleHandle, seatIndex) then
            local passengerHandle = getCharInCarPassengerSeat(vehicleHandle, seatIndex)
            local result, passengerID = sampGetPlayerIdByCharHandle(passengerHandle)
            if result then
                local passengerNickname = sampGetPlayerNickname(passengerID)
                if nickname == passengerNickname then
                    return true
                end
            end
        end
    end
    return false
end

function vehicle.getMaxPassengers()
    if vehicle.name == "Buffalo" then
        return 1
    elseif vehicle.name then
        return 3
    else
        return nil
    end
end

function vehicle.drawMarkers()
    for id = 0, 999 do
        if sampIsPlayerConnected(id) then
            local charInStream, charHandle = sampGetCharHandleBySampPlayerId(id)
            if charInStream then
                if not vehicle.markers[id] then
                    if isCharInAnyCar(charHandle) and sampGetPlayerColor(id) == 16777215 then
                        vehicle.markers[id] = addBlipForChar(charHandle)
                        changeBlipDisplay(vehicle.markers[id], 2)
                        changeBlipColour(vehicle.markers[id], 0xFFFFFF25)
                    end
                elseif not isCharInAnyCar(charHandle) or sampGetPlayerColor(id) ~= 16777215 then
                    removeBlip(vehicle.markers[id])
                    vehicle.markers[id] = nil
                end
            else
                if vehicle.markers[id] then
                    removeBlip(vehicle.markers[id])
                    vehicle.markers[id] = nil
                end
            end
        end
    end
end

function vehicle.clearMarkers()
    for id, marker in pairs(vehicle.markers) do
        removeBlip(marker)
        vehicle.markers[id] = nil
    end
end

function vehicle.cruiseControl()
    if not isCharInAnyCar(PLAYER_PED) then
        return
    end
    local car = storeCarCharIsInNoSave(PLAYER_PED)
    if vehicle.cruiseControlEnabled then
        if not isCarEngineOn(car) or not isCharInAnyCar(PLAYER_PED) then
            vehicle.cruiseControlEnabled = false
            if ini.settings.notifications then
                imgui.addNotification(FORMAT_NOTIFICATIONS.cruiseControlDisabled, 2, -8)
            end
            return
        end
    end
    if not sampIsChatInputActive() and not sampIsDialogActive() then
        if vehicle.gasPressed and not isKeyDown(87) then
            vehicle.gasPressed = false
        end
        if isCarEngineOn(car) and isCharInAnyCar(PLAYER_PED) and PLAYER_PED == getDriverOfCar(car) then
            if isKeyJustPressed(ini.settings.key4) then
                vehicle.cruiseControlEnabled = not vehicle.cruiseControlEnabled
                if ini.settings.notifications then
                    local text = FORMAT_NOTIFICATIONS.cruiseControlEnabled
                    if not vehicle.cruiseControlEnabled then
                        text = FORMAT_NOTIFICATIONS.cruiseControlDisabled
                    end
                    imgui.addNotification(text, 2, -8)
                end
                vehicle.gasPressed = true
            elseif
                vehicle.cruiseControlEnabled and not isKeyJustPressed(ini.settings.key4) and
                    (isKeyDown(87) or isKeyDown(83)) and
                    not vehicle.gasPressed
             then
                vehicle.cruiseControlEnabled = false
                if ini.settings.notifications then
                    imgui.addNotification(FORMAT_NOTIFICATIONS.cruiseControlDisabled, 2, -8)
                end
            end
        end
    end
    if vehicle.cruiseControlEnabled then
        setGameKeyState(16, 255)
    end
end

player = {
    id = nil,
    nickname = nil,
    onWork = false,
    skill = 1,
    skillExp = 0,
    skillClients = 0,
    rank = 1,
    rankExp = 0,
    salary = 0,
    salaryLimit = 0,
    tips = 0,
    connected = false,
    textdrawUpdateClock = os.clock()
}

function player.refresh()
    if not chat.hiddenMessages["/paycheck"].bool then
        chat.addMessageToQueue("/paycheck", true, true)
    end
    if not chat.hiddenMessages["/jskill"].bool then
        chat.addMessageToQueue("/jskill", true, true)
    end
end

ini = {
    settings = {
        checkUpdates = true,
        showHUD = true,
        showBindMenu = true,
        sounds = true,
        notifications = true,
        sendSMS = true,
        sendSMSCancel = true,
        updateOrderMark = true,
        acceptRepeatOrder = true,
        autoClist = true,
        workClist = 25,
        hotKeys = true,
        SMSTimer = 30,
        maxDistanceToAcceptOrder = 1400,
        maxDistanceToGetOrder = 1000,
        fastMapCompatibility = true,
        key1 = 88,
        key1add = 0,
        key2 = 16,
        key2add = 88,
        key3 = 88,
        key3add = 82,
        key4 = 67,
        binderPosX = 36,
        binderPosY = 103,
        hudPosX = 498,
        hudPosY = 310,
        markers = false,
        ordersDistanceUpdate = true,
        ordersDistanceUpdateTimer = 5,
        soundVolume = 50,
        dispatcherMessages = true,
        finishWork = true,
        SMSPrefix = "",
        SMSText = "Жёлтый {carname} в пути. Дистанция: {distance}",
        SMSArrival = "Жёлтый {carname} прибыл на место вызова",
        SMSSeats = "Такси имеет только одно пассажирское место",
        SMSCancel = "Вызов отменён, закажите новое такси",
        ignoreCanceledOrder = true,
        canceledOrderDelay = 120,
        cruiseControl = true,
        seatsNotify = true,
        autoRepair = true,
        autoRefill = true,
        maxAutoRefillCost = 3000,
        autoRefillGauge = 50,
        autoAccept1_2 = true,
        autoAccept3_5 = true,
        autoAccept6 = true,
        blacklistIgnore = true,
        blacklistHide = true,
        startEngine = true
    }
}

local defaults = {
    maxDistanceToAcceptOrder = 1400,
    maxDistanceToGetOrder = 1000,
    SMSTimer = 30,
    ordersDistanceUpdateTimer = 5,
    soundVolume = 50,
    canceledOrderDelay = 120,
    maxAutoRefillCost = 3000,
    autoRefillGauge = 50
}

sounds = {list = {}}

function sounds.loadSound(soundName)
    sounds.list[soundName] = loadAudioStream(getWorkingDirectory() .. "/rsc/" .. soundName .. ".mp3")
end

function sounds.play(soundName)
    if sounds.list[soundName] then
        setAudioStreamVolume(sounds.list[soundName], ini.settings.soundVolume / 100)
        setAudioStreamState(sounds.list[soundName], moonloader.audiostream_state.PLAY)
    end
end

binds = {
    list = {},
    defaults = {
        binds = {
            {text = "/service", cmd = "", key = 0, addKey = 0},
            {text = "Привет", cmd = "", key = 0, addKey = 0},
            {text = "Куда едем?", cmd = "", key = 0, addKey = 0},
            {text = "Спасибо", cmd = "", key = 0, addKey = 0},
            {text = "Хорошо", cmd = "", key = 0, addKey = 0},
            {text = "Удачи", cmd = "", key = 0, addKey = 0},
            {text = "Да", cmd = "", key = 0, addKey = 0},
            {text = "Нет", cmd = "", key = 0, addKey = 0},
            {text = ")", cmd = "", key = 0, addKey = 0},
            {text = "Почини", cmd = "", key = 0, addKey = 0},
            {text = "Заправь", cmd = "", key = 0, addKey = 0},
            {text = "/rkt", cmd = "", key = 0, addKey = 0},
            {
                text = "/b Скрипт для таксистов - Taximate",
                cmd = "",
                key = 0,
                addKey = 0
            }
        },
        actions = {
            {
                text = "Выкинуть из автомобиля",
                cmd = "/eject {id}",
                key = 0,
                addKey = 0
            }
        },
        sms = {
            {
                text = "Жёлтый {carname} в пути. Дистанция: {distance}",
                cmd = "",
                key = 0,
                addKey = 0
            },
            {
                text = "Жёлтый {carname} прибыл на место вызова",
                cmd = "",
                key = 0,
                addKey = 0
            },
            {
                text = "Вызов отменён, закажите новое такси",
                cmd = "",
                key = 0,
                addKey = 0
            },
            {text = "Скоро буду", cmd = "", key = 0, addKey = 0},
            {text = "Да", cmd = "", key = 0, addKey = 0},
            {text = "Нет", cmd = "", key = 0, addKey = 0}
        }
    }
}

function binds.chooseEdit(key, bindIndex)
    binds.list[key][bindIndex].edit = true
    for keyname in pairs(binds.list) do
        for _bindIndex, _bind in pairs(binds.list[keyname]) do
            if _bindIndex ~= bindIndex or keyname ~= key then
                _bind.edit = false
            end
        end
    end
end

function binds.get()
    local list = {}

    local bindsFile = io.open(getWorkingDirectory() .. "/config/Taximate/binds.json", "r")

    local json = nil

    if bindsFile then
        local content = bindsFile:read("*a")
        bindsFile:close()
        local jsonFromFile = decodeJson(content)
        local newjson = {
            binds = {},
            actions = binds.defaults.actions,
            sms = binds.defaults.sms
        }
        for key, value in pairs(jsonFromFile) do
            if type(key) == "string" and key == "binds" then
                json = jsonFromFile
                break
            else
                table.insert(
                    newjson.binds,
                    {
                        text = value.text,
                        cmd = "",
                        key = value.key,
                        addKey = value.addKey
                    }
                )
            end
        end
        if json == nil then
            json = newjson
        end
    else
        bindsFile = io.open(getWorkingDirectory() .. "/config/Taximate/binds.json", "w")
        local content = encodeJson(binds.defaults)
        bindsFile:write(content)
        bindsFile:close()
        json = binds.defaults
    end

    for keyname, bind in pairs(json) do
        list[keyname] = {}
        for index, value in pairs(bind) do
            local buffer = imgui.ImBuffer(128)
            local bufferCmd = imgui.ImBuffer(128)
            buffer.v = value.text or ""
            bufferCmd.v = value.cmd or ""
            table.insert(
                list[keyname],
                {
                    buffer = buffer,
                    bufferCmd = bufferCmd,
                    key = value.key or 0,
                    addKey = value.addKey or 0,
                    edit = false
                }
            )
        end
    end

    return list
end

function binds.delete(key, index)
    for i = index, #binds.list[key] + 1 do
        binds.list[key][i] = binds.list[key][i + 1]
    end
    binds.save()
end

function binds.isEdit(key)
    for bindIndex, bind in pairs(binds.list[key]) do
        if bind.edit then
            return true
        end
    end
    return false
end

function binds.save()
    local bindsFile = io.open(getWorkingDirectory() .. "/config/Taximate/binds.json", "w")
    local json = {}
    for keyname, bind in pairs(binds.list) do
        json[keyname] = {}
        for index, value in pairs(bind) do
            table.insert(
                json[keyname],
                {
                    text = value.buffer.v,
                    cmd = value.bufferCmd.v,
                    key = value.key,
                    addKey = value.addKey
                }
            )
        end
    end
    local content = encodeJson(json)
    bindsFile:write(content)
    bindsFile:close()
end

function binds.pressProcessingThread()
    while true do
        wait(0)
        for key, binds in pairs(binds.list) do
            for index, bind in ipairs(binds) do
                if
                    isKeysPressed(bind.key, bind.addKey, false) and not imgui.showInputWindow.v and
                        not sampIsDialogActive() and
                        not sampIsChatInputActive() and
                        not isPauseMenuActive() and
                        ini.settings.hotKeys
                 then
                    local text = bind.buffer.v
                    if key == "sms" then
                        if orders.currentOrder then
                            text =
                                string.format(
                                "/service chat %s", chat.subSMSText(ini.settings.SMSPrefix, bind.buffer.v)
                            )
                            chat.addMessageToQueue(text)
                        end
                    else
                        chat.addMessageToQueue(text)
                    end
                end
            end
        end
    end
end

blacklist = {}
blacklist.players = {}
blacklist.sortedNicknames = {}

function blacklist.get()
    local list = {}
    local blacklistFile = io.open(getWorkingDirectory() .. "/config/Taximate/blacklist.json", "r")
    if blacklistFile then
        local content = blacklistFile:read("*a")
        blacklistFile:close()
        local jsonFromFile = decodeJson(content)
        for nickname, record in pairs(jsonFromFile) do
            list[nickname] = {
                active = record.active,
                buffer = imgui.ImBuffer(25),
                edit = false,
                date = record.date
            }
            list[nickname].buffer.v = nickname
        end
    end

    return list
end

function blacklist.save()
    local blacklistFile = io.open(getWorkingDirectory() .. "/config/Taximate/blacklist.json", "w")
    local json = {}
    for nickname, record in pairs(blacklist.players) do
        json[nickname] = {
            active = record.active,
            date = record.date
        }
    end
    local content = encodeJson(json)
    blacklistFile:write(content)
    blacklistFile:close()
    blacklist.sortNicknames()
end

function blacklist.sortNicknames()
    blacklist.sortedNicknames = table.getTableKeysSortedByValue(blacklist.players, "date", false)
end

function blacklist.check(nickname)
    if blacklist.players[nickname] then
        if blacklist.players[nickname].active then
            return true
        end
    end

    for pattern, record in pairs(blacklist.players) do
        if (pattern:find("%?") or pattern:find("%*")) and record.active then
            pattern = "^" .. pattern .. "$"
            pattern = pattern:gsub("%?", "[%%w_]")
            pattern = pattern:gsub("%*", "[%%w_]%*")
            if nickname:lower():match(pattern:lower()) then
                return true
            end
        end
    end

    return false
end

blacklist.command = function(arg)
    local nickname = ""
    local error = false
    local id = tonumber(arg)
    if not arg:find("^[%w_%?%*]+$") and not id then
        error = true
    else
        local idstr = ""
        if id then
            if id >= 0 and id <= 999 and sampIsPlayerConnected(id) then
                nickname = sampGetPlayerNickname(id)
                idstr = "[" .. id .. "]"
            else
                error = true
            end
        else
            nickname = arg
        end
        if #nickname > 25 or #nickname < 1 then
            error = true
        end
        if blacklist.players[nickname] and not error then
            blacklist.players[nickname] = nil
            chat.sendMessage(string.format("{00CED1}%s%s{FFFFFF} удален из чёрного списка", nickname, idstr))
        elseif not error then
            blacklist.players[nickname] = {
                active = true,
                buffer = imgui.ImBuffer(25),
                edit = false,
                date = os.time(os.date("!*t"))
            }
            blacklist.players[nickname].buffer.v = nickname
            chat.sendMessage(string.format("{00CED1}%s%s{FFFFFF} добавлен в чёрный список", nickname, idstr))
        end
    end
    if error then
        chat.sendMessage("Введите: /tmbl [Nick_Name/id]")
    else
        blacklist.save()
    end
end

function sampev.onShowDialog(DdialogId, Dstyle, Dtitle, Dbutton1, Dbutton2, Dtext)
    if player.connected then
        if Dstyle == 0 and string.find(Dtext, "Таксист") then
            lua_thread.create(
                function()
                    local line = 0
                    for string in string.gmatch(Dtext, "[^\n]+") do
                        line = line + 1
                        if line == 5 then
                            player.skill, player.skillExp = string.match(string, MESSAGES.skill)
                            player.skillClients =
                                math.ceil(
                                (100 - player.skillExp) /
                                    (((9600 / 100 * (1.1 ^ (50 - player.skill))) * 100) / (5000 * (1.1 ^ player.skill)))
                            )
                        end
                        if line == 6 then
                            player.rank, player.rankExp = string.match(string, MESSAGES.rank)
                        end
                    end
                end
            )
            if chat.hiddenMessages["/jskill"].bool then
                chat.hiddenMessages["/jskill"].bool = false
                sampSendDialogResponse(DdialogId, 0)
                return false
            end
        elseif string.find(Dtitle, "GPS") then
            if chat.hiddenMessages["/gps"].bool then
                chat.hiddenMessages["/gps"].bool = false
                orders.GPSMark = nil
                sampSendDialogResponse(DdialogId, 0)
                return false
            else
                lua_thread.create(
                    function()
                        if orders.currentOrderBlip then
                            orders.currentOrder.showMark = false
                            removeBlip(orders.currentOrderBlip)
                            deleteCheckpoint(orders.currentOrderCheckpoint)
                            orders.currentOrderBlip = nil
                            orders.currentOrderCheckpoint = nil
                        end
                    end
                )
            end
        elseif string.find(Dtitle, "Вызовы") then
            lua_thread.create(
                function()
                    local ordersList = {}
                    for string in string.gmatch(Dtext, "[^\n]+") do
                        local nickname, id, time, distance = string.match(string, MESSAGES.order)
                        time = stringToSeconds(time)
                        distance = stringToMeters(distance)
                        if orders.list[nickname] then
                            if distance < orders.list[nickname].distance then
                                orders.list[nickname].direction = 1
                            elseif distance > orders.list[nickname].distance then
                                orders.list[nickname].direction = -1
                            end
                            orders.list[nickname].distance = distance
                            orders.list[nickname].time = os.clock() - time
                        else
                            orders.add(nickname, id, distance, os.clock() - time)
                        end
                        table.insert(ordersList, nickname)
                        local posX, posY = getCharCoordinates(PLAYER_PED)
                        if not orders.list[nickname].tempCircles[1] then
                            orders.list[nickname].tempCircles[1] = {
                                x = posX,
                                y = posY,
                                radius = distance
                            }
                        elseif not orders.list[nickname].tempCircles[2] then
                            if
                                math.abs(orders.list[nickname].tempCircles[1].x - posX) > 15 or
                                    math.abs(orders.list[nickname].tempCircles[1].y - posY) > 15
                             then
                                orders.list[nickname].tempCircles[2] = {
                                    x = posX,
                                    y = posY,
                                    radius = distance
                                }
                            end
                        elseif not orders.list[nickname].tempCircles[3] then
                            if
                                (math.abs(orders.list[nickname].tempCircles[1].x - posX) > 15 or
                                    math.abs(orders.list[nickname].tempCircles[1].y - posY) > 15) and
                                    (math.abs(orders.list[nickname].tempCircles[2].x - posX) > 15 or
                                        math.abs(orders.list[nickname].tempCircles[2].y - posY) > 15)
                             then
                                orders.list[nickname].tempCircles[3] = {
                                    x = posX,
                                    y = posY,
                                    radius = distance
                                }
                                local result, calcX, calcY =
                                    orders.calculate2dCoords(
                                    orders.list[nickname].tempCircles[1],
                                    orders.list[nickname].tempCircles[2],
                                    orders.list[nickname].tempCircles[3]
                                )
                                if result then
                                    orders.list[nickname].pos = {
                                        x = calcX,
                                        y = calcY,
                                        z = 30
                                    }
                                    orders.list[nickname].zone = getZone(calcX, calcY)
                                end

                                orders.list[nickname].tempCircles[1] = nil
                                orders.list[nickname].tempCircles[2] = nil
                                orders.list[nickname].tempCircles[3] = nil
                            end
                        end
                    end
                    for order in pairs(orders.list) do
                        if not table.contains(order, ordersList) then
                            orders.delete(order)
                        end
                    end
                end
            )
            if chat.hiddenMessages["/service"].bool then
                chat.hiddenMessages["/service"].bool = false
                sampSendDialogResponse(DdialogId, 0)
                return false
            end
        end
    end
end

function sampev.onSendDialogResponse(dialogId, button, listboxId, input)
    chat.dialogClock = os.clock() + 1
end

function sampev.onServerMessage(color, message)
    if player.connected then
        if string.find(message, MESSAGES.service) then
            return false
        elseif string.find(message, MESSAGES.payCheck) then
            player.salary, player.salaryLimit = string.match(message, MESSAGES.payCheckFormat)
            if not player.salary then
                player.salary = 0
                player.salaryLimit = 0
            end
            if chat.hiddenMessages["/paycheck"].bool then
                chat.hiddenMessages["/paycheck"].bool = false
                return false
            end
        elseif string.find(message, MESSAGES.clist) then
            if chat.hiddenMessages["/clist"].bool then
                chat.hiddenMessages["/clist"].bool = false
                return false
            end
        elseif
            string.find(message, MESSAGES.noOrders1) or string.find(message, MESSAGES.noOrders2) or 
                string.find(message, MESSAGES.enterService1) or string.find(message, MESSAGES.enterService2)
         then
            if chat.hiddenMessages["/service"].bool then
                chat.hiddenMessages["/service"].bool = false
                return false
            end
        elseif string.find(message, MESSAGES.wrongPerson) then
            if orders.acceptedNickname ~= nil then
                orders.acceptedNickname = nil
                return false
            end
        else
            chat.handleInputMessage(message)
            if string.find(message, MESSAGES.newOrderFormat) then
                local nickname = string.match(message, MESSAGES.newOrderFormat)
                if blacklist.check(nickname) and ini.settings.blacklistHide then
                    return false
                end
            end
            if string.find(message, MESSAGES.orderAcceptedFormat) then
                local _, nickname = string.match(message, MESSAGES.orderAcceptedFormat)
                if blacklist.check(nickname) and ini.settings.blacklistHide then
                    return false
                end
            end
            if string.find(message, "^ %[Такси%] Диспетчер:.+$") and vehicle.maxPassengers and not ini.settings.dispatcherMessages then
                return false
            end
        end
    end
end

function sampev.onSendChat(message)
    chat.lastMessage = message
    chat.updateAntifloodClock()
end

function sampev.onSendCommand(command)
    chat.lastMessage = command
    chat.updateAntifloodClock()
end

function sampev.onSendSpawn()
    if player.onWork then
        if ini.settings.autoClist and not chat.hiddenMessages["/clist"].bool and ini.settings.workClist ~= 0 then
            chat.addMessageToQueue("/clist " .. ini.settings.workClist, true, true)
        end
    end
end

function onScriptTerminate(script, quitGame)
    if script == thisScript() then
        removeBlip(orders.currentOrderBlip)
        deleteCheckpoint(orders.currentOrderCheckpoint)
        vehicle.clearMarkers()
        imgui.Process = false
    end
end

function stringToMeters(string)
    if string.find(string, " м") then
        return tonumber(string.match(string, "(%d+) м"))
    else
        return tonumber(string.match(string, "(.+) км")) * 1000
    end
end

function metersToString(meters, color)
    if color == false then
        color = ""
    else
        color = "{FFFFFF}"
    end
    local distanceString = string.format("%d %sм", meters, color)
    if meters >= 1000 then
        distanceString = string.format("%.1f %sкм", meters / 1000, color)
    end
    return distanceString
end

function stringToSeconds(string)
    if string.find(string, " мин") then
        local minutes, seconds = string.match(string, "(%d+):(%d+) мин")
        return minutes * 60 + seconds
    else
        return tonumber(string.match(string, "(.+) сек"))
    end
end

function table.spairs(iterTable, order)
    local keys = {}

    for key in pairs(iterTable) do
        keys[#keys + 1] = key
    end

    if order then
        table.sort(
            keys,
            function(a, b)
                return order(iterTable, a, b)
            end
        )
    else
        table.sort(keys)
    end

    local index = 0
    return function()
        index = index + 1
        if keys[index] then
            return keys[index], iterTable[keys[index]]
        end
    end
end

function table.getTableKeysSortedByValue(iterTable, valueName, increase)
    local tableKeys = {}

    for key in table.spairs(
        iterTable,
        function(t, a, b)
            if type(t[a][valueName]) ~= "boolean" then
                if increase then
                    return t[a][valueName] < t[b][valueName]
                else
                    return t[a][valueName] > t[b][valueName]
                end
            else
                if increase then
                    return t[b][valueName]
                else
                    return t[a][valueName]
                end
            end
        end
    ) do
        table.insert(tableKeys, key)
    end

    return tableKeys
end

function table.contains(value, table)
    if type(table) == "nil" then
        return false, nil
    end

    for index = 1, #table do
        if value == table[index] then
            return true, index
        end
    end

    return false, nil
end

function table.isEmpty(table)
    if type(table) == "nil" then
        return true
    end

    for _, _ in pairs(table) do
        return false
    end
    return true
end

function imgui.initBuffers()
    imgui.settingsTab = 1
    imgui.binderPage = 1
    imgui.showSettings = imgui.ImBool(false)
    imgui.showInputWindow = imgui.ImBool(false)
    imgui.key1Edit = false
    imgui.key2Edit = false
    imgui.key3Edit = false
    imgui.key4Edit = false
    imgui.singleBind = false
    imgui.key = 0
    imgui.addKey = 0
    imgui.blacklistName = imgui.ImBuffer(25)
    imgui.blacklistName.v = "Nick_Name"
    imgui.SMSPrefix = imgui.ImBuffer(126)
    imgui.SMSPrefix.v = ini.settings.SMSPrefix
    imgui.SMSText = imgui.ImBuffer(126)
    imgui.SMSText.v = ini.settings.SMSText
    imgui.SMSArrival = imgui.ImBuffer(126)
    imgui.SMSArrival.v = ini.settings.SMSArrival
    imgui.SMSCancel = imgui.ImBuffer(126)
    imgui.SMSCancel.v = ini.settings.SMSCancel
    imgui.SMSSeats = imgui.ImBuffer(126)
    imgui.SMSSeats.v = ini.settings.SMSSeats
    imgui.workClist = imgui.ImInt(ini.settings.workClist)
    imgui.SMSTimer = imgui.ImInt(ini.settings.SMSTimer)
    imgui.canceledOrderDelay = imgui.ImInt(ini.settings.canceledOrderDelay)
    imgui.maxDistanceToAcceptOrder = imgui.ImInt(ini.settings.maxDistanceToAcceptOrder)
    imgui.maxDistanceToGetOrder = imgui.ImInt(ini.settings.maxDistanceToGetOrder)
    imgui.ordersDistanceUpdateTimer = imgui.ImInt(ini.settings.ordersDistanceUpdateTimer)
    imgui.soundVolume = imgui.ImInt(ini.settings.soundVolume)
    imgui.maxAutoRefillCost = imgui.ImInt(ini.settings.maxAutoRefillCost)
    imgui.autoRefillGauge = imgui.ImInt(ini.settings.autoRefillGauge)
end

function imgui.showActions(passengerIndex, passengers)
    for bindIndex, bind in pairs(binds.list.actions) do
        imgui.NewLine()
        local x1 = 10.5
        if passengers then
            x1 = x1 + 10
        end
        imgui.SameLine(toScreenX(x1))
        imgui.PushID(passengerIndex + 100)
        if bind.edit then
            local x2 = 29.67
            if not passengers then
                x2 = x2 + 5
            end
            imgui.PushItemWidth(toScreenX(x2))
            imgui.PushStyleVar(imgui.StyleVar.FramePadding, vec(4, 1.1))
            imgui.PushID(bindIndex)
            if imgui.InputText("##text", bind.buffer) then
                binds.save()
            end
            imgui.SetTooltip(bind.buffer.v, 500)
            imgui.PopID()
            imgui.SameLine()
            imgui.PushID(bindIndex)
            if imgui.InputText("##cmd", bind.bufferCmd) then
                binds.save()
            end
            imgui.PopID()
            imgui.PopStyleVar()
            imgui.PopItemWidth()
            imgui.SetTooltip(
                bind.bufferCmd.v .. "\n\nУказанный в сообщении токен '{id}' заменится на id пассажира",
                500
            )
            imgui.SameLine()
            if imgui.Button("X##actions" .. bindIndex, vec(7, 10)) then
                binds.list.actions[bindIndex].edit = false
                binds.delete("actions", bindIndex)
            end
            imgui.SameLine()
            if imgui.Button("-##actions" .. bindIndex, vec(5, 10)) or isKeyJustPressed(13) then
                bind.edit = false
                binds.save()
            end
        else
            local x2 = 80.5
            if passengers then
                x2 = x2 - 10
            end
            if imgui.Button(bind.buffer.v .. "##actions", vec(x2, 10)) and passengerIndex ~= -1 then
                chat.addMessageToQueue(
                    bind.bufferCmd.v:gsub("{id}", tostring(vehicle.passengersList[passengerIndex].id))
                )
            end
            imgui.SameLine()
            if imgui.Button("+##actions" .. bindIndex, vec(5, 10)) then
                binds.chooseEdit("actions", bindIndex)
                binds.save()
            end
        end
        imgui.PopID()
    end
end

function imgui.OnDrawFrame()
    if
        (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or imgui.showInputWindow.v) and
            not sampIsDialogActive() and
            not sampIsChatInputActive() and
            not isPauseMenuActive()
     then
        imgui.ShowCursor = true
    end
    if imgui.showInputWindow.v then
        imgui.onDrawInputWindow()
    elseif
        not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() and
            not (ini.settings.fastMapCompatibility and isKeyDown(fastMapKey))
     then
        imgui.onDrawNotification()
        if ini.settings.showHUD then
            imgui.onDrawHUD()
        end
        if ini.settings.showBindMenu then
            imgui.OnDrawBinder()
        end
        if imgui.showSettings.v then
            imgui.onDrawSettings()
        end
    end
end

function imgui.onDrawInputWindow()
    imgui.SetNextWindowPos(vec(280, 165))
    imgui.SetNextWindowSize(vec(90, 76))
    imgui.Begin(
        "Горячие клавиши",
        imgui.showInputWindow,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar +
            imgui.WindowFlags.NoScrollWithMouse +
            imgui.WindowFlags.NoMove +
            imgui.WindowFlags.NoTitleBar
    )
    imgui.Dummy(vec(15, 0))
    imgui.SameLine()
    if not imgui.singleBind then
        imgui.Text("Установить клавиши")
    else
        imgui.Text("Установить клавишу")
    end
    imgui.Dummy(vec(0, 10))
    imgui.NewLine()
    if imgui.key ~= 0 then
        imgui.SameLine()
        imgui.Text(vkeys.id_to_name(imgui.key))
    end
    if imgui.addKey ~= 0 then
        imgui.SameLine()
        imgui.Text("+ " .. vkeys.id_to_name(imgui.addKey))
    end

    lua_thread.create(
        function()
            repeat
                wait(0)
                for k, v in pairs(vkeys) do
                    if wasKeyPressed(v) then
                        if v < 160 or v > 165 then
                            if
                                imgui.key == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and k ~= "VK_BACK" and
                                    k ~= "VK_LBUTTON" and
                                    k ~= "VK_RBUTTON"
                             then
                                imgui.key = v
                            elseif
                                imgui.key ~= v and imgui.addKey == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and
                                    k ~= "VK_BACK" and
                                    k ~= "VK_LBUTTON" and
                                    k ~= "VK_RBUTTON" and
                                    not imgui.singleBind
                             then
                                imgui.addKey = v
                            elseif k == "VK_ESCAPE" then
                                imgui.key = 0
                                imgui.addKey = 0
                                imgui.showInputWindow.v = false
                            elseif k == "VK_RETURN" then
                                imgui.showInputWindow.v = false
                            elseif k == "VK_BACK" then
                                imgui.key = 0
                                imgui.addKey = 0
                            end
                        end
                    end
                end
            until not imgui.showInputWindow.v
            imgui.showInputWindow.v = false
        end
    )
    imgui.Dummy(vec(0, 10))
    if not imgui.singleBind then
        imgui.Text("Нажмите клавишу/комбинацию\nBackspace - стереть клавиши")
    else
        imgui.Text("Нажмите клавишу\nBackspace - стереть клавишу")
    end
    if imgui.Button("Принять", vec(27, 10)) then
        imgui.showInputWindow.v = false
    end
    imgui.SameLine()
    if imgui.Button("Удалить", vec(27, 10)) then
        imgui.key = -1
        imgui.showInputWindow.v = false
    end
    imgui.SameLine()
    if imgui.Button("Отменить", vec(27, 10)) then
        imgui.key = 0
        imgui.addKey = 0
        imgui.showInputWindow.v = false
    end
    imgui.End()
end

imgui.hudHovered = false
function imgui.onDrawHUD()
    if vehicle.name or isKeysPressed(ini.settings.key1, ini.settings.key1add, true) then
        local windowPosY = 0
        local zone = nil
        local gps = nil
        if orders.currentOrder then
            windowPosY = windowPosY + 37
        elseif orders.GPSMark then
            windowPosY = windowPosY + 9.5
            zone = getZone(orders.GPSMark.x, orders.GPSMark.y)
            gps = {x = orders.GPSMark.x, y = orders.GPSMark.y}
        end

        if
            not (imgui.hudHovered and imgui.IsMouseDragging(0) and
                isKeysPressed(ini.settings.key1, ini.settings.key1add, true)) or
                orders.currentOrder or
                orders.GPSMark
         then
            imgui.SetNextWindowPos(vec(ini.settings.hudPosX, ini.settings.hudPosY - windowPosY))
            imgui.SetNextWindowSize(vec(105, 42 + windowPosY))
        end

        imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
        imgui.Begin(
            "Taximate HUD",
            _,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar +
                imgui.WindowFlags.NoScrollWithMouse +
                imgui.WindowFlags.NoFocusOnAppearing
        )
        imgui.hudHovered = imgui.IsRootWindowOrAnyChildHovered()
        local newPos = imgui.GetWindowPos()
        local savePosX, savePosY = convertWindowScreenCoordsToGameScreenCoords(newPos.x, newPos.y)

        if
            (math.ceil(savePosX) ~= math.ceil(ini.settings.hudPosX) or
                math.ceil(savePosY) ~= math.ceil(ini.settings.hudPosY)) and
                imgui.IsRootWindowOrAnyChildFocused() and
                imgui.IsMouseDragging(0) and
                imgui.IsRootWindowOrAnyChildHovered() and
                not (orders.currentOrder or orders.GPSMark)
         then
            ini.settings.hudPosX = math.ceil(savePosX)
            ini.settings.hudPosY = math.ceil(savePosY)
            inicfg.save(ini, "Taximate/settings.ini")
        end

        if not player.onWork then
            local buttonText = "Начать рабочий день"
            if ini.settings.hotKeys then
                if ini.settings.key3 ~= 0 then
                    buttonText = buttonText .. " [" .. vkeys.id_to_name(ini.settings.key3)
                    if ini.settings.key3add ~= 0 then
                        buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key3add)
                    end
                    buttonText = buttonText .. "]"
                end
            end
            if imgui.Button(buttonText, vec(100, 10)) then
                player.onWork = true
                if ini.settings.autoClist and ini.settings.workClist ~= 0 then
                    chat.addMessageToQueue("/clist " .. ini.settings.workClist, true, true)
                end
            end
        else
            local buttonText = "Закончить рабочий день"
            if ini.settings.hotKeys then
                if ini.settings.key3 ~= 0 then
                    buttonText = buttonText .. " [" .. vkeys.id_to_name(ini.settings.key3)
                    if ini.settings.key3add ~= 0 then
                        buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key3add)
                    end
                    buttonText = buttonText .. "]"
                end
            end
            if imgui.Button(buttonText, vec(100, 10)) then
                player.onWork = false
                if ini.settings.autoClist then
                    chat.addMessageToQueue("/clist 0", true, true)
                end
            end
        end
        if zone then
            local posX, posY = getCharCoordinates(PLAYER_PED)
            imgui.BeginChild(
                "##upleft",
                vec(90, 8),
                false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
            )
            imgui.TextColoredRGB(
                "GPS: {4296f9}" ..
                    zone ..
                        "{FFFFFF}, {4296f9}" ..
                            metersToString(math.ceil(getDistanceBetweenCoords2d(posX, posY, gps.x, gps.y)))
            )
            imgui.EndChild()
            imgui.SameLine()
            imgui.BeginChild(
                "##upright",
                vec(10, 8),
                false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
            )
            imgui.PushStyleVar(imgui.StyleVar.FramePadding, vec(2, 0))
            if imgui.Button("X") then
                chat.addMessageToQueue("/gps", true, true)
            end
            imgui.PopStyleVar()
            imgui.EndChild()
        end
        imgui.BeginChild(
            "##midleft",
            vec(56, 8),
            false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        )
        imgui.TextColoredRGB("Скилл: {4296f9}" .. player.skill .. " {FFFFFF}(" .. player.skillExp .. "%)")
        imgui.SameLine()
        imgui.TextDisabled("(?)")
        imgui.SetTooltip("Клиентов до следующего уровня: " .. player.skillClients, 70)
        imgui.EndChild()
        imgui.SameLine()
        imgui.BeginChild(
            "##midright",
            vec(44, 8),
            false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        )
        imgui.TextColoredRGB("Ранг: {4296f9}" .. player.rank .. " {FFFFFF}(" .. player.rankExp .. "%)")
        imgui.EndChild()
        imgui.BeginChild(
            "##bottomleft",
            vec(56.5, 8),
            false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        )
        imgui.TextColoredRGB("ЗП: {4296f9}" .. player.salary .. " / " .. player.salaryLimit .. "{FFFFFF} вирт")
        imgui.EndChild()
        imgui.SameLine()
        imgui.BeginChild(
            "##bottomright ",
            vec(43.5, 8),
            false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        )
        imgui.TextColoredRGB("Чай: {4296f9}" .. player.tips .. "{FFFFFF} вирт")
        imgui.EndChild()

        if orders.currentOrder then
            imgui.BeginChild(
                "bottom  ",
                vec(100, 34),
                true,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
            )
            imgui.TextColoredRGB(
                "Клиент: {4296f9}" ..
                    orders.currentOrder.nickname ..
                        "[" .. orders.currentOrder.id .. "]{ffffff} (" .. orders.currentOrder.level .. ")"
            )
            imgui.TextColoredRGB(
                "Район: {4296f9}" ..
                    orders.currentOrder.zone ..
                        "{FFFFFF},{4296f9} " .. metersToString(orders.currentOrder.currentDistance)
            )
            local buttonText = "Отменить вызов"
            if ini.settings.hotKeys then
                if ini.settings.key2 ~= 0 then
                    buttonText = buttonText .. " [" .. vkeys.id_to_name(ini.settings.key2)
                    if ini.settings.key2add ~= 0 then
                        buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key2add)
                    end
                    buttonText = buttonText .. "]"
                end
            end
            if imgui.Button(buttonText, vec(95, 10)) then
                orders.startOrderCanceling()
            end
            imgui.EndChild()
        end
        imgui.End()
        imgui.PopStyleVar()
    end
end

imgui.bindHovered = false
function imgui.OnDrawBinder()
    if
        isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or binds.isEdit("binds") or binds.isEdit("actions") or
            binds.isEdit("sms")
     then
        local passengers = not table.isEmpty(vehicle.passengersList)
        local sizeX = 104

        imgui.ShowCursor = true

        local flags =
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysVerticalScrollbar

        if
            not (imgui.bindHovered and imgui.IsMouseDragging(0) and
                (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or binds.isEdit("binds")))
         then
            imgui.SetNextWindowPos(vec(ini.settings.binderPosX, ini.settings.binderPosY))
            imgui.SetNextWindowSize(vec(sizeX, 225))
        end

        imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
        imgui.Begin("Taximate Binder", _, flags)
        imgui.bindHovered = imgui.IsRootWindowOrAnyChildHovered()
        local newPos = imgui.GetWindowPos()
        local savePosX, savePosY = convertWindowScreenCoordsToGameScreenCoords(newPos.x, newPos.y)

        if
            (math.ceil(savePosX) ~= math.ceil(ini.settings.binderPosX) or
                math.ceil(savePosY) ~= math.ceil(ini.settings.binderPosY)) and
                (imgui.bindHovered and imgui.IsMouseDragging(0) and
                    (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or binds.isEdit("binds")))
         then
            ini.settings.binderPosX = math.ceil(savePosX)
            ini.settings.binderPosY = math.ceil(savePosY)
            inicfg.save(ini, "Taximate/settings.ini")
        end

        imgui.NewLine()
        imgui.SameLine(toScreenX(3))
        if imgui.CollapsingHeader("Отправить СМС клиенту", vec(97, 10)) then
            imgui.NewLine()
            imgui.SameLine(toScreenX(10.5))
            if imgui.Button("Добавить сообщение", vec(87.5, 9)) then
                if not binds.isEdit("sms") then
                    local num = #binds.list.sms + 1
                    if num - 1 < 12 then
                        local buffer = imgui.ImBuffer(128)
                        local bufferCmd = imgui.ImBuffer(128)
                        buffer.v = "Новое сообщение"
                        bufferCmd.v = ""
                        binds.list.sms[num] = {
                            buffer = buffer,
                            bufferCmd = bufferCmd,
                            key = 0,
                            addKey = 0,
                            edit = false
                        }
                        binds.save()
                    end
                end
            end
            for bindIndex, bind in pairs(binds.list.sms) do
                imgui.NewLine()
                imgui.SameLine(toScreenX(10.5))
                imgui.PushID(bindIndex + 200)
                if bind.edit then
                    imgui.PushItemWidth(toScreenX(51.6))
                    imgui.PushStyleVar(imgui.StyleVar.FramePadding, vec(4, 1.1))
                    imgui.PushID(bindIndex)
                    if imgui.InputText("##textsms", bind.buffer) then
                        binds.save()
                    end
                    imgui.PopID()
                    imgui.SetTooltip(
                        bind.buffer.v .. "\n\nДоступные для замены токены:\n{carname}, {distance}, {zone}",
                        500
                    )
                    imgui.SameLine()
                    local buttonName = "Bind"
                    if bind.key ~= 0 then
                        buttonName = vkeys.id_to_name(bind.key)
                    end
                    if bind.addKey ~= 0 then
                        buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.addKey)
                    end
                    if imgui.Button(buttonName .. "##sms", vec(18, 10)) then
                        imgui.key = 0
                        imgui.addKey = 0
                        imgui.showInputWindow.v = true
                    end
                    imgui.PopStyleVar()
                    imgui.PopItemWidth()
                    if not imgui.showInputWindow.v and imgui.key ~= 0 then
                        if imgui.key == -1 then
                            imgui.key = 0
                            imgui.addKey = 0
                        end
                        bind.key = imgui.key
                        bind.addKey = imgui.addKey
                        imgui.key = 0
                        imgui.addKey = 0
                        binds.save()
                    end
                    imgui.SameLine()
                    if imgui.Button("X##sms" .. bindIndex, vec(7, 10)) then
                        bind.edit = false
                        binds.delete("sms", bindIndex)
                    end
                    imgui.SameLine()
                    if imgui.Button("-##sms" .. bindIndex, vec(5, 10)) or isKeyJustPressed(13) then
                        bind.edit = false
                        binds.save()
                    end
                else
                    local text = chat.subSMSText(ini.settings.SMSPrefix, bind.buffer.v)
                    local buttonName = ""
                    if ini.settings.hotKeys then
                        if bind.key ~= 0 then
                            buttonName = "[" .. vkeys.id_to_name(bind.key)
                        end
                        if bind.addKey ~= 0 then
                            buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.addKey)
                        end
                        if buttonName ~= "" then
                            buttonName = buttonName .. "] "
                        end
                    end
                    buttonName = buttonName .. text
                    if imgui.Button(buttonName .. "##sms" .. bindIndex, vec(80.5, 10)) and orders.currentOrder then
                        chat.addMessageToQueue(string.format("/service chat %s", text))
                    end
                    if utf8len(text) > 25 then
                        imgui.SetTooltip(text, 500)
                    end
                    imgui.SameLine()
                    if imgui.Button("+##sms" .. bindIndex, vec(5, 10)) then
                        binds.chooseEdit("sms", bindIndex)
                        binds.save()
                    end
                end
                imgui.PopID()
            end
        end

        imgui.NewLine()
        imgui.SameLine(toScreenX(3))
        if imgui.CollapsingHeader("Меню действий с пассажирами") then
            imgui.NewLine()
            imgui.SameLine(toScreenX(10.5))
            if imgui.Button("Добавить действие", vec(87.5, 9)) then
                if not binds.isEdit("actions") then
                    local num = #binds.list.actions + 1
                    if num - 1 < 12 then
                        local buffer = imgui.ImBuffer(128)
                        local bufferCmd = imgui.ImBuffer(128)
                        buffer.v = "Новое действие"
                        bufferCmd.v = "/cmd {id}"
                        binds.list.actions[num] = {
                            buffer = buffer,
                            bufferCmd = bufferCmd,
                            key = 0,
                            addKey = 0,
                            edit = false
                        }
                        binds.save()
                    end
                end
            end
            if passengers and vehicle.maxPassengers then
                for passengerIndex = 0, vehicle.maxPassengers - 1 do
                    if vehicle.passengersList[passengerIndex] then
                        imgui.NewLine()
                        imgui.SameLine(toScreenX(11))
                        if
                            imgui.CollapsingHeader(
                                vehicle.passengersList[passengerIndex].nickname ..
                                    "[" .. vehicle.passengersList[passengerIndex].id .. "]",
                                vec(89, 10)
                            )
                         then
                            imgui.showActions(passengerIndex, passengers)
                        end
                    end
                end
            else
                imgui.showActions(-1, passengers)
            end
        end

        imgui.BeginChild("binderPage", vec(97, 10), false)
        for i = 1, 10 do
            imgui.BeginChild(tostring(i), vec(8, 10), false)
            local bindPage = i == 1 and 0 or (i - 1) * 14
            local bindPageText = i < 10 and " " .. i or tostring(i)
            local binderSize = #binds.list.binds
            if binderSize > bindPage or i == 1 then
                if imgui.Selectable(bindPageText, imgui.binderPage == i, 0, vec(5, 8)) then
                    imgui.binderPage = i
                end
            else
                if imgui.binderPage == i then
                    imgui.binderPage = imgui.binderPage - 1
                end
                imgui.TextDisabled(bindPageText)
            end
            imgui.EndChild()
            if i < 10 then
                imgui.SameLine()
            end
        end
        imgui.EndChild()

        if imgui.Button("Добавить строку", vec(96, 10)) then
            if not binds.isEdit("binds") then
                local num = #binds.list.binds + 1
                if num <= 140 then
                    local buffer = imgui.ImBuffer(128)
                    local bufferCmd = imgui.ImBuffer(128)
                    buffer.v = ""
                    bufferCmd.v = ""
                    binds.list.binds[num] = {
                        buffer = buffer,
                        bufferCmd = bufferCmd,
                        key = 0,
                        addKey = 0,
                        edit = false
                    }
                    binds.save()
                end
            end
        end

        local beginBind, endBind = 1, 14

        if imgui.binderPage > 1 then
            beginBind = 15 + (imgui.binderPage - 2) * 14
            endBind = imgui.binderPage * 14
        end

        for bindIndex = beginBind, endBind do
            if binds.list.binds[bindIndex] then
                local bind = binds.list.binds[bindIndex]
                imgui.PushID(bindIndex)
                if bind.edit then
                    imgui.PushItemWidth(toScreenX(55.5))
                    imgui.PushStyleVar(imgui.StyleVar.FramePadding, vec(4, 1.1))
                    imgui.PushID(bindIndex)
                    if imgui.InputText("", bind.buffer) then
                        binds.save()
                    end
                    imgui.SetTooltip(bind.buffer.v, 500)
                    imgui.PopID()
                    imgui.PopStyleVar()
                    imgui.PopItemWidth()
                else
                    local buttonName = ""
                    if ini.settings.hotKeys then
                        if bind.key ~= 0 then
                            buttonName = "[" .. vkeys.id_to_name(bind.key)
                        end
                        if bind.addKey ~= 0 then
                            buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.addKey)
                        end
                        if buttonName ~= "" then
                            buttonName = buttonName .. "] "
                        end
                    end
                    buttonName = buttonName .. bind.buffer.v
                    if imgui.Button(buttonName, vec(89, 10)) then
                        chat.addMessageToQueue(bind.buffer.v)
                    end
                    if utf8len(bind.buffer.v) > 30 then
                        imgui.SetTooltip(bind.buffer.v, 500)
                    end
                end

                imgui.PopID()
                imgui.SameLine()
                imgui.PushID(bindIndex)
                if bind.edit then
                    local buttonName = "Bind"
                    if bind.key ~= 0 then
                        buttonName = vkeys.id_to_name(bind.key)
                    end
                    if bind.addKey ~= 0 then
                        buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.addKey)
                    end
                    if imgui.Button(buttonName, vec(23, 10)) then
                        imgui.key = 0
                        imgui.addKey = 0
                        imgui.showInputWindow.v = true
                    end

                    if not imgui.showInputWindow.v and imgui.key ~= 0 then
                        if imgui.key == -1 then
                            imgui.key = 0
                            imgui.addKey = 0
                        end
                        bind.key = imgui.key
                        bind.addKey = imgui.addKey
                        imgui.key = 0
                        imgui.addKey = 0
                        binds.save()
                    end
                    imgui.SameLine()
                    if imgui.Button("X", vec(7, 10)) then
                        binds.list.binds[bindIndex].edit = false
                        binds.delete("binds", bindIndex)
                    end
                    imgui.SameLine()
                    if binds.list.binds[bindIndex] then
                        if imgui.Button("-", vec(5, 10)) or isKeyJustPressed(13) then
                            bind.edit = false
                            binds.save()
                        end
                    end
                else
                    if imgui.Button("+##" .. bindIndex, vec(5, 10)) then
                        binds.chooseEdit("binds", bindIndex)
                        binds.save()
                    end
                end
                imgui.PopID()
            end
        end
        imgui.End()
        imgui.PopStyleVar()
    end
end

function imgui.onDrawNotification()
    local count = 0
    for notificationIndex, notification in ipairs(notificationsQueue) do
        local push = false
        local isOrderExist = orders.list[notification.orderNickname]
        local sizeWithButton = 0

        if notification.button then
            sizeWithButton = sizeWithButton + 16
        end

        if notification.active and (notification.time < os.clock() or (notification.button and not isOrderExist)) then
            notification.active = false
        end

        if not notification.showtime then
            if notification.time < os.clock() then
                if notification.button and isOrderExist then
                    if orders.list[notification.orderNickname].direction > 0 then
                        notification.active = true
                    end
                else
                    notificationsQueue[notificationIndex] = nil
                end
            end
        end

        if notification then
            if count < 3 then
                if not notification.active then
                    if notification.showtime > 0 then
                        notification.active = true
                        notification.time = os.clock() + notification.showtime
                        notification.showtime = 0
                    end
                end

                if
                    notification.active and
                        (vehicle.name or isKeysPressed(ini.settings.key1, ini.settings.key1add, true))
                 then
                    count = count + 1
                    if notification.time + 3.000 >= os.clock() then
                        if (notification.time - os.clock()) / 1.0 > 0.95 then
                            imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
                        else
                            imgui.PushStyleVar(imgui.StyleVar.Alpha, (notification.time - os.clock()) / 1.0)
                        end
                        push = true
                    end

                    local notfPos = 0
                    if orders.currentOrder then
                        notfPos = notfPos + 37
                    elseif orders.GPSMark then
                        notfPos = notfPos + 9.5
                    end
                    local notificationTitle = "{4296f9}Taximate notification\t\t\t\t\t{FFFFFF}" .. notification.date

                    notfList.pos = {
                        x = ini.settings.hudPosX,
                        y = notfList.pos.y - (notfList.size.y + 10 + sizeWithButton + notification.addSize)
                    }
                    imgui.SetNextWindowPos(vec(notfList.pos.x, notfList.pos.y - notfPos))
                    imgui.SetNextWindowSize(
                        vec(
                            105,
                            sizeWithButton + notfList.size.y + imgui.GetStyle().ItemSpacing.y +
                                imgui.GetStyle().WindowPadding.y -
                                5 +
                                notification.addSize
                        )
                    )
                    imgui.Begin(
                        "message #" .. notificationIndex,
                        _,
                        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar +
                            imgui.WindowFlags.NoScrollWithMouse +
                            imgui.WindowFlags.NoMove +
                            imgui.WindowFlags.NoTitleBar
                    )
                    imgui.TextColoredRGB(notificationTitle)
                    imgui.Dummy(vec(0, 2))
                    if notification.button then
                        if orders.list[notification.orderNickname] then
                            local notfText = FORMAT_NOTIFICATIONS.newOrder
                            if orders.list[notification.orderNickname].direction > 0 then
                                notfText = notfText:gsub(": {4296f9}", ": {42ff96}")
                            elseif orders.list[notification.orderNickname].direction < 0 then
                                notfText = notfText:gsub(": {4296f9}", ": {d44331}")
                            end
                            notification.text =
                                string.format(
                                notfText,
                                notification.orderNickname,
                                orders.list[notification.orderNickname].id,
                                orders.list[notification.orderNickname].level,
                                metersToString(orders.list[notification.orderNickname].distance),
                                orders.list[notification.orderNickname].zone
                            )
                            if orders.list[notification.orderNickname].zone ~= "Неизвестно" then
                                notification.text =
                                    notification.text .. ", {4296f9}" .. orders.list[notification.orderNickname].zone
                            end
                        end
                    end
                    imgui.TextColoredRGB(notification.text)
                    imgui.Dummy(vec(0, 2))
                    if notification.button then
                        local acceptOrderText = "Принять вызов"
                        if
                            orders.lastCorrectOrderNickname == notification.orderNickname and ini.settings.hotKeys and
                                ini.settings.key2 ~= 0
                         then
                            acceptOrderText = acceptOrderText .. " [" .. vkeys.id_to_name(ini.settings.key2)
                            if ini.settings.key2add ~= 0 then
                                acceptOrderText = acceptOrderText .. " + " .. vkeys.id_to_name(ini.settings.key2add)
                            end
                            acceptOrderText = acceptOrderText .. "]"
                        end
                        if imgui.Button(acceptOrderText, vec(100, 10)) then
                            orders.accept(notification.orderNickname, orders.list[notification.orderNickname].time)
                            imgui.Dummy(vec(0, 2))
                        end
                    end
                    imgui.End()
                    if push then
                        imgui.PopStyleVar()
                    end
                    if not notification.active then
                        notification = nil
                    end
                end
            end
        end
    end
    notfList = {
        pos = {x = ini.settings.hudPosX, y = ini.settings.hudPosY},
        size = {x = 100, y = 29}
    }
end

function imgui.onDrawSettings()
    imgui.ShowCursor = true
    imgui.SetNextWindowSize(vec(200, 180))
    imgui.SetNextWindowPos(vec(220, 130), 2)
    imgui.Begin(
        "Taximate " .. thisScript().version,
        imgui.showSettings,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
    )
    imgui.BeginChild("top", vec(195, 9), false)
    if imgui.Selectable("\t\t\t Настройки", imgui.settingsTab == 1, 0, vec(65, 8)) then
        imgui.settingsTab = 1
    end
    imgui.SameLine()
    if imgui.Selectable("\t\t  Чёрный список", imgui.settingsTab == 2, 0, vec(65, 8)) then
        imgui.settingsTab = 2
    end
    imgui.SameLine()
    if imgui.Selectable("\t\t  Информация", imgui.settingsTab == 3, 0, vec(65, 8)) then
        if imgui.settingsTab ~= 3 and ini.settings.checkUpdates then
            checkUpdates()
        end
        imgui.settingsTab = 3
    end
    imgui.EndChild()
    imgui.BeginChild("bottom", vec(195, 155), true)
    if imgui.settingsTab == 1 then
        if imgui.CollapsingHeader("Общие настройки", true, imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox("Показывать Taximate Binder", imgui.ImBool(ini.settings.showBindMenu)) then
                ini.settings.showBindMenu = not ini.settings.showBindMenu
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            if imgui.Checkbox("Показывать Taximate HUD", imgui.ImBool(ini.settings.showHUD)) then
                ini.settings.showHUD = not ini.settings.showHUD
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Уведомления", imgui.ImBool(ini.settings.notifications)) then
                ini.settings.notifications = not ini.settings.notifications
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            if
                imgui.Checkbox(
                    "Звуковые уведомления, громкость: ",
                    imgui.ImBool(ini.settings.notifications and ini.settings.sounds)
                )
             then
                ini.settings.sounds = not ini.settings.sounds
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SetTooltip(
                "Для работы требуется выставить минимальную громкость игрового радио и перезапустить игру",
                90
            )
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(40))
            if imgui.SliderInt("", imgui.soundVolume, 0, 100) then
                if imgui.soundVolume.v < 0 or imgui.soundVolume.v > 100 then
                    imgui.soundVolume.v = defaults.soundVolume
                end
                ini.settings.soundVolume = imgui.soundVolume.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SetTooltip(
                "Для работы требуется выставить минимальную громкость игрового радио и перезапустить игру",
                90
            )
            imgui.NewLine()
        end
        if imgui.CollapsingHeader("Приём вызовов", true, imgui.TreeNodeFlags.DefaultOpen) then
            imgui.Text("Дистанция для принятия вызова:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(95.7))
            if imgui.SliderInt("м", imgui.maxDistanceToAcceptOrder, 0, 7000) then
                if imgui.maxDistanceToAcceptOrder.v < 0 or imgui.maxDistanceToAcceptOrder.v > 7000 then
                    imgui.maxDistanceToAcceptOrder.v = defaults.maxDistanceToAcceptOrder
                end
                ini.settings.maxDistanceToAcceptOrder = imgui.maxDistanceToAcceptOrder.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.Text("Дистанция для получения доп. вызова:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(80.5))
            if imgui.SliderInt("м##", imgui.maxDistanceToGetOrder, 0, 2000) then
                if imgui.maxDistanceToGetOrder.v < 0 or imgui.maxDistanceToGetOrder.v > 2000 then
                    imgui.maxDistanceToGetOrder.v = defaults.maxDistanceToGetOrder
                end
                ini.settings.maxDistanceToGetOrder = imgui.maxDistanceToGetOrder.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.Text("Принимать вызовы от игроков с уровнем:")
            imgui.SameLine()
            if imgui.Checkbox("1-2", imgui.ImBool(ini.settings.autoAccept1_2)) then
                ini.settings.autoAccept1_2 = not ini.settings.autoAccept1_2
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            if imgui.Checkbox("3-5", imgui.ImBool(ini.settings.autoAccept3_5)) then
                ini.settings.autoAccept3_5 = not ini.settings.autoAccept3_5
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            if imgui.Checkbox("6+", imgui.ImBool(ini.settings.autoAccept6)) then
                ini.settings.autoAccept6 = not ini.settings.autoAccept6
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.NewLine()
            if imgui.Checkbox("Показывать сообщения диспетчера", imgui.ImBool(ini.settings.dispatcherMessages)) then
                ini.settings.dispatcherMessages = not ini.settings.dispatcherMessages
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if
                imgui.Checkbox(
                    "Не принимать отмененные вызовы в течение",
                    imgui.ImBool(ini.settings.ignoreCanceledOrder)
                )
             then
                ini.settings.ignoreCanceledOrder = not ini.settings.ignoreCanceledOrder
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(50))
            if imgui.SliderInt("сек ", imgui.canceledOrderDelay, 0, 600) then
                if imgui.canceledOrderDelay.v < 0 or imgui.canceledOrderDelay.v > 600 then
                    imgui.canceledOrderDelay.v = defaults.canceledOrderDelay
                end
                ini.settings.canceledOrderDelay = imgui.canceledOrderDelay.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Обновлять дистанцию вызовов раз в", imgui.ImBool(ini.settings.ordersDistanceUpdate)) then
                ini.settings.ordersDistanceUpdate = not ini.settings.ordersDistanceUpdate
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(71.5))
            if imgui.SliderInt("сeк", imgui.ordersDistanceUpdateTimer, 1, 30) then
                if imgui.ordersDistanceUpdateTimer.v < 1 or imgui.ordersDistanceUpdateTimer.v > 30 then
                    imgui.ordersDistanceUpdateTimer.v = defaults.ordersDistanceUpdateTimer
                end
                ini.settings.ordersDistanceUpdateTimer = imgui.ordersDistanceUpdateTimer.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Заводить двигатель при принятии вызова", imgui.ImBool(ini.settings.startEngine)) then
                ini.settings.startEngine = not ini.settings.startEngine
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.NewLine()
        end
        if imgui.CollapsingHeader("Отправка сообщений", true, imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox("Отправлять СМС клиенту раз в", imgui.ImBool(ini.settings.sendSMS)) then
                ini.settings.sendSMS = not ini.settings.sendSMS
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(85))
            if imgui.SliderInt("сек", imgui.SMSTimer, 15, 90) then
                if imgui.SMSTimer.v < 15 or imgui.SMSTimer.v > 90 then
                    imgui.SMSTimer.v = defaults.SMSTimer
                end
                ini.settings.SMSTimer = imgui.SMSTimer.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Отправлять СМС клиенту при отмене вызова", imgui.ImBool(ini.settings.sendSMSCancel)) then
                ini.settings.sendSMSCancel = not ini.settings.sendSMSCancel
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if
                imgui.Checkbox(
                    "Отправка СМС об одном пассажирском месте для такси Buffalo",
                    imgui.ImBool(ini.settings.seatsNotify)
                )
             then
                ini.settings.seatsNotify = not ini.settings.seatsNotify
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.NewLine()
            imgui.Text("СМС префикс:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(60))
            if imgui.InputText("##SMSPrefix", imgui.SMSPrefix) then
                ini.settings.SMSPrefix = imgui.SMSPrefix.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            local color = "{FFFFFF}"
            local text = chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSText)
            imgui.TextColoredRGB(color .. "Доклад:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(165))
            if imgui.InputText("##SMSText", imgui.SMSText) then
                ini.settings.SMSText = imgui.SMSText.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            local color = "{FFFFFF}"
            local text = chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSArrival)
            imgui.TextColoredRGB(color .. "Прибытие:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(158))
            if imgui.InputText("##SMSArrival", imgui.SMSArrival) then
                ini.settings.SMSArrival = imgui.SMSArrival.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            local color = "{FFFFFF}"
            local text = chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSSeats)
            imgui.TextColoredRGB(color .. "Одно пасс. место:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(139.5))
            if imgui.InputText("##SMSSeats", imgui.SMSSeats) then
                ini.settings.SMSSeats = imgui.SMSSeats.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            local color = "{FFFFFF}"
            local text = chat.subSMSText(ini.settings.SMSPrefix, ini.settings.SMSCancel)
            imgui.TextColoredRGB(color .. "Отмена вызова:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(144.5))
            if imgui.InputText("##SMSCancel", imgui.SMSCancel) then
                ini.settings.SMSCancel = imgui.SMSCancel.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.TextDisabled("Доступные для замены токены: {carname}, {distance}, {zone}")
            imgui.NewLine()
        end
        if imgui.CollapsingHeader("Горячие клавиши", true, imgui.TreeNodeFlags.DefaultOpen) then
            imgui.PushID("hotkeys")
            if imgui.Checkbox("Горячие клавиши", imgui.ImBool(ini.settings.hotKeys)) then
                ini.settings.hotKeys = not ini.settings.hotKeys
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.PopID()
            imgui.Text("Открыть Taximate HUD/Binder: ")
            imgui.SameLine()
            local buttonText = "None"
            if ini.settings.key1 ~= 0 then
                buttonText = vkeys.id_to_name(ini.settings.key1)
            end
            if ini.settings.key1add ~= 0 then
                buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key1add)
            end
            imgui.PushID(1)
            if imgui.Button(buttonText, vec(0, 10)) then
                imgui.key = 0
                imgui.addKey = 0
                imgui.showInputWindow.v = true
                imgui.key1Edit = true
            end
            imgui.PopID()
            if not ini.settings.hotKeys then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 0.5))
            end
            imgui.Text("Принять/отменить вызов: ")
            imgui.SameLine()
            buttonText = "None"
            if ini.settings.key2 ~= 0 then
                buttonText = vkeys.id_to_name(ini.settings.key2)
            end
            if ini.settings.key2add ~= 0 then
                buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key2add)
            end
            imgui.PushID(2)
            if imgui.Button(buttonText, vec(0, 10)) then
                imgui.key = 0
                imgui.addKey = 0
                imgui.showInputWindow.v = true
                imgui.key2Edit = true
            end
            imgui.PopID()
            imgui.Text("Начать/закончить работу таксиста: ")
            imgui.SameLine()
            buttonText = "None"
            if ini.settings.key3 ~= 0 then
                buttonText = vkeys.id_to_name(ini.settings.key3)
            end
            if ini.settings.key3add ~= 0 then
                buttonText = buttonText .. " + " .. vkeys.id_to_name(ini.settings.key3add)
            end
            imgui.PushID(3)
            if imgui.Button(buttonText, vec(0, 10)) then
                imgui.key = 0
                imgui.addKey = 0
                imgui.showInputWindow.v = true
                imgui.key3Edit = true
            end
            imgui.PopID()
            if not ini.settings.hotKeys then
                imgui.PopStyleColor()
            end
            if imgui.Checkbox("Активация круиз-контроля клавишей", imgui.ImBool(ini.settings.cruiseControl)) then
                ini.settings.cruiseControl = not ini.settings.cruiseControl
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            local buttonText = "None"
            if ini.settings.key4 ~= 0 then
                buttonText = vkeys.id_to_name(ini.settings.key4)
            end
            imgui.PushID(4)
            if imgui.Button(buttonText, vec(0, 10)) then
                imgui.key = 0
                imgui.addKey = 0
                imgui.showInputWindow.v = true
                imgui.singleBind = true
                imgui.key4Edit = true
            end
            imgui.PopID()
            if not imgui.showInputWindow.v and imgui.key ~= 0 then
                if imgui.key == -1 then
                    imgui.key = 0
                    imgui.addKey = 0
                end
                if imgui.key1Edit then
                    ini.settings.key1 = imgui.key
                    ini.settings.key1add = imgui.addKey
                elseif imgui.key2Edit then
                    ini.settings.key2 = imgui.key
                    ini.settings.key2add = imgui.addKey
                elseif imgui.key3Edit then
                    ini.settings.key3 = imgui.key
                    ini.settings.key3add = imgui.addKey
                elseif imgui.key4Edit then
                    ini.settings.key4 = imgui.key
                end
                inicfg.save(ini, "Taximate/settings.ini")
                imgui.key1Edit = false
                imgui.key2Edit = false
                imgui.key3Edit = false
                imgui.key4Edit = false
                imgui.singleBind = false
                imgui.key = 0
                imgui.addKey = 0
            end  
            imgui.NewLine()
        end
        if imgui.CollapsingHeader("Прочие настройки", true, imgui.TreeNodeFlags.DefaultOpen) then
            imgui.Text("Принимать предложения ")
            imgui.SameLine()
            if imgui.Checkbox("ремонта ", imgui.ImBool(ini.settings.autoRepair)) then
                ini.settings.autoRepair = not ini.settings.autoRepair
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            if imgui.Checkbox("заправки", imgui.ImBool(ini.settings.autoRefill)) then
                ini.settings.autoRefill = not ini.settings.autoRefill
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if not ini.settings.autoRefill then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 0.5))
            end
            imgui.Text("Максимальная цена заправки:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(95))
            if imgui.SliderInt("вирт", imgui.maxAutoRefillCost, 500, 5000) then
                if imgui.maxAutoRefillCost.v < 500 or imgui.maxAutoRefillCost.v > 5000 then
                    imgui.maxAutoRefillCost.v = defaults.maxAutoRefillCost
                end
                ini.settings.maxAutoRefillCost = imgui.maxAutoRefillCost.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.Text("Минимальный остаток литров для заправки:")
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(74))
            if imgui.SliderInt("##л.", imgui.autoRefillGauge, 0, 200) then
                if imgui.autoRefillGauge.v < 0 or imgui.autoRefillGauge.v > 200 then
                    imgui.autoRefillGauge.v = defaults.autoRefillGauge
                end
                ini.settings.autoRefillGauge = imgui.autoRefillGauge.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if not ini.settings.autoRefill then
                imgui.PopStyleColor()
            end
            imgui.NewLine()
            if
                imgui.Checkbox(
                    "Обновлять метку на карте если клиент поблизости",
                    imgui.ImBool(ini.settings.updateOrderMark)
                )
             then
                ini.settings.updateOrderMark = not ini.settings.updateOrderMark
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Изменять clist на рабочий цвет:", imgui.ImBool(ini.settings.autoClist)) then
                ini.settings.autoClist = not ini.settings.autoClist
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.SameLine()
            imgui.PushItemWidth(toScreenX(65))
            if imgui.Combo("##Combo", imgui.workClist, COLOR_LIST) then
                ini.settings.workClist = imgui.workClist.v
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Показывать на карте игроков в транспорте", imgui.ImBool(ini.settings.markers)) then
                ini.settings.markers = not ini.settings.markers
                inicfg.save(ini, "Taximate/settings.ini")
            end
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 0, 0, 1))
            imgui.SetTooltip("Функция даёт преимущество над игроками\nИспользовать на свой страх и риск", 150)
            imgui.PopStyleColor()
            if imgui.Checkbox("Закончить рабочий день при поломке/пустом баке", imgui.ImBool(ini.settings.finishWork)) then
                ini.settings.finishWork = not ini.settings.finishWork
                inicfg.save(ini, "Taximate/settings.ini")
            end
            if imgui.Checkbox("Совместимость с FastMap", imgui.ImBool(ini.settings.fastMapCompatibility)) then
                ini.settings.fastMapCompatibility = not ini.settings.fastMapCompatibility
                inicfg.save(ini, "Taximate/settings.ini")
            end
        end
    elseif imgui.settingsTab == 2 then
        if imgui.Checkbox("Не принимать вызовы от игроков в списке", imgui.ImBool(ini.settings.blacklistIgnore)) then
            ini.settings.blacklistIgnore = not ini.settings.blacklistIgnore
            inicfg.save(ini, "Taximate/settings.ini")
        end
        if imgui.Checkbox("Скрывать вызовы от игроков в списке", imgui.ImBool(ini.settings.blacklistHide)) then
            ini.settings.blacklistHide = not ini.settings.blacklistHide
            inicfg.save(ini, "Taximate/settings.ini")
        end
        imgui.PushItemWidth(toScreenX(138))
        imgui.InputText("##blacklistName", imgui.blacklistName)
        imgui.PopItemWidth()
        imgui.SameLine()
        local bufferValue = imgui.blacklistName.v
        if imgui.Button("Добавить строку", vec(50, 10)) and not blacklist.players[bufferValue] then
            if
                bufferValue:find("^[%w_%?%*]+$") and #bufferValue < 25 and #bufferValue > 1 and
                    tonumber(bufferValue) == nil
             then
                blacklist.players[bufferValue] = {
                    active = true,
                    buffer = imgui.ImBuffer(25),
                    edit = false,
                    date = os.time(os.date("!*t"))
                }
                blacklist.players[bufferValue].buffer.v = bufferValue
                blacklist.save()
            end
        end
        imgui.TextDisabled("Поддерживаются символы подстановки «?» и «*»")
        imgui.TextDisabled("? - любой одиночный символ, * - любой набор символов (включая пустой)")
        imgui.TextDisabled("Команда для добавления/удаления из списка: /tmbl [Nick_Name/id]")
        imgui.BeginChild("blacklist", vec(190, 87.5), true)
        for id, nickname in pairs(blacklist.sortedNicknames) do
            record = blacklist.players[nickname]
            if record then
                if imgui.Checkbox("##" .. nickname, imgui.ImBool(record.active)) then
                    record.active = not record.active
                    blacklist.save()
                end
                imgui.SameLine()
                if not record.edit then
                    imgui.Text(nickname)
                    imgui.SameLine()
                    imgui.PushID(id)
                    if imgui.Button("+", vec(6, 9)) then
                        record.edit = true
                        for _nickname, _record in pairs(blacklist.players) do
                            if nickname ~= _nickname then
                                _record.edit = false
                            end
                        end
                    end
                    imgui.PopID(id)
                else
                    imgui.PushItemWidth(toScreenX(88))
                    imgui.PushID(id)
                    imgui.InputText("##" .. id, record.buffer)
                    imgui.PopID(id)
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.PushID(id)
                    if imgui.Button("Удалить", vec(43, 10)) then
                        blacklist.players[nickname] = nil
                        blacklist.save()
                    end
                    imgui.PopID(id)
                    imgui.SameLine()
                    imgui.PushID(id)
                    if imgui.Button("Сохранить", vec(40, 10)) then
                        local bufferValue = record.buffer.v
                        if
                            bufferValue:find("^[%w_%?%*]+$") and #bufferValue < 25 and #bufferValue > 1 and
                                tonumber(bufferValue) == nil
                         then
                            if record.buffer.v ~= nickname then
                                blacklist.players[nickname] = nil
                                blacklist.players[bufferValue] = {
                                    active = record.active,
                                    buffer = record.buffer,
                                    edit = false,
                                    date = record.date
                                }
                                blacklist.save()
                            else
                                record.edit = false
                            end
                        end
                    end
                    imgui.PopID(id)
                end
            end
        end
        imgui.EndChild()
    elseif imgui.settingsTab == 3 then
        if imgui.Checkbox("Автоматическая проверка обновлений", imgui.ImBool(ini.settings.checkUpdates)) then
            ini.settings.checkUpdates = not ini.settings.checkUpdates
            inicfg.save(ini, "Taximate/settings.ini")
        end
        imgui.SetTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
        if imgui.Button("Проверить обновления") then
            checkUpdates()
        end
        imgui.SetTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
        imgui.SameLine()
        if script_updates.update then
            if imgui.Button("Скачать новую версию") then
                update()
            end
        else
            imgui.Text("Обновления отсутствуют")
        end
        imgui.SetTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
        if imgui.Button("Перезапустить скрипт") then
            thisScript():reload()
        end
        imgui.Text("Связь:")
        imgui.SameLine()
        if imgui.Button("GitHub") then
            os.execute("start https://github.com/21se/Taximate/issues/new")
        end
        imgui.SameLine()
        if imgui.Button("VK") then
            os.execute("start https://vk.com/id387503690")
        end
        imgui.Text("История обновлений")
        imgui.BeginChild("changelog", vec(190, 95), true)
        if script_updates.changelog then
            for index, key in pairs(script_updates.sorted_keys) do
                if imgui.CollapsingHeader("Версия " .. key) then
                    imgui.PushTextWrapPos(toScreenX(185))
                    imgui.Text(script_updates.changelog[key])
                    imgui.PopTextWrapPos()
                end
            end
        else
            imgui.Text(
                "История обновлений недоступна...\nАнтистиллеры и прочие скрипты могут блокировать проверку обновлений"
            )
        end
        imgui.EndChild()
    end
    imgui.EndChild()
    imgui.End()
end

function imgui.addNotification(text, time, addSize)
    notificationsQueue[#notificationsQueue + 1] = {
        active = false,
        time = 0,
        showtime = time,
        date = os.date("%X"),
        text = text,
        button = false,
        orderNickname = nil,
        addSize = addSize or 0
    }
end

function imgui.SetTooltip(text, width)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(toScreenX(width))
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

function imgui.addNotificationWithButton(text, time, _orderNickname, addSize)
    notificationsQueue[#notificationsQueue + 1] = {
        active = false,
        time = 0,
        showtime = time,
        date = os.date("%X"),
        text = text,
        button = true,
        orderNickname = _orderNickname,
        addSize = addSize or 0
    }
end

local zones = {
    ["Гараж [SF]"] = {x = -1960, y = 614.8281},
    ["Порт [SF]"] = {x = -1731.5, y = 118.919899},
    ["Come-A-Lot"] = {x = 2115.459717, y = 920.206421},
    ["Автошкола"] = {x = -2026.514404, y = -95.752701},
    ["Автосалон [SF] B/A"] = {x = -1638.35144, y = 1202.657227},
    ["Банк [LS]"] = {x = 1411.71875, y = -1699.705566},
    ["Клуб Amnesia"] = {x = 2507.358398, y = 1242.260132},
    ["Новости [LS]"] = {x = 1632.979248, y = -1712.134644},
    ["Spinybed"] = {x = 2169.407715, y = 2795.919189},
    ["Амму-нация [LV]"] = {x = 2154.377686, y = 935.150208},
    ["Ballas"] = {x = 2702.399414, y = -2003.425903},
    ["Ферма 2"] = {x = -1060.39856, y = -1205.524048},
    ["Julius"] = {x = 2640.000244, y = 1106.087646},
    ["Emerald Isle"] = {x = 2202.513672, y = 2474.13623},
    ["Грабители домов"] = {x = 2444.0413, y = -1971.8397},
    ["АВ/ЖД вокзал [SF]"] = {x = -1985.027222, y = 113.767799},
    ["Прием металла"] = {x = 2263.516846, y = -2537.962158},
    ["Yakuza"] = {x = 1538.84436, y = 2761.891602},
    ["Outlaws MC"] = {x = -309.605103, y = 1303.436035},
    ["Клуб Pig Pen"] = {x = 2417.153076, y = -1244.189941},
    ["Sobrino de Botin"] = {x = 2269.751465, y = -74.159599},
    ["Спортзал [LV]"] = {x = 2098.566895, y = 2480.085938},
    ["Ферма 4"] = {x = 1925.693237, y = 170.401703},
    ["Sons of Silence MC"] = {x = 1243.829102, y = 203.576202},
    ["Vinewood"] = {x = 1380.432251, y = -897.429016},
    ["Грабители ЛЭП"] = {x = 2285.899658, y = -2339.326904},
    ["Flats"] = {x = -2718.883301, y = 50.5322},
    ["Автосалон [SF] D/C"] = {x = -1987.325806, y = 288.925507},
    ["Easter"] = {x = -1675.596558, y = 413.487213},
    ["Grove street"] = {x = 2491.886963, y = -1666.881348},
    ["Пейнтбол"] = {x = 2488.860107, y = 2776.471191},
    ["Montgomery"] = {x = 1381.814453, y = 459.14801},
    ["La Cosa Nostra"] = {x = 1461.381958, y = 659.340027},
    ["Грузчики"] = {x = 2230.001709, y = -2211.310547},
    ["Больница [LV]"] = {x = 1607.858, y = 1820.549},
    ["Ферма 0"] = {x = -381.502808, y = -1438.979248},
    ["Warlocks MC"] = {x = 661.681824, y = 1717.991211},
    ["Мэрия"] = {x = 1481.229248, y = -1749.487305},
    ["ФБР"] = {x = -2418.072754, y = 497.657501},
    ["PricklePine"] = {x = 2147.674561, y = 2747.945313},
    ["Армия [LV]"] = {x = 133.322205, y = 1994.77356},
    ["Вертолет [LS]"] = {x = 1571.372192, y = -1335.252197},
    ["Черный рынок"] = {x = 2519.776367, y = -1272.694214},
    ["Бар Lil Probe Inn"] = {x = -89.612503, y = 1378.249268},
    ["BoneCounty"] = {x = 614.468323, y = 1692.853638},
    ["Магазин одежды [LV]"] = {x = 2802.930664, y = 2430.718018},
    ["Стоянка электриков"] = {x = -84.297798, y = -1125.867188},
    ["Ферма 3"] = {x = -5.5959, y = 67.837303},
    ["Нефтезавод 1"] = {x = 256.26001, y = 1414.930054},
    ["Bandidos MC"] = {x = -1940.291016, y = 2380.227783},
    ["Авиашкола LV"] = {x = 1319.1371, y = 1249.5378},
    ["Аэропорт [SF]"] = {x = -1551.542847, y = -436.707214},
    ["Новости [SF]"] = {x = -2013.973755, y = 469.190094},
    ["Mulholland"] = {x = 1003.979614, y = -937.547302},
    ["Гора Чилиад"] = {x = -2231.874, y = -1739.619},
    ["Vagos"] = {x = 2803.55542, y = -1585.0625},
    ["Бар Big Spread Ranch"] = {x = 693.625305, y = 1967.683716},
    ["Vagos MC"] = {x = -315.249115, y = 1773.921875},
    ["Склад продуктов"] = {x = -502.780609, y = -553.796204},
    ["Магазин одежды [SF]"] = {x = -1694.672119, y = 951.845581},
    ["Церковь [SF]"] = {x = -1981.333252, y = 1117.466675},
    ["Angel Pine"] = {x = -2155.095215, y = -2460.37793},
    ["Лесопилка 2"] = {x = -1978.709961, y = -2435.139893},
    ["Торговая площадка"] = {x = -1939.609131, y = 555.069824},
    ["Santa Maria"] = {x = 331.410309, y = -1802.567505},
    ["Dillimore"] = {x = 655.649109, y = -564.918518},
    ["Порт [LS]"] = {x = 2507.131348, y = -2234.151855},
    ["AngelPine"] = {x = -2243.743896, y = -2560.55542},
    ["СТО [LS]"] = {x = 854.575928, y = -605.205322},
    ["Бар Misty"] = {x = -2246.219482, y = -90.975998},
    ["Автоугонщики"] = {x = 2494.080078, y = -1464.709961},
    ["ЖД вокзал [LS]"] = {x = 1808.494507, y = -1896.349854},
    ["Автосалон [LS] Nope"] = {x = 557.109619, y = -1285.791626},
    ["Idlewood"] = {x = 1940.922241, y = -1772.977905},
    ["Склад урожая"] = {x = 1629.969971, y = 2326.031494},
    ["Перегон. Получение"] = {x = 2476.624756, y = -2596.437256},
    ["Аэропорт [LV]"] = {x = 1726.2912, y = 1610.0333},
    ["Магазин одежды [LS]"] = {x = 461.51239, y = -1500.866211},
    ["Клуб Alhambra"] = {x = 1827.609253, y = -1682.12207},
    ["Русская мафия"] = {x = 1001.480103, y = 1690.514526},
    ["Автобусный парк [LS]"] = {x = 1672.12, y = -1170.56},
    ["Автобусный парк [SF]"] = {x = -2306.51, y = -97.76},
    ["Автобусный парк [LV]"] = {x = 2568.63, y = 1402.62},
    ["Redsands West"] = {x = 1157.925537, y = 2072.282227},
    ["Marina Cluck"] = {x = 928.539917, y = -1352.939331},
    ["Полиция [LV]"] = {x = 2283.758789, y = 2420.525146},
    ["ElGuebrabos"] = {x = -1328.19751, y = 2677.596924},
    ["Redsands"] = {x = 1596.309814, y = 2199.004639},
    ["Банк [LV]"] = {x = 2412.57666, y = 1123.766235},
    ["Алкозавод"] = {x = -49.508301, y = -297.973602},
    ["Стадион [LV]"] = {x = 1099.208, y = 1600.952},
    ["Казино 4 Дракона"] = {x = 2327.4501, y = 2114.2021},
    ["Склад бара 4 Дракона"] = {x = 2225.8444, y = 2067.1940},
    ["Казино Belagio"] = {x = 2330.4199, y = 2166.1262},
    ["Стадион [LS]"] = {x = 2704.779053, y = -1701.145874},
    ["Tierra Robada"] = {x = -1471.741943, y = 1863.972412},
    ["Glen Park"] = {x = 1970.055, y = -1204.361},
    ["Garcia"] = {x = -2335.71875, y = -166.687805},
    ["Jefferson Motel"] = {x = 2228.676, y = -1161.456},
    ["Лесопилка 1"] = {x = -449.269897, y = -65.660004},
    ["Склад угля 2"] = {x = -2923.211, y = -1424.843},
    ["СТО [LV]"] = {x = 1658.380371, y = 2200.350342},
    ["Полиция [SF]"] = {x = -1607.410034, y = 723.03717},
    ["Marina Burger"] = {x = 810.51001, y = -1616.193848},
    ["Армия [SF]"] = {x = -1554.953613, y = 500.124207},
    ["Гараж [LV]"] = {x = 1447.29541, y = 2370.61499},
    ["Гараж [LS]"] = {x = 1636.65918, y = -1525.564209},
    ["Склад бара Калигула"] = {x = 2237.3657, y = 2230.6188},
    ["Вертолет [LV]"] = {x = 2614.588379, y = 2735.326416},
    ["СТО [SF]"] = {x = -1799.868042, y = 1200.299316},
    ["Больница [SF]"] = {x = -2658.259766, y = 627.981018},
    ["Willowfield"] = {x = 2397.851563, y = -1899.040039},
    ["Old Venturas Strip"] = {x = 2393.200684, y = 2041.559448},
    ["Strip"] = {x = 2083.269775, y = 2224.69751},
    ["Redsands East"] = {x = 1872.255249, y = 2071.863037},
    ["Whetstone"] = {x = -1605.54834, y = -2714.580322},
    ["Перегон. Сдача"] = {x = -1705.791138, y = 12.4111},
    ["Esplanade"] = {x = -1721.592529, y = 1360.345215},
    ["Financial"] = {x = -1807.485352, y = 944.666626},
    ["Нефтезавод 2"] = {x = -1046.780029, y = -670.650024},
    ["Palomino Creek"] = {x = 2250.245117, y = 52.701401},
    ["Comedy club"] = {x = 2506.8877, y = 2120.3816},
    ["Juniper"] = {x = -2410.803467, y = 975.240906},
    ["Наркопритон"] = {x = 2182.824707, y = -1669.634644},
    ["Амму-нация [SF]"] = {x = -2611.327393, y = 213.002808},
    ["Автосалон [LV] B/A"] = {x = 2159.575195, y = 1385.734131},
    ["Автосалон [SF] S"] = {x = -1754.2285, y = 964.1264},
    ["Бар Tierra Robada"] = {x = -2501.24292, y = 2318.692627},
    ["Flint"] = {x = -90.936501, y = -1169.390747},
    ["Банк [SF]"] = {x = -2226.506348, y = 251.924103},
    ["Военкомат"] = {x = -551.301514, y = 2593.905029},
    ["Склад угля 1"] = {x = 832.456787, y = 863.901611},
    ["Клуб Jizzy"] = {x = -2593.454834, y = 1362.782349},
    ["Fort Carson"] = {x = 61.247101, y = 1189.19104},
    ["Инкассаторы"] = {x = -2206.516113, y = 312.605194},
    ["Автовокзал [LS]"] = {x = 1143.750122, y = -1746.589111},
    ["Aztecas"] = {x = 1723.966553, y = -2112.802734},
    ["Полиция [LS]"] = {x = 1548.657715, y = -1675.47522},
    ["Hell's Angels MC"] = {x = 681.496521, y = -475.403198},
    ["Больница [LS]"] = {x = 1181.302, y = -1323.499},
    ["Кладбище [LS]"] = {x = 815.756226, y = -1103.168091},
    ["Дальнобойщики"] = {x = 2236.611816, y = 2770.693848},
    ["Новости [LV]"] = {x = 2617.3396, y = 1179.765137},
    ["Машины хот-догов"] = {x = -2407.622803, y = 741.159424},
    ["Стадион [SF]"] = {x = -2133.911133, y = -444.985199},
    ["Rifa"] = {x = 2184.550537, y = -1765.587158},
    ["Ферма 1"] = {x = -112.575401, y = -10.4236},
    ["АВ/ЖД вокзал [LV]"] = {x = 2843.035156, y = 1343.983032},
    ["Highwaymen MC"] = {x = 22.934, y = -2646.949219},
    ["Казино Калигула"] = {x = 2374.4543, y = 2168.7851},
    ["Амму-нация [LS]"] = {x = 1363.999512, y = -1288.82666},
    ["Кладбище самолётов"] = {x = 252.94, y = 2504.34},
    ["Mongols MC"] = {x = -1265.713867, y = 2716.588623},
    ["Pagans MC"] = {x = -2104.451904, y = -2481.883057},
    ["Free Souls MC"] = {x = -253.842606, y = 2603.138184},
    ["Вертолет [SF]"] = {x = -2241.166992, y = 2322.205566},
    ["Бар Grove street"] = {x = 2306.214355, y = -1651.560547},
    ["Аэрoпoрт [LS]"] = {x = 1967.20105, y = -2173.359375},
    ["Blueberry"] = {x = 193.50517272949, y = -149.43431091309},
    ["Fern Ridge"] = {x = 828.34381103516, y = 87.334922790527},
    ["Fort Carsоn"] = {x = -318.39666748047, y = 1059.1397705078},
    ["Garver Bridge"] = {x = -1340.0278320313, y = 896.04992675781},
    ["Las Barrancas"] = {x = -783.38702392578, y = 1542.9613037109},
    ["Дамба Шермана"] = {x = -688.28234863281, y = 2057.3684082031},
    ["Las Brujas"] = {x = -389.77297973633, y = 2224.3134765625},
    ["Gant Bridge"] = {x = -2678, y = 1844.75},
    ["Missionary Hill"] = {x = -2412, y = -594.2333984375},
    ["Маяк [LS]"] = {x = 167.46875, y = -1941.484375},
    ["Fort Cаrson"] = {x = -87.913604736328, y = 896.2822265625},
    ["Перекрёсток LV-LS"] = {x = 1792.2270507813, y = 842.9541015625},
    ["Причал [LV]"] = {x = 2314, y = 573.0322265625},
    ["Колесо обозрения"] = {
        x = 371.21142578125,
        y = -2036.2333984375
    },
    ["Vinewoоd"] = {x = 217.96139526367, y = -1269.2333984375},
    ["Back O Beyond"] = {x = -652.17919921875, y = -2188},
    ["Стоянка такси [LV]"] = {
        x = 2448.4223632813,
        y = 1337.5726318359
    },
    ["Northstar Rock"] = {x = 2272, y = -507.87426757813},
    ["Vinewоod"] = {x = 1404, y = -686.48815917969},
    ["Лодочная станция"] = {
        x = 730.087890625,
        y = -1667.2354736328
    },
    ["Обсерватория"] = {x = 1108.71875, y = -2032.654296875},
    ["Причал Tierra Robada"] = {x = -2704.2709, y = 2367.1948},
    ["Аэропорт [LS]"] = {x = 1684, y = -2531.5048828125},
    ["Армия [LS]"] = {x = 2734, y = -2449.25},
    ["Стоянка такси [SF]"] = {
        x = -2267.4973144531,
        y = 123.14111328125
    },
    ["Foster Valley"] = {x = -1922.984375, y = -938.43969726563},
    ["Shady Creeks"] = {x = -1655.234375, y = -1922.6591796875},
    ["Las Colinas"] = {x = 2566, y = -1054.6638183594},
    ["Офис SF [B] I"] = {x = -2067.65, y = -962.38},
    ["Офис SF [B] II"] = {x = -2067.65, y = -911.11},
    ["Офис SF [B] III"] = {x = -2067.65, y = -859.85},
    ["Офис SF [B] IV"] = {x = -2067.65, y = -808.59},
    ["Офис SF [B] V"] = {x = -2067.65, y = -757.33},
    ["Офис LV [A] Elite"] = {x = 2461.47, y = 2245.14},
    ["Офис LS [C] Classic"] = {x = 1429.97, y = -1481.61},
    ["Магазин садовода"] = {x = -2579.77, y = 310.06},
    ["Склад фруктов"] = {x = 969.73, y = 2160.69},
    ["Скотобаза"] = {x = 984.53, y = 2073.18},
    ["Ферма коров"] = {x = -1094.28, y = -1660.17},
    ["Раста магазин"] = {x = -2490.31, y = -16.91},
    ["Магазин аксессуаров"] = {x = -1882.39, y = 866.40},
    ["Тренинг центр"] = {x = 1616.18, y = -1897.56},
    ["Военный музей"] = {x = 1029.46, y = 1135.63},
    ["Суд"] = {x = -2766.55, y = 375.71},
    ["Pershing Square"] = {x = 1411.71, y = -1699.70},
    ["Kings"] = {x = -2059.21, y = 354.39},
    ["Roca Escalante"] = {x = 2447.68, y = 2376.24},
    ["Market"] = {x = 1015.19, y = -1508.75},
    ["Bayside"] = {x = -2510.86, y = 2276.93},
    ["Игра в Кальмара"] = {x = 1459.40, y = -1009.92}
}

function getZone(x, y)
    local minDist = 10000
    local findZone = "Неизвестно"
    for zone, pos in pairs(zones) do
        local dist = getDistanceBetweenCoords2d(x, y, pos.x, pos.y)
        if dist < minDist then
            minDist = dist
            findZone = zone
        end
    end
    return findZone
end

function imgui.ApplyCustomStyle()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    style.WindowRounding = toScreenX(2.0)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.ChildWindowRounding = toScreenX(2.0)
    style.FrameRounding = toScreenX(2.0)
    style.ScrollbarSize = toScreenX(4.3)
    style.ScrollbarRounding = toScreenX(2.0)
    style.GrabMinSize = toScreenX(2.0)
    style.GrabRounding = toScreenX(1.0)
    style.WindowPadding = vec(2.5, 2.5)
    style.FramePadding = vec(1, 1)
    style.ItemSpacing = vec(2, 2)
    style.ItemInnerSpacing = vec(2, 2)
    style.IndentSpacing = toScreenX(0)
    style.TouchExtraPadding = vec(0, 0)
    style.ColumnsMinSpacing = toScreenX(0)
    style.DisplayWindowPadding = vec(0, 0)
    style.DisplaySafeAreaPadding = vec(0, 0)

    colors[clr.Text] = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.TextDisabled] = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[clr.WindowBg] = ImVec4(0.06, 0.06, 0.06, 0.94)
    colors[clr.ChildWindowBg] = ImVec4(1.00, 1.00, 1.00, 0.00)
    colors[clr.PopupBg] = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[clr.ComboBg] = colors[clr.PopupBg]
    colors[clr.Border] = ImVec4(0.43, 0.43, 0.50, 0.50)
    colors[clr.BorderShadow] = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.FrameBg] = ImVec4(0.16, 0.29, 0.48, 0.54)
    colors[clr.FrameBgHovered] = ImVec4(0.26, 0.59, 0.98, 0.40)
    colors[clr.FrameBgActive] = ImVec4(0.26, 0.59, 0.98, 0.67)
    colors[clr.TitleBg] = ImVec4(0.16, 0.29, 0.48, 1.00)
    colors[clr.TitleBgActive] = colors[clr.TitleBg]
    colors[clr.TitleBgCollapsed] = ImVec4(0.00, 0.00, 0.00, 0.51)
    colors[clr.MenuBarBg] = ImVec4(0.14, 0.14, 0.14, 1.00)
    colors[clr.ScrollbarBg] = ImVec4(0.02, 0.02, 0.02, 0.53)
    colors[clr.ScrollbarGrab] = ImVec4(0.31, 0.31, 0.31, 1.00)
    colors[clr.ScrollbarGrabHovered] = ImVec4(0.41, 0.41, 0.41, 1.00)
    colors[clr.ScrollbarGrabActive] = ImVec4(0.51, 0.51, 0.51, 1.00)
    colors[clr.CheckMark] = ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[clr.SliderGrab] = ImVec4(0.24, 0.52, 0.88, 1.00)
    colors[clr.SliderGrabActive] = colors[clr.CheckMark]
    colors[clr.Button] = colors[clr.FrameBgHovered]
    colors[clr.ButtonHovered] = colors[clr.CheckMark]
    colors[clr.ButtonActive] = ImVec4(0.06, 0.53, 0.98, 1.00)
    colors[clr.Header] = ImVec4(0.26, 0.59, 0.98, 0.31)
    colors[clr.HeaderHovered] = ImVec4(0.26, 0.59, 0.98, 0.80)
    colors[clr.HeaderActive] = colors[clr.CheckMark]
    colors[clr.Separator] = colors[clr.Border]
    colors[clr.SeparatorHovered] = ImVec4(0.26, 0.59, 0.98, 0.78)
    colors[clr.SeparatorActive] = colors[clr.CheckMark]
    colors[clr.ResizeGrip] = ImVec4(0.26, 0.59, 0.98, 0.25)
    colors[clr.ResizeGripHovered] = colors[clr.FrameBgActive]
    colors[clr.ResizeGripActive] = ImVec4(0.26, 0.59, 0.98, 0.95)
    colors[clr.CloseButton] = ImVec4(0.41, 0.41, 0.41, 0.50)
    colors[clr.CloseButtonHovered] = ImVec4(0.98, 0.39, 0.36, 1.00)
    colors[clr.CloseButtonActive] = colors[clr.CloseButtonHovered]
    colors[clr.PlotLines] = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered] = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[clr.PlotHistogram] = ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[clr.PlotHistogramHovered] = ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[clr.TextSelectedBg] = ImVec4(0.26, 0.59, 0.98, 0.35)
    colors[clr.ModalWindowDarkening] = ImVec4(0.80, 0.80, 0.80, 0.35)
end

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec4 = imgui.ImVec4

    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end

    local getcolor = function(color)
        if color:sub(1, 6):upper() == "SSSSSS" then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == "string" and tonumber(color, 16) or color
        if type(color) ~= "number" then
            return
        end
        local r, g, b, a = explode_argb(color)
        return imgui.ImColor(r, g, b, a):GetVec4()
    end

    local render_text = function(text_)
        for w in text_:gmatch("[^\r\n]+") do
            local text, colors_, m = {}, {}, 1
            w = w:gsub("{(......)}", "{%1FF}")
            while w:find("{........}") do
                local n, k = w:find("{........}")
                local color = getcolor(w:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
            end
            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], text[i])
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else
                imgui.Text(w)
            end
        end
    end

    render_text(text)
end

function sampev.onSetRaceCheckpoint(type, position)
    orders.GPSMark = {
        x = position.x,
        y = position.y,
        z = position.z,
        time = os.clock()
    }
end

function sampev.onDisableRaceCheckpoint()
    orders.GPSMark = nil
end

function onReceiveRpc(int, bit)
    if int == 56 then
        local bIconID = raknetBitStreamReadInt8(bit)
        local posX = raknetBitStreamReadFloat(bit)
        local posY = raknetBitStreamReadFloat(bit)
        local posZ = raknetBitStreamReadFloat(bit)
        local type = raknetBitStreamReadInt8(bit)
        local color = raknetBitStreamReadInt32(bit)
        local style = raknetBitStreamReadInt8(bit)
        
        if orders.currentOrder and type == 0 and color == -16776961 and style == 3 then
            orders.currentOrder.pos.x = posX
            orders.currentOrder.pos.y = posY
            orders.currentOrder.pos.z = posZ
            orders.currentOrder.zone = getZone(posX, posY)
            orders.currentOrder.distance =
                getDistanceToCoords3d(orders.currentOrder.pos.x, orders.currentOrder.pos.y, orders.currentOrder.pos.z)
            orders.currentOrder.currentDistance = orders.currentOrder.distance
            orders.currentOrder.showMark = true
        end
    end
end

function getGPSMarkCoords3d()
    wait(500)
    if orders.GPSMark then
        local found = os.clock() - orders.GPSMark.time <= 5
        return found, orders.GPSMark.x, orders.GPSMark.y, orders.GPSMark.z
    end
    return false
end

function getPlayerIdByNickname(Nickname)
    for id = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(id) then
            if sampGetPlayerNickname(id) == tostring(Nickname) then
                return id
            end
        end
    end
end

function toScreenY(gY)
    local x, y = convertGameScreenCoordsToWindowScreenCoords(0, gY)
    return y
end

function toScreenX(gX)
    local x, y = convertGameScreenCoordsToWindowScreenCoords(gX, 0)
    return x
end

function vec(gX, gY)
    local x, y = convertGameScreenCoordsToWindowScreenCoords(gX, gY)
    return imgui.ImVec2(x, y)
end

function getDistanceToCoords3d(posX, posY, posZ)
    local charPosX, charPosY, charPosZ = getCharCoordinates(PLAYER_PED)
    local distance = math.ceil(getDistanceBetweenCoords3d(charPosX, charPosY, charPosZ, posX, posY, posZ))
    return distance
end

function checkUpdates(verbose)
    if verbose == nil then
        verbose = true
    end
    local fpath = os.tmpname()
    if doesFileExist(fpath) then
        os.remove(fpath)
    end
    downloadUrlToFile(
        "https://raw.githubusercontent.com/21se/Taximate/" .. script_branch .. "/version.json",
        fpath,
        function(_, status, _, _)
            if status == moonloader.download_status.STATUSEX_ENDDOWNLOAD then
                if not doesFileExist(fpath) then
                    return false
                end
                local file = io.open(fpath, "r")
                if not file then
                    return false
                end
                script_updates = decodeJson(file:read("*a"))
                script_updates.update_from_version_num = thisScript().version_num
                script_updates.sorted_keys = {}
                if script_updates.changelog then
                    for key in pairs(script_updates.changelog) do
                        table.insert(script_updates.sorted_keys, key)
                    end
                    table.sort(
                        script_updates.sorted_keys,
                        function(a, b)
                            return a > b
                        end
                    )
                end
                file:close()
                os.remove(fpath)
                if script_updates.version_num > thisScript().version_num then
                    if verbose then
                        chat.sendMessage(
                            "Доступен {00CED1}Taximate v" ..
                                script_updates.sorted_keys[1] ..
                                    "{FFFFFF}. Введите {00CED1}'/tmup'{FFFFFF} чтобы скачать обновление"
                        )
                    end
                    script_updates.update = true
                    return true
                end
            end
        end
    )
end

local PressType = {KeyDown = isKeyDown, KeyPressed = wasKeyPressed}
function keycheck(k)
    local r = true
    for i = 1, #k.k do
        r = r and PressType[k.t[i]](k.k[i])
    end
    return r
end

function isKeysPressed(key, addKey, hold)
    if hold then
        return (isKeyDown(key) and addKey == 0) or (isKeyDown(key) and isKeyDown(addKey))
    end
    if addKey == 0 then
        return isKeyJustPressed(key)
    end
    return keycheck({k = {key, addKey}, t = {"KeyDown", "KeyPressed"}})
end

function update()
    if script_updates.update then
        chat.sendMessage("Выполняется обновление...")
        local fpath = os.tmpname()
        if doesFileExist(fpath) then
            os.remove(fpath)
        end
        downloadUrlToFile(
            "https://raw.githubusercontent.com/21se/Taximate/" .. script_branch .. "/taximate.lua",
            fpath,
            function(_, status, _, _)
                if status == moonloader.download_status.STATUS_ENDDOWNLOADDATA then
                    local fail = false
                    try(
                        function()
                            os.copy(thisScript().path, thisScript().path .. "old")
                            local scriptFile = io.open(fpath, "r")
                            if not scriptFile then
                                fail = true
                                print("{f44331}При попытке обновления произошла ошибка: не удалось открыть файл")
                                return
                            end
                            loadChangesFromFile(scriptFile)
                            scriptFile:close()
                            applyChanges(thisScript().version_num) -- applyChanges from scriptFile
                            os.move(fpath, thisScript().path)
                            os.remove(thisScript().path .. "old")
                        end,
                        function(e)
                            fail = true
                            os.move(thisScript().path .. "old", thisScript().path)
                            print("{f44331}При попытке обновления произошла ошибка: " .. e)
                        end
                    )
                    if not fail then
                        chat.sendMessage(
                            "Скрипт обновлён. В случае возникновения ошибок обращаться в ВК - {00CED1}vk.com/id387503690{FFFFFF}"
                        )
                    else
                        chat.sendMessage(
                            "{f44331}При попытке обновления произошла ошибка.{FFFFFF} Обратитесь в ВК - {00CED1}vk.com/id387503690{FFFFFF}"
                        )
                    end
                    if script.find("ML-AutoReboot") == nil and not fail then
                        thisScript():reload()
                    end
                end
            end
        )
    else
        chat.sendMessage("Обновления не найдены, возможно скрипт не получил выход в Интернет")
    end
end

function loadChangesFromFile(scriptFile)
    local text = u8:decode(scriptFile:read("*a"))
    if text:find("\n%-%- applyChanges\n.+\n%-%- applyChanges\n") then
        for changes in text:gmatch("\n%-%- applyChanges\n(.+)\n%-%- applyChanges\n") do
            text = changes
            break
        end
        load(text)()
    end
end

-- applyChanges
function applyChanges(version_num)
    -- if version_num < 53 then
    -- end
end
-- applyChanges

function try(f, catch_f)
    local status, exception = pcall(f)
    if not status then
        catch_f(exception)
    end
end

local find = string.find
function string.find(s, pattern)
    return find(s, u8:decode(pattern))
end

local match = string.match
function string.match(s, pattern)
    return match(s, u8:decode(pattern))
end

local gmatch = string.gmatch
function string.gmatch(s, pattern)
    return gmatch(s, u8:decode(pattern))
end

function os.copy(source, path)
    local infile = io.open(source, "r")
    local instr = infile:read("*a")
    infile:close()

    local outfile = io.open(path, "w")
    outfile:write(instr)
    outfile:close()
end

function os.move(source, path)
    os.copy(source, path)
    os.remove(source)
end

-- utf8lib
function utf8charbytes(s, i)
    -- argument defaults
    i = i or 1

    -- argument checking
    if type(s) ~= "string" then
        error("bad argument #1 to 'utf8charbytes' (string expected, got " .. type(s) .. ")")
    end
    if type(i) ~= "number" then
        error("bad argument #2 to 'utf8charbytes' (number expected, got " .. type(i) .. ")")
    end

    local c = s:byte(i)

    -- determine bytes needed for character, based on RFC 3629
    -- validate byte 1
    if c > 0 and c <= 127 then
        -- UTF8-1
        return 1
    elseif c >= 194 and c <= 223 then
        -- UTF8-2
        local c2 = s:byte(i + 1)

        if not c2 then
            error("UTF-8 string terminated early")
        end

        -- validate byte 2
        if c2 < 128 or c2 > 191 then
            error("Invalid UTF-8 character")
        end

        return 2
    elseif c >= 224 and c <= 239 then
        -- UTF8-3
        local c2 = s:byte(i + 1)
        local c3 = s:byte(i + 2)

        if not c2 or not c3 then
            error("UTF-8 string terminated early")
        end

        -- validate byte 2
        if c == 224 and (c2 < 160 or c2 > 191) then
            error("Invalid UTF-8 character")
        elseif c == 237 and (c2 < 128 or c2 > 159) then
            error("Invalid UTF-8 character")
        elseif c2 < 128 or c2 > 191 then
            error("Invalid UTF-8 character")
        end

        -- validate byte 3
        if c3 < 128 or c3 > 191 then
            error("Invalid UTF-8 character")
        end

        return 3
    elseif c >= 240 and c <= 244 then
        -- UTF8-4
        local c2 = s:byte(i + 1)
        local c3 = s:byte(i + 2)
        local c4 = s:byte(i + 3)

        if not c2 or not c3 or not c4 then
            error("UTF-8 string terminated early")
        end

        -- validate byte 2
        if c == 240 and (c2 < 144 or c2 > 191) then
            error("Invalid UTF-8 character")
        elseif c == 244 and (c2 < 128 or c2 > 143) then
            error("Invalid UTF-8 character")
        elseif c2 < 128 or c2 > 191 then
            error("Invalid UTF-8 character")
        end

        -- validate byte 3
        if c3 < 128 or c3 > 191 then
            error("Invalid UTF-8 character")
        end

        -- validate byte 4
        if c4 < 128 or c4 > 191 then
            error("Invalid UTF-8 character")
        end

        return 4
    else
        error("Invalid UTF-8 character")
    end
end

function utf8len(s)
    -- argument checking
    if type(s) ~= "string" then
        error("bad argument #1 to 'utf8len' (string expected, got " .. type(s) .. ")")
    end

    local pos = 1
    local bytes = s:len()
    local len = 0

    while pos <= bytes do
        len = len + 1
        pos = pos + utf8charbytes(s, pos)
    end

    return len
end

function utf8sub(s, i, j)
    -- argument defaults
    j = j or -1

    local pos = 1
    local bytes = s:len()
    local len = 0

    -- only set l if i or j is negative
    local l = (i >= 0 and j >= 0) or s:utf8len()
    local startChar = (i >= 0) and i or l + i + 1
    local endChar = (j >= 0) and j or l + j + 1

    -- can"t have start before end!
    if startChar > endChar then
        return ""
    end

    -- byte offsets to pass to string.sub
    local startByte, endByte = 1, bytes

    while pos <= bytes do
        len = len + 1

        if len == startChar then
            startByte = pos
        end

        pos = pos + utf8charbytes(s, pos)

        if len == endChar then
            endByte = pos - 1
            break
        end
    end

    return s:sub(startByte, endByte), startByte, endByte
end