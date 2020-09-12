script_name('Taximate')
script_author("21se(pivo)")
script_version('1.3.0 dev')
script_version_number(32)
script_url("https://21se.github.io/Taximate")
script_updates = {}
script_updates.update = false

-- TODO: дополнить метки на карте, автопррием заправки починки
--       /seeme /seedo

local inicfg = require 'inicfg'
local ini = {}
local sampev = require 'lib.samp.events'
local vkeys = require 'lib.vkeys'
local imgui = require 'imgui'
local as_action = require 'moonloader'.audiostream_state
local encoding = require 'encoding'
			encoding.default = 'CP1251'
local u8 = encoding.UTF8
local notificationsQueue = {}
local fastMapKey = 0

local MAX_PASSENGERS = {
	DEFAULT = 3,
	BUFFALO = 1
}

local VEHICLE_MODEL_IDS = {
	["Premier"] = 420,
	["Cabbie"] = 438,
	["Sentinel"] = 405,
	["Sultan"] = 560,
	["Buffalo"] = 402
}

local INPUT_MESSAGES = {
	newOrder = u8:decode"^ Диспетчер: вызов от [a-zA-Z0-9_]+%[%d+%]. Примерное расстояние .+м$",
	orderAccepted = u8:decode"^ Диспетчер: [a-zA-Z0-9_]+ принял вызов от [a-zA-Z0-9_]+%[%d+%]$",
	payCheck = u8:decode("^ Вы заработали .+ вирт. Деньги будут зачислены на ваш банковский счет в .+$")
}

local FORMAT_INPUT_MESSAGES = {
	newOrder = u8:decode"^ Диспетчер: вызов от (.+)%[(%d+)%]. Примерное расстояние (.+)$",
	orderAccepted = u8:decode"^ Диспетчер: (.+) принял вызов от (.+)%[%d+%]$",
	payCheck = u8:decode"^ Вы заработали (.+) / (.+) вирт. Деньги будут зачислены на ваш банковский счет в .+$"
}

local REMOVE_INPUT_MESSAGES = {
	serviceNotice = u8:decode"^ %(%( Введите '/service' чтобы принять вызов %)%)$"
}

local FORMAT_TAXI_SMS = {
	onWay = "/sms %d [Taxi] Жёлтый %s в пути. Дистанция: %d м",
	arrived = "/sms %d [Taxi] Жёлтый %s прибыл на место вызова"
}

local FORMAT_NOTIFICATIONS = {
	newOrder = "Вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s {FFFFFF}м",
	newOrderPos = "Вызов от {4296f9}%s[%s]\nДистанция: {42ff96}%s {FFFFFF}м",
	newOrderNeg = "Вызов от {4296f9}%s[%s]\nДистанция: {d44331}%s {FFFFFF}м",
	orderAccepted = "Принят вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s {FFFFFF}м",
}


function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(100) end

	repeat
		wait(100)
		local _, playerID = sampGetPlayerIdByCharHandle(PLAYER_PED)
		player.nickname = sampGetPlayerNickname(playerID)
		player.id = playerID
	until sampGetPlayerScore(player.id) ~= 0 and sampGetCurrentServerName() ~= 'Samp-Rp.Ru'

	server = sampGetCurrentServerName():gsub("|", "")
  server = (server:find("02") and "two" or (server:find("Revolution") and "revolution" or (server:find("Legacy") and "legacy" or (server:find("Classic") and "classic" or ""))))
  if server == "" then
    thisScript():unload()
		return
  end

	chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..']{FFFFFF} Меню настроек скрипта - {00CED1}/taximate{FFFFFF}, страница скрипта: {00CED1}'.. thisScript().url:gsub('https://', ''))

	if not doesDirectoryExist(getWorkingDirectory()..'\\config') then
		createDirectory(getWorkingDirectory()..'\\config')
	end
	if not doesDirectoryExist(getWorkingDirectory()..'\\config\\Taximate') then
		createDirectory(getWorkingDirectory()..'\\config\\Taximate')
	end
	ini = inicfg.load({settings = defaultSettings}, 'Taximate/settings.ini')
	imgui.initBuffers()
	soundManager.loadSound("new_order")
	soundManager.loadSound("correct_order")
	soundManager.loadSound("new_passenger")
	imgui.ApplyCustomStyle()
	imgui.GetIO().Fonts:Clear()
	imgui.GetIO().Fonts:AddFontFromFileTTF("C:\\Windows\\Fonts\\arial.ttf", 18/(1920/getScreenResolution()), nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
	imgui.RebuildFonts()
	imgui.Process = true
	chatManager.initQueue()
	player.refreshPlayerInfo()
	player.connected = true
	bindMenu.bindList = bindMenu.getBindList()
	lua_thread.create(bindMenu.bindsPressProcessingThread)
  lua_thread.create(chatManager.checkMessagesQueueThread)
	lua_thread.create(vehicleManager.refreshVehicleInfoThread)
	lua_thread.create(orderHandler.deleteUnacceptedOrdersThread)

	sampRegisterChatCommand("taximate", function() imgui.showSettings.v = not imgui.showSettings.v end)

	if ini.settings.checkUpdates then
		lua_thread.create(checkUpdates)
	end

	if doesFileExist(getGameDirectory()..'\\map.asi') and doesFileExist(getGameDirectory()..'\\map.ini') then
		local fastMap = inicfg.load(_, getGameDirectory()..'\\map.ini')
		fastMapKey = fastMap.MAP.key
		fastMap = nil
	end

	while true do
		wait(0)

		imgui.ShowCursor = false

		if player.onWork then
			local result, orderNickname, orderDistance, orderClock = orderHandler.getOrder()
			if result then
				orderHandler.handleOrder(orderNickname, orderDistance, orderClock)
			end

			orderHandler.autoAccept = table.isEmpty(vehicleManager.passengersList) and not orderHandler.currentOrder

			orderHandler.refreshCurrentOrder()

			if ini.settings.ordersDistanceUpdate then
				orderHandler.updateOrdersDistance()
			end

			if isKeysPressed(ini.settings.key3, ini.settings.key3add, false) and ini.settings.hotKeys then
				player.onWork = false
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist 0", true,true)
				end
				if orderHandler.currentOrder then
					orderHandler.cancelCurrentOrder()
				end
			end

			if isKeyJustPressed(vkeys.VK_2) then
				if vehicleManager.maxPassengers then
					chatManager.antifloodClock = os.clock()
				end
			end

			if not orderHandler.currentOrder then
				if orderHandler.lastCorrectOrderNickname then
					if isKeysPressed(ini.settings.key2, ini.settings.key2add, false) and ini.settings.hotKeys then
						orderHandler.acceptOrder(orderHandler.lastCorrectOrderNickname, orderHandler.lastCorrectOrderClock)
					end
				end
			else
				if isKeysPressed(ini.settings.key2, ini.settings.key2add, false) and ini.settings.hotKeys then
					orderHandler.cancelCurrentOrder()
				end
			end

		elseif orderHandler.currentOrder then
			orderHandler.cancelCurrentOrder()
		else
			orderHandler.autoAccept = false

			if isKeysPressed(ini.settings.key3, ini.settings.key3add, false) and ini.settings.hotKeys then
				player.onWork = true
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist "..ini.settings.workClist,true,true)
				end
			end
		end

		if ini.settings.markers then
			vehicleManager.drawMarkers()
		else
			vehicleManager.clearMarkers()
		end

	end
end

chatManager = {}
	chatManager.messagesQueue = {}
	chatManager.messagesQueueSize = 10
	chatManager.antifloodClock = os.clock()
	chatManager.lastMessage = ""
	chatManager.antifloodDelay = 0.6
	chatManager.hideResultMessages = {
		["/service"] = {bool = false, dialog = true},
		["/paycheck"] = {bool = false, dialog = false},
		["/clist"] = {bool = false, dialog = false},
		["/jskill"] = {bool = false, dialog = true},
		["/gps"] = {bool = false, dialog = true},
	}

  function chatManager.addChatMessage(message)
		sampAddChatMessage(u8:decode(tostring(message)), 0xFFFFFF)
	end

	function chatManager.updateAntifloodClock()
		chatManager.antifloodClock = os.clock()
		if string.sub(chatManager.lastMessage, 1, 4) == '/sms' then
			chatManager.antifloodClock = chatManager.antifloodClock + 0.5
		end
	end

	function chatManager.checkMessagesQueueThread()
		while true do
			wait(0)
			for messageIndex = 1, chatManager.messagesQueueSize do
				local message = chatManager.messagesQueue[messageIndex]
				if message.message ~= '' then
					if string.sub(chatManager.lastMessage, 1, 1) ~= '/' and string.sub(message.message, 1, 1) ~= '/' then
						chatManager.antifloodDelay = chatManager.antifloodDelay + 0.5
					end
					if os.clock() - chatManager.antifloodClock > chatManager.antifloodDelay then

						if string.find(message.message,'/service ac taxi') then
							player.acceptOrder = true
						end

						if message.hideResult then
							local command = string.match(message.message, "^(/[^ ]*).*")
							if chatManager.hideResultMessages[command] then
								chatManager.hideResultMessages[command].bool = not sampIsDialogActive() or not chatManager.hideResultMessages[command].dialog
							end
						end

						chatManager.lastMessage = u8:decode(message.message)
						sampSendChat(u8:decode(message.message))

						message.hideResult = false
						message.message = ''
					end
					chatManager.antifloodDelay = 0.6
				end
			end
		end
	end

	function chatManager.sendTaxiNotification(currentOrder)
		if ini.settings.sendSMS then
			if not currentOrder.arrived and currentOrder.showMark then
				if currentOrder.currentDistance < 30 then
					chatManager.addMessageToQueue(string.format(FORMAT_TAXI_SMS.arrived, currentOrder.id, vehicleManager.vehicleName))
					currentOrder.arrived = true
				elseif currentOrder.SMSClock < os.clock() and currentOrder.updateDistance then
					chatManager.addMessageToQueue(string.format(FORMAT_TAXI_SMS.onWay, currentOrder.id, vehicleManager.vehicleName, currentOrder.currentDistance))
					currentOrder.SMSClock = os.clock() + ini.settings.SMSTimer
					if currentOrder.pos.x == nil then
						currentOrder.updateDistance = false
					end
				end
			end
		end
	end

	function chatManager.handleInputMessage(message)
		lua_thread.create(function()
			if string.find(message, INPUT_MESSAGES.newOrder) and player.onWork then
				local time = os.clock()
				local nickname, id, distance = string.match(message, FORMAT_INPUT_MESSAGES.newOrder)
				distance = stringToMeters(distance)
				orderHandler.addOrder(nickname, id, distance, time)
			elseif string.find(message, INPUT_MESSAGES.orderAccepted) and player.onWork then
				local driverNickname, passengerNickname = string.match(message, FORMAT_INPUT_MESSAGES.orderAccepted)
				if driverNickname == player.nickname then
					if player.acceptOrder then
						player.acceptOrder = false
					end
					if orderHandler.currentOrder then
						if orderHandler.currentOrder.nickname ~= passengerNickname then
							if ini.settings.notifications and ini.settings.sounds then
								soundManager.playSound("new_order")
							end
							if ini.settings.notifications then
								imgui.addNotification(string.format(FORMAT_NOTIFICATIONS.orderAccepted, orderHandler.orderList[passengerNickname].nickname, orderHandler.orderList[passengerNickname].id, orderHandler.orderList[passengerNickname].distance), 10)
							end
						else
							orderHandler.currentOrder.repeatCount = orderHandler.currentOrder.repeatCount + 1

							orderHandler.updateMark()

						end
					elseif orderHandler.orderList[passengerNickname] then
						if ini.settings.notifications and ini.settings.sounds then
							soundManager.playSound("new_order")
						end
						if ini.settings.notifications then
							imgui.addNotification(string.format(FORMAT_NOTIFICATIONS.orderAccepted, orderHandler.orderList[passengerNickname].nickname, orderHandler.orderList[passengerNickname].id, orderHandler.orderList[passengerNickname].distance), 10)
						end
						orderHandler.currentOrder = orderHandler.orderList[passengerNickname]
						orderHandler.currentOrder.SMSClock = os.clock()

						orderHandler.updateMark()
					end
				end
				orderHandler.deleteOrder(passengerNickname)
			elseif string.find(message, u8:decode"^ '.+' помечено на карте красной меткой. Дистанция .+ метров$") and player.onWork then
				local text = "Метка на карте обновлена"
				local result, x, y= getGPSMarkCoords3d()
				if result then
					text = text .. '\nРайон: {4296f9}' .. getZone(x, y)
					if ini.settings.notifications and ini.settings.sounds then
						soundManager.playSound("correct_order")
					end
					if ini.settings.notifications then
						imgui.addNotification(text,5)
					end
				end
			elseif string.find(message, u8:decode"^ {00A86B}Используйте телефон {FFFFFF}%(%( /call %)%){00A86B} чтобы вызвать механика / таксиста$") and player.onWork and ini.settings.finishWork and not orderHandler.currentOrder then
				player.onWork = false
				if ini.settings.autoClist and chatManager.hideResultMessages["/clist"].bool then
					chatManager.addMessageToQueue("/clist 0", true, true)
				end
			elseif string.find(message, u8:decode"^ Пассажир вышел из такси. Использован купон на бесплатный проезд$") or string.find(message, u8:decode"^ Пассажир вышел из такси. Деньги будут зачислены во время зарплаты$") then
				player.refreshPlayerInfo()
			elseif string.find(message, u8:decode"^ Вы получили (%d+) вирт, от [a-zA-Z0-9_]+%[%d+%]$") then
				local sum, nickname = string.match(message, u8:decode"Вы получили (%d+) вирт, от (.+)%[")
				if table.contains(nickname, vehicleManager.lastPassengersList) then
					player.tips = player.tips + sum
				end
			elseif string.find(message, u8:decode"^--------===%[ КЛИЕНТ БАНКА SA %]===-------$") then
				player.tips = 0
				player.refreshPlayerInfo()
			elseif string.find(message, u8:decode"^ Не флуди!$") then
				chatManager.updateAntifloodClock()

				for qMessage in pairs(chatManager.hideResultMessages) do
					chatManager.hideResultMessages[qMessage].bool = false
				end

			end
		end)
	end

	function chatManager.initQueue()
		for messageIndex = 1, chatManager.messagesQueueSize do
			chatManager.messagesQueue[messageIndex] = {
				message = '',
				hideResult = false
			}
		end
	end

	function chatManager.addMessageToQueue(string, _nonRepeat, _hideResult)
		local isRepeat = false
		local nonRepeat = _nonRepeat or false
		local hideResult = _hideResult or false

		if nonRepeat then
			for messageIndex = 1, chatManager.messagesQueueSize do
				if string == chatManager.messagesQueue[messageIndex].message then
						isRepeat = true
				end
			end
		end

		if not isRepeat then
			for messageIndex = 1, chatManager.messagesQueueSize-1 do
				chatManager.messagesQueue[messageIndex].message =  chatManager.messagesQueue[messageIndex+1].message
				chatManager.messagesQueue[messageIndex].hideResult = chatManager.messagesQueue[messageIndex+1].hideResult
			end
			chatManager.messagesQueue[chatManager.messagesQueueSize].message = string
			chatManager.messagesQueue[chatManager.messagesQueueSize].hideResult = hideResult
		end
	end

orderHandler = {}
	orderHandler.orderList = {}

	orderHandler.autoAccept = false
	orderHandler.lastAcceptedOrderClock = os.clock()
	orderHandler.lastCorrectOrderNickname = nil
	orderHandler.lastCorrectOrderClock = os.clock()
	orderHandler.updateOrdersDistanceClock = os.clock()
	orderHandler.currentOrder = nil
	orderHandler.currentOrderBlip = nil
	orderHandler.currentOrderCheckpoint = nil

	function orderHandler.cancelCurrentOrder()
		if ini.settings.notifications and ini.settings.sounds then
			soundManager.playSound("correct_order")
		end
		if ini.settings.notifications then
			imgui.addNotification("Вызов отменён\nМетка на карте удалена",5)
		end
		if ini.settings.sendSMSCancel then
			chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Вызов отменён, закажите новое такси')
		end
		orderHandler.currentOrder = nil
		orderHandler.removeGPSMark()
	end

	function orderHandler.removeGPSMark()
		if orderHandler.currentOrderBlip then
			deleteCheckpoint(orderHandler.currentOrderCheckpoint)
			removeBlip(orderHandler.currentOrderBlip)
			orderHandler.currentOrderBlip = nil
			orderHandler.currentOrderCheckpoint = nil
		else
			chatManager.addMessageToQueue("/gps", true, true)
		end
	end

	function orderHandler.updateMark()
		local result, posX, posY, posZ = getGPSMarkCoords3d()
		if orderHandler.currentOrder and result then
			orderHandler.currentOrder.pos.x = posX
			orderHandler.currentOrder.pos.y = posY
			orderHandler.currentOrder.pos.z = posZ
			orderHandler.currentOrder.zone = getZone(posX, posY)
			orderHandler.currentOrder.distance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x,orderHandler.currentOrder.pos.y,orderHandler.currentOrder.pos.z)
			orderHandler.currentOrder.currentDistance = orderHandler.currentOrder.distance
			orderHandler.currentOrder.showMark = true
		end
	end

	function orderHandler.calculate2dCoords(circle1, circle2, circle3)
	  local dX = circle2.x - circle1.x
	  local dY = circle2.y - circle1.y

	  local d = math.sqrt((dY*dY) + (dX*dX))

		if d > (circle1.radius + circle2.radius) then
			return false
		end

		if d < math.abs(circle1.radius - circle2.radius) then
			return false
		end

	  local a = ((circle1.radius*circle1.radius) - (circle2.radius*circle2.radius) + (d*d)) / (2.0 * d)

	  local point2X = circle1.x + (dX * a/d)
	  local point2Y = circle1.y + (dY * a/d)

	  local h = math.sqrt((circle1.radius*circle1.radius) - (a*a))

	  local rX = -dY * (h/d)
	  local rY = dX * (h/d)

	  local intersectionPoint1X = point2X + rX
	  local intersectionPoint2X = point2X - rX
	  local intersectionPoint1Y = point2Y + rY
	  local intersectionPoint2Y = point2Y - rY

	  dX = intersectionPoint1X - circle3.x
	  dY = intersectionPoint1Y - circle3.y

	  local d1 = math.sqrt((dY*dY) + (dX*dX))

	  dX = intersectionPoint2X - circle3.x;
	  dY = intersectionPoint2Y - circle3.y;

	  local d2 = math.sqrt((dY*dY) + (dX*dX))

		if math.abs(d1 - circle3.radius) < math.abs(d2 - circle3.radius) then
			return true, intersectionPoint1X, intersectionPoint1Y
		else
			return true, intersectionPoint2X, intersectionPoint2Y
		end
	end

	function orderHandler.updateOrdersDistance()
		if vehicleManager.vehicleName then
			if orderHandler.updateOrdersDistanceClock < os.clock() then
				if not orderHandler.currentOrder then
					if not chatManager.hideResultMessages["/service"].bool then
						chatManager.addMessageToQueue("/service",true,true)
						orderHandler.updateOrdersDistanceClock = os.clock() + ini.settings.ordersDistanceUpdateTimer
					end
				end
			end
		end
	end

	function orderHandler.addOrder(_nickname, _id, _distance, _time)
		local posX, posY = getCharCoordinates(PLAYER_PED)
		orderHandler.orderList[_nickname] = {
			nickname = _nickname,
			id = _id,
			distance = _distance,
			pos = {
				x = nil,
				y = nil,
				z = nil
			},
			currentDistance = _distance,
			time = _time,
			correct = false,
			showMark = false,
			SMSClock = os.clock()-ini.settings.SMSTimer,
			arrived = false,
			updateDistance = true,
			repeatCount = 0,
			direction = 0,
			tempCircles = {{x = posX, y = posY, radius = _distance}, nil, nil},
			zone = "Неизвестно"
		}
	end

	function orderHandler.refreshCurrentOrder()
		if orderHandler.currentOrder then
			if sampIsPlayerConnected(orderHandler.currentOrder.id) and sampGetPlayerNickname(orderHandler.currentOrder.id)==orderHandler.currentOrder.nickname then
				if vehicleManager.maxPassengers then
					chatManager.sendTaxiNotification(orderHandler.currentOrder)
					local charInStream, charHandle = sampGetCharHandleBySampPlayerId(orderHandler.currentOrder.id)
					if charInStream and ini.settings.updateOrderMark then
						orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z = getCharCoordinates(charHandle)
						orderHandler.currentOrder.zone = getZone(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y)
						if orderHandler.currentOrder.showMark then
							if not orderHandler.currentOrderBlip then
								orderHandler.currentOrderBlip = addBlipForCoord(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
								changeBlipColour(orderHandler.currentOrderBlip, 0xBB0000FF)
								orderHandler.currentOrderCheckpoint = createCheckpoint(1, orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z, orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z, 2.99)
								chatManager.addMessageToQueue("/gps", true, true)
								if ini.settings.notifications then
									imgui.addNotification("Клиент поблизости\nМетка на карте обновлена",5)
								end
								if ini.settings.notifications and ini.settings.sounds then
									soundManager.playSound("correct_order")
								end
							else
								removeBlip(orderHandler.currentOrderBlip)
								orderHandler.currentOrderBlip = addBlipForCoord(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
								changeBlipColour(orderHandler.currentOrderBlip, 0xBB0000FF)
								setCheckpointCoords(orderHandler.currentOrderCheckpoint, orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
							end

							if orderHandler.currentOrderBlip then
								local distance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
								if distance <= 3 then
									removeBlip(orderHandler.currentOrderBlip)
									deleteCheckpoint(orderHandler.currentOrderCheckpoint)
									orderHandler.currentOrderBlip = nil
									orderHandler.currentOrderCheckpoint = nil
									orderHandler.currentOrder.showMark = false
								end
							end
						end
					end

					if orderHandler.currentOrder.pos.x then
						orderHandler.currentOrder.currentDistance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
						orderHandler.currentOrder.updateDistance = true
					end

					if vehicleManager.isPassengerInVehicle(vehicleManager.vehicleHandle, orderHandler.currentOrder.nickname) then
						orderHandler.currentOrder = nil
					end
				end
			else
				if ini.settings.notifications then
					imgui.addNotification("Клиент оффлайн\nВызов отменён",5)
				end
				if ini.settings.notifications and ini.settings.sounds then
					soundManager.playSound("correct_order")
				end
				orderHandler.currentOrder = nil
				orderHandler.removeGPSMark()
			end
		else
			removeBlip(orderHandler.currentOrderBlip)
			deleteCheckpoint(orderHandler.currentOrderCheckpoint)
			orderHandler.currentOrderBlip = nil
			orderHandler.currentOrderCheckpoint = nil
		end
	end

	function orderHandler.deleteOrder(nickname)
		orderHandler.orderList[nickname] = nil
	end

	function orderHandler.acceptOrder(nickname, orderClock)
		if orderHandler.orderList[nickname] then
			if orderClock then
				if orderHandler.lastAcceptedOrderClock ~= orderClock then
					if not player.acceptOrder then
						chatManager.addMessageToQueue("/service ac taxi "..orderHandler.orderList[nickname].id)
						orderHandler.lastAcceptedOrderClock = orderHandler.orderList[nickname].time
					end
				end
			end
		end
	end

	function orderHandler.deleteUnacceptedOrdersThread()
		while true do
			wait(0)
			for nickname, order in pairs(orderHandler.orderList) do
				if os.clock() - order.time > 600 or not sampIsPlayerConnected(order.id) or not sampGetPlayerNickname(order.id)==order.nickname then
					orderHandler.deleteOrder(nickname)
				end
			end
		end
	end

	function orderHandler.getOrder()
		for keyIndex, key in ipairs(table.getTableKeysSortedByValue(orderHandler.orderList, "time", false)) do
			if orderHandler.orderList[key] then
				return true, key, orderHandler.orderList[key].distance, orderHandler.orderList[key].time
			end
		end
		return false, nil, nil, nil
	end

	function orderHandler.handleOrder(orderNickname, orderDistance, orderClock)
		if not orderHandler.currentOrder  then
			if not table.contains(orderNickname, vehicleManager.lastPassengersList) or ini.settings.acceptLastPassengersOrders then
				if table.isEmpty(vehicleManager.passengersList) then
					if orderHandler.autoAccept then
						if orderDistance <= ini.settings.maxDistanceToAcceptOrder and os.clock() - 60 < orderClock then
							orderHandler.acceptOrder(orderNickname, orderClock)
						end
					else
						if orderDistance <= ini.settings.maxDistanceToGetOrder and os.clock() - 60 < orderClock then
							if not orderHandler.orderList[orderNickname].correct then
								orderHandler.orderList[orderNickname].correct = true
								if ini.settings.notifications and ini.settings.sounds then
									soundManager.playSound("correct_order")
								end
								if ini.settings.notifications then
									imgui.addNotificationWithButton(string.format(FORMAT_NOTIFICATIONS.newOrder, orderNickname, orderHandler.orderList[orderNickname].id, orderDistance, orderHandler.orderList[orderNickname].zone), 15, orderNickname)
								end
								orderHandler.lastCorrectOrderNickname = orderNickname
								orderHandler.lastCorrectOrderClock = os.clock()
							end
						end
					end
				else
					if orderDistance <= ini.settings.maxDistanceToGetOrder and os.clock() - 60 < orderClock then
						if not orderHandler.orderList[orderNickname].correct then
							orderHandler.orderList[orderNickname].correct = true
							if ini.settings.notifications and ini.settings.sounds then
								soundManager.playSound("correct_order")
							end
							if ini.settings.notifications then
								imgui.addNotificationWithButton(string.format(FORMAT_NOTIFICATIONS.newOrder, orderNickname, orderHandler.orderList[orderNickname].id, orderDistance, orderHandler.orderList[orderNickname].zone), 15, orderNickname)
							end
							orderHandler.lastCorrectOrderNickname = orderNickname
							orderHandler.lastCorrectOrderClock = os.clock()
						end
					end
				end
			end
		elseif orderNickname == orderHandler.currentOrder.nickname and ini.settings.acceptRepeatOrder and orderHandler.currentOrder.repeatCount < 3 then
			orderHandler.acceptOrder(orderNickname, orderClock)
		end
	end

vehicleManager = {}
	vehicleManager.lastPassengersList = {}
	vehicleManager.lastPassengersListSize = 3
	vehicleManager.passengersList = {}
	vehicleManager.maxPassengers = nil
	vehicleManager.vehicleName = nil
	vehicleManager.vehicleHandle = nil
	vehicleManager.markers = {}
	vehicleManager.GPSMark = nil

	function vehicleManager.refreshVehicleInfoThread()
		while true do
			wait(0)
			vehicleManager.vehicleName, vehicleManager.vehicleHandle, vehicleManager.maxPassengers = vehicleManager.getVehicleInfo()
			vehicleManager.refreshPassengersList()
		end
	end

	function vehicleManager.addLastPassenger(passengerNickname)
		local isPassengerInVehicle = false

		for passengerIndex = 1, vehicleManager.lastPassengersListSize do
			if passengerNickname == vehicleManager.lastPassengersList[passengerIndex] then
				isPassengerInVehicle = true
				break
			end
		end

		if not isPassengerInVehicle then
			for passengerindex = vehicleManager.lastPassengersListSize, 1, -1 do
				vehicleManager.lastPassengersList[passengerindex] = vehicleManager.lastPassengersList[passengerindex - 1]
			end
			vehicleManager.lastPassengersList[1] = passengerNickname
			if ini.settings.notifications and ini.settings.sounds then
				soundManager.playSound("new_passenger")
			end
		end
	end

	function vehicleManager.refreshPassengersList()
		if vehicleManager.maxPassengers then
			for passengerIndex = 0, vehicleManager.maxPassengers-1 do
				vehicleManager.passengersList[passengerIndex] = nil
			end

			for seatIndex = 0, vehicleManager.maxPassengers-1 do
				if not isCarPassengerSeatFree(vehicleManager.vehicleHandle, seatIndex) then
					local passengerHandle = getCharInCarPassengerSeat(vehicleManager.vehicleHandle, seatIndex)
					local result, passengerID = sampGetPlayerIdByCharHandle(passengerHandle)
					local passengerNickname = sampGetPlayerNickname(passengerID)
					vehicleManager.passengersList[seatIndex] = {
						nickname = passengerNickname,
						id = passengerID
					}
					vehicleManager.addLastPassenger(passengerNickname)
				end
			end

		end
	end

	function vehicleManager.getVehicleInfo()
		for vehicleName, vehicleModelID in pairs(VEHICLE_MODEL_IDS) do
			if isCharInModel(PLAYER_PED, vehicleModelID) then
				local vehicleHandle = storeCarCharIsInNoSave(PLAYER_PED)
				if PLAYER_PED == getDriverOfCar(vehicleHandle) then
					if vehicleManager.isTaxi(vehicleHandle) then
						local maxPassengers = vehicleManager.getMaxPassengers()
						return vehicleName, vehicleHandle, maxPassengers
					end
				end
			end
		end

		return nil, nil, nil
	end

	function vehicleManager.isTaxi(vehicleHandle)
		result, id = sampGetVehicleIdByCarHandle(vehicleHandle)
		if result then
			for textId = 0, 2048 do
				if sampIs3dTextDefined(textId) then
					string, _, _, _, _, _, _, _, vehicleId = sampGet3dTextInfoById(textId)
					if string.find(string, u8:decode'Бесплатное такси') and vehicleId == id then
						return true
					end
				end
			end
		end

		return false
	end

	function vehicleManager.isPassengerInVehicle(vehicleHandle, nickname)
		for seatIndex = 0, vehicleManager.maxPassengers-1 do
			if not isCarPassengerSeatFree(vehicleHandle, seatIndex) then
				local passengerHandle = getCharInCarPassengerSeat(vehicleHandle, seatIndex)
				local result, passengerID = sampGetPlayerIdByCharHandle(passengerHandle)
				local passengerNickname = sampGetPlayerNickname(passengerID)
				if nickname == passengerNickname then
					return true
				end
			end
		end
		return false
	end

	function vehicleManager.getMaxPassengers()
		if vehicleManager.vehicleName == "Buffalo" then
			return MAX_PASSENGERS.BUFFALO
		elseif vehicleManager.vehicleName then
			return MAX_PASSENGERS.DEFAULT
		else
			return nil
		end
	end

	function vehicleManager.drawMarkers()
		for id = 0, 999 do
			if sampIsPlayerConnected(id) then
				local charInStream, charHandle = sampGetCharHandleBySampPlayerId(id)
				if charInStream then
					if not vehicleManager.markers[id] then
						if isCharInAnyCar(charHandle) and sampGetPlayerColor(id) == 16777215 then
							vehicleManager.markers[id] = addBlipForChar(charHandle)
							changeBlipDisplay(vehicleManager.markers[id], 2)
							changeBlipColour(vehicleManager.markers[id], 0xFFFFFF25)
						end
					elseif not isCharInAnyCar(charHandle) or sampGetPlayerColor(id) ~= 16777215 then
							removeBlip(vehicleManager.markers[id])
							vehicleManager.markers[id] = nil
					end
				else
					if vehicleManager.markers[id] then
						removeBlip(vehicleManager.markers[id])
						vehicleManager.markers[id] = nil
					end
				end
			end
		end
	end

	function vehicleManager.clearMarkers()
		for id, marker in pairs(vehicleManager.markers) do
			removeBlip(marker)
			vehicleManager.markers[id] = nil
		end
	end

player = {}
	player.id = nil
	player.nickname = nil
	player.onWork = false
	player.skill = 1
	player.skillExp = 0
	player.rank = 1
	player.rankExp = 0
	player.salary = 0
	player.salaryLimit = 0
	player.tips = 0
	player.connected = false
	player.acceptOrder = false

	function player.refreshPlayerInfo()
		if not chatManager.hideResultMessages["/paycheck"].bool then
			chatManager.addMessageToQueue("/paycheck",true , true)
		end
		if not chatManager.hideResultMessages["/jskill"].bool then
			chatManager.addMessageToQueue("/jskill", true, true)
		end
	end

defaultSettings = {}
	defaultSettings.checkUpdates = true
	defaultSettings.showHUD = true
	defaultSettings.showBindMenu = true
	defaultSettings.sounds = true
	defaultSettings.notifications = true
	defaultSettings.sendSMS = true
	defaultSettings.sendSMSCancel = true
	defaultSettings.updateOrderMark = true
	defaultSettings.acceptRepeatOrder = true
	defaultSettings.autoClist = true
	defaultSettings.workClist = 25
	defaultSettings.acceptLastPassengersOrders = false
	defaultSettings.hotKeys = true
	defaultSettings.SMSTimer = 30
	defaultSettings.maxDistanceToAcceptOrder = 1400
	defaultSettings.maxDistanceToGetOrder = 1000
	defaultSettings.fastMapCompatibility = true
	defaultSettings.key1 = 88
	defaultSettings.key1add = 0
	defaultSettings.key2 = 16
	defaultSettings.key2add = 88
	defaultSettings.key3 = 88
	defaultSettings.key3add = 82
	defaultSettings.binderPosX = 36
	defaultSettings.binderPosY = 103
	defaultSettings.hudPosX = 498
	defaultSettings.hudPosY = 310
	defaultSettings.markers = true
	defaultSettings.ordersDistanceUpdate = true
	defaultSettings.ordersDistanceUpdateTimer = 3
	defaultSettings.soundVolume = 50
	defaultSettings.dispatcherMessages = true
	defaultSettings.finishWork = true

soundManager = {}
	soundManager.soundsList = {}

	function soundManager.loadSound(soundName)
		soundManager.soundsList[soundName] = loadAudioStream(getWorkingDirectory()..'\\rsc\\'..soundName..'.mp3')
	end

	function soundManager.playSound(soundName)
		if soundManager.soundsList[soundName] then
			setAudioStreamVolume(soundManager.soundsList[soundName], ini.settings.soundVolume/100)
			setAudioStreamState(soundManager.soundsList[soundName], as_action.PLAY)
		end
	end

bindMenu = {}
	bindMenu.bindList= {}
	bindMenu.json= {}
	bindMenu.defaultBinds = {
		{text = "Привет", key = 0, addKey =0},
		{text = "Куда едем?", key = 0, addKey =0},
		{text = "Спасибо", key = 0,addKey =0},
		{text = "Хорошо", key = 0, addKey =0},
		{text = "Удачи", key = 0, addKey =0},
		{text = "Да", key = 0, addKey =0},
		{text = "Нет", key = 0, addKey =0},
		{text = "))", key = 0, addKey =0},
		{text = "Почини", key = 0, addKey =0},
		{text = "Заправь", key = 0, addKey =0},
		{text = "/rkt", key = 0, addKey =0},
		{text = "/b Taximate: 21se.github.io/Taximate", key = 0, addKey = 0}
	}

	function bindMenu.getBindList()
		local list = {}

		local oldBinds = inicfg.load(nil, 'Taximate/binds.ini')

		if oldBinds then
			for index, bind in pairs(oldBinds) do
				if bind.text ~= "" then
					bindMenu.json[index] = {text = bind.text, key = bind.key, addKey = bind.keyadd}
				end
			end
			os.remove(getWorkingDirectory()..'\\config\\Taximate\\binds.ini')
			bindMenu.save()
		else
			local binds = io.open(getWorkingDirectory()..'\\config\\Taximate\\binds.json', "r")

	    if binds then
	        local content = binds:read("*a")
					bindMenu.json = decodeJson(content)
					binds:close()
	    else
					binds = io.open(getWorkingDirectory()..'\\config\\Taximate\\binds.json', "w")
					local content = encodeJson(bindMenu.defaultBinds)
	        binds:write(content)
					binds:close()
					bindMenu.json = bindMenu.defaultBinds
	    end
		end

		for index, bind in pairs(bindMenu.json)  do
			local _buffer = imgui.ImBuffer(128)
			_buffer.v = bind.text
			table.insert(list,{buffer = _buffer, key = bind.key, addKey =bind.addKey, edit = false})
		end

		return list
	end

	function bindMenu.deleteBind(bindIndex)
		for i = bindIndex, #bindMenu.json+1 do
			bindMenu.json[i] = bindMenu.json[i+1]
		end
		bindMenu.save()
	end


	function bindMenu.isBindEdit()
		for bindIndex, bind in pairs(bindMenu.bindList) do
			if bind.edit then
				return true
			end
		end
		return false
	end

	function bindMenu.save()
		binds = io.open(getWorkingDirectory()..'\\config\\Taximate\\binds.json', "w")
		local content = encodeJson(bindMenu.json)
		binds:write(content)
		binds:close()
	end

	function bindMenu.bindsPressProcessingThread()
		while true do
			wait(0)
			for index, bind in pairs(bindMenu.bindList) do
				if isKeysPressed(bind.key, bind.addKey, false) and not imgui.showInputWindow and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() and ini.settings.hotKeys then
				 chatManager.addMessageToQueue(bind.buffer.v)
			 	end
		 	end
		end
	end

function sampev.onShowDialog(DdialogId, Dstyle, Dtitle, Dbutton1, Dbutton2, Dtext)
	if player.connected then
		if Dstyle == 0 and string.find(Dtext, u8:decode"Таксист") then
			lua_thread.create(function()
				local line = 0
				for string in string.gmatch(Dtext, '[^\n]+') do
					line = line + 1
					if line == 5 then
						player.skill, player.skillExp = string.match(string, u8:decode"Скилл: (%d+)	Опыт: .+ (%d+%.%d+)%%")
					end
					if line == 6 then
						player.rank, player.rankExp = string.match(string, u8:decode"Ранг: (%d+)  	Опыт: .+ (%d+%.%d+)%%")
					end
				end
			end)
			if chatManager.hideResultMessages["/jskill"].bool then
				chatManager.hideResultMessages["/jskill"].bool = false
				return false
			end
		elseif string.find(Dtitle, "GPS") then
			if chatManager.hideResultMessages["/gps"].bool then
				chatManager.hideResultMessages["/gps"].bool = false
				return false
			else
				lua_thread.create(function()
					if orderHandler.currentOrderBlip then
						orderHandler.currentOrder.showMark = false
						removeBlip(orderHandler.currentOrderBlip)
						deleteCheckpoint(orderHandler.currentOrderCheckpoint)
						orderHandler.currentOrderBlip = nil
						orderHandler.currentOrderCheckpoint = nil
					end
				end)
			end
		elseif string.find(Dtitle, u8:decode"Вызовы") then
			lua_thread.create(function()
				for string in string.gmatch(Dtext, '[^\n]+') do
					local nickname, id, time, distance = string.match(string, u8:decode"%[%d+%] (.+)%[ID:(%d+)%]	(.+)	(.+)")
					time = stringToSeconds(time)
					distance = stringToMeters(distance)
					if orderHandler.orderList[nickname] then
						if distance < orderHandler.orderList[nickname].distance then
							orderHandler.orderList[nickname].direction = 1
						elseif distance > orderHandler.orderList[nickname].distance then
							orderHandler.orderList[nickname].direction = -1
						end
						orderHandler.orderList[nickname].distance = distance
						orderHandler.orderList[nickname].time = os.clock() - time
					else
						orderHandler.addOrder(nickname, id, distance, os.clock() - time)
					end

					local posX, posY = getCharCoordinates(PLAYER_PED)
					if not orderHandler.orderList[nickname].tempCircles[1] then
						orderHandler.orderList[nickname].tempCircles[1] = {x = posX, y = posY, radius = distance}
					elseif not orderHandler.orderList[nickname].tempCircles[2] then
						if math.abs(orderHandler.orderList[nickname].tempCircles[1].x - posX) > 15 or math.abs(orderHandler.orderList[nickname].tempCircles[1].y - posY) > 15 then
							orderHandler.orderList[nickname].tempCircles[2] = {x = posX, y = posY, radius = distance}
						end
					elseif not orderHandler.orderList[nickname].tempCircles[3] then
						if (math.abs(orderHandler.orderList[nickname].tempCircles[1].x - posX) > 15 or math.abs(orderHandler.orderList[nickname].tempCircles[1].y - posY) > 15) and
						(math.abs(orderHandler.orderList[nickname].tempCircles[2].x - posX) > 15 or math.abs(orderHandler.orderList[nickname].tempCircles[2].y - posY) > 15) then
							orderHandler.orderList[nickname].tempCircles[3] = {x = posX, y = posY, radius = distance}
							local result, calcX, calcY  = orderHandler.calculate2dCoords(orderHandler.orderList[nickname].tempCircles[1], orderHandler.orderList[nickname].tempCircles[2], orderHandler.orderList[nickname].tempCircles[3])
							if result then
								orderHandler.orderList[nickname].pos = {x = calcX, y = calcY, z = 30}
								orderHandler.orderList[nickname].zone = getZone(calcX, calcY)
							end

							orderHandler.orderList[nickname].tempCircles[1] = nil
							orderHandler.orderList[nickname].tempCircles[2] = nil
							orderHandler.orderList[nickname].tempCircles[3] = nil

						end
					end
				end
			end)
			if chatManager.hideResultMessages["/service"].bool then
				chatManager.hideResultMessages["/service"].bool = false
				return false
			end
		end
	end
end

function sampev.onServerMessage(color, message)
	if player.connected then
		if string.find(message, REMOVE_INPUT_MESSAGES.serviceNotice) then
			if not ini.settings.dispatcherMessages then
				return false
			end
		elseif string.find(message, INPUT_MESSAGES.payCheck) then
			player.salary, player.salaryLimit = string.match(message, FORMAT_INPUT_MESSAGES.payCheck)
			if not player.salary then
				player.salary = 0
				player.salaryLimit = 0
			end
			if chatManager.hideResultMessages["/paycheck"].bool then
				chatManager.hideResultMessages["/paycheck"].bool = false
				return false
			end
		elseif string.find(message, u8:decode" Цвет выбран") then
			if chatManager.hideResultMessages["/clist"].bool then
				chatManager.hideResultMessages["/clist"].bool = false
				return false
			end
		elseif string.find(message, u8:decode" Вызовов не поступало") or string.find(message, u8:decode" Введите: /service ") then
			if chatManager.hideResultMessages["/service"].bool then
				chatManager.hideResultMessages["/service"].bool = false
				return false
			end
		elseif string.find(message, u8:decode" Диспетчер: вызов от этого человека не поступал") then
			if player.acceptOrder then
				player.acceptOrder = false
				return false
			end
		else
			chatManager.handleInputMessage(message)
			if string.find(message, FORMAT_INPUT_MESSAGES.newOrder) or string.find(message, FORMAT_INPUT_MESSAGES.orderAccepted) then
				if not ini.settings.dispatcherMessages then
					return false
				end
			end
		end
	end
end

function sampev.onSendChat(message)
	chatManager.lastMessage = message
	chatManager.updateAntifloodClock()
end

function sampev.onSendCommand(command)
	chatManager.lastMessage = command
	chatManager.updateAntifloodClock()
end

function sampev.onSendSpawn()
	if player.onWork then
		if ini.settings.autoClist and not chatManager.hideResultMessages["/clist"].bool then
			chatManager.addMessageToQueue("/clist "..ini.settings.workClist,true,true)
		end
	end
end

function onScriptTerminate(script, quitGame)
	if script == thisScript() then
		removeBlip(orderHandler.currentOrderBlip)
		deleteCheckpoint(orderHandler.currentOrderCheckpoint)
		vehicleManager.clearMarkers()
		imgui.Process = false
		if not quitGame then
	    if not reload then
				chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..'] {FF6633}Скрипт прекратил работу. В случае возникновения ошибок обращаться в ВК - {00CED1}vk.com/twonse')
			end
		end
	end
end

function stringToMeters(string)
	if string.find(string, u8:decode" м") then
		return tonumber(string.match(string, u8:decode"(%d+) м"))
	else
		return tonumber(string.match(string, u8:decode"(.+) км")) * 1000
	end
end

function stringToSeconds(string)
	if string.find(string, u8:decode" мин") then
		local minutes, seconds = string.match(string, u8:decode"(%d+):(%d+) мин")
		return minutes * 60 + seconds
	else
		return tonumber(string.match(string, u8:decode"(.+) сек"))
	end
end

function table.spairs(_table, order)
    local keys = {}

    for key in pairs(_table) do
			keys[#keys+1] = key
		end

    if order then
        table.sort(keys, function(a,b) return order(_table, a, b) end)
    else
        table.sort(keys)
    end

    local index = 0
    return function()
        index = index + 1
        if keys[index] then
            return keys[index], _table[keys[index]]
        end
    end
end

function table.getTableKeysSortedByValue(_table, valueName, increase)
	local tableKeys = {}

	for key in table.spairs(_table, function(t,a,b) if increase then return t[a][valueName] < t[b][valueName] else return t[a][valueName] > t[b][valueName] end end) do
		table.insert(tableKeys, key)
	end

	return tableKeys
end

function table.contains(value, table)
	if type(table) == 'nil' then
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
	if type(table) == 'nil' then
		return true
	end

	for _, _ in pairs(table) do
		return false
	end
	return true
end

function imgui.initBuffers()
	imgui.settingsTab = 1
	imgui.showSettings = imgui.ImBool(false)
	imgui.showInputWindow = false
	imgui.key1Edit = false
	imgui.key2Edit = false
	imgui.key3Edit = false
	imgui.key = 0
	imgui.addKey = 0
	imgui.workClist = imgui.ImInt(ini.settings.workClist)
	imgui.SMSTimer = imgui.ImInt(ini.settings.SMSTimer)
	imgui.maxDistanceToAcceptOrder = imgui.ImInt(ini.settings.maxDistanceToAcceptOrder)
	imgui.maxDistanceToGetOrder = imgui.ImInt(ini.settings.maxDistanceToGetOrder)
	imgui.ordersDistanceUpdateTimer = imgui.ImInt(ini.settings.ordersDistanceUpdateTimer)
	imgui.soundVolume = imgui.ImInt(ini.settings.soundVolume)
end

function imgui.OnDrawFrame()
	if (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or imgui.showInputWindow) and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() then
		imgui.ShowCursor = true
	end
	if imgui.showInputWindow then
		imgui.onDrawInputWindow()
	elseif not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() and not (ini.settings.fastMapCompatibility and isKeyDown(fastMapKey)) then
		imgui.onDrawNotification()
		if ini.settings.showHUD then
			imgui.onDrawHUD()
		end
		if ini.settings.showBindMenu then
			imgui.onDrawBindMenu()
		end
		if imgui.showSettings.v then
			imgui.onDrawSettings()
		end
	end
end

function imgui.onDrawInputWindow()
	imgui.SetNextWindowPos(vec(290, 180))
	imgui.SetNextWindowSize(vec(90, 91))
	imgui.Begin("Горячие клавиши", _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoTitleBar)
		imgui.Dummy(vec(15,0))
		imgui.SameLine()
		imgui.Text("Установить клавиши")
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

		lua_thread.create(function()
			repeat
				wait(0)
				for k, v in pairs(vkeys) do
					if wasKeyPressed(v) then
						if v < 160 or v > 165 then
							if imgui.key == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and k ~= "VK_BACK" and k ~= "VK_LBUTTON" and k ~= "VK_RBUTTON" then
								imgui.key = v
							elseif imgui.key ~= v and imgui.addKey == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and k ~= "VK_BACK" and k ~= "VK_LBUTTON" and k ~= "VK_RBUTTON" then
								imgui.addKey = v
							elseif k == "VK_ESCAPE" then
								imgui.key = 0
								imgui.addKey = 0
								imgui.showInputWindow = false
							elseif k == "VK_RETURN" then
								imgui.showInputWindow = false
							elseif k == "VK_BACK" then
								imgui.key = 0
								imgui.addKey = 0
							end
						end
					end
				end
			until not imgui.showInputWindow
			imgui.showInputWindow = false
		end)
		imgui.Dummy(vec(0, 10))
		imgui.Text("Нажмите клавишу/комбинацию\nBackspace - стереть клавиши\nEnter - сохранить")
		if imgui.Button("Принять", vec(28,10)) then
			imgui.showInputWindow = false
		end
		imgui.SameLine()
		if imgui.Button("Удалить", vec(28,10)) then
			imgui.key = -1
			imgui.showInputWindow = false
		end
		imgui.SameLine()
		if imgui.Button("Отменить", vec(28,10)) then
			imgui.key = 0
			imgui.addKey = 0
			imgui.showInputWindow = false
		end
	imgui.End()
end

imgui.hudHovered = false
function imgui.onDrawHUD()
	if vehicleManager.vehicleName or isKeysPressed(ini.settings.key1, ini.settings.key1add, true) then
		local windowPosY = 0
		if orderHandler.currentOrder then
			windowPosY = 37
		end

		if not (imgui.hudHovered and imgui.IsMouseDragging(0) and isKeysPressed(ini.settings.key1, ini.settings.key1add, true)) or orderHandler.currentOrder then
			imgui.SetNextWindowPos(vec(ini.settings.hudPosX, ini.settings.hudPosY-windowPosY))
			imgui.SetNextWindowSize(vec(105, 42+windowPosY))
		end

		imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
		imgui.Begin("Taximate HUD", _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoFocusOnAppearing)
			imgui.hudHovered = imgui.IsRootWindowOrAnyChildHovered()
			local newPos = imgui.GetWindowPos()
			local savePosX, savePosY = convertWindowScreenCoordsToGameScreenCoords(newPos.x, newPos.y)

			if (math.ceil(savePosX)~=math.ceil(ini.settings.hudPosX) or math.ceil(savePosY)~=math.ceil(ini.settings.hudPosY)) and imgui.IsRootWindowOrAnyChildFocused() and imgui.IsMouseDragging(0) and imgui.IsRootWindowOrAnyChildHovered() and not orderHandler.currentOrder then
				ini.settings.hudPosX = math.ceil(savePosX)
				ini.settings.hudPosY = math.ceil(savePosY)
				inicfg.save(ini,'Taximate/settings.ini')
			end

			if not player.onWork then
				local buttonText = "Начать рабочий день"
				if ini.settings.hotKeys then
					if ini.settings.key3 ~= 0 then
						buttonText = buttonText .. " [" ..vkeys.id_to_name(ini.settings.key3)
						if ini.settings.key3add ~= 0 then
							buttonText = buttonText .. " + " ..vkeys.id_to_name(ini.settings.key3add)
						end
						buttonText = buttonText .. ']'
					end
				end
				if imgui.Button(buttonText, vec(100, 10)) then
					player.onWork = true
					if ini.settings.autoClist then
						chatManager.addMessageToQueue("/clist "..ini.settings.workClist, true, true)
					end
				end
			else
				local buttonText = "Закончить рабочий день"
				if ini.settings.hotKeys then
					if ini.settings.key3 ~= 0 then
						buttonText = buttonText .. " [" ..vkeys.id_to_name(ini.settings.key3)
						if ini.settings.key3add ~= 0 then
							buttonText = buttonText .. " + " ..vkeys.id_to_name(ini.settings.key3add)
						end
						buttonText = buttonText .. ']'
					end
				end
				if imgui.Button(buttonText, vec(100, 10)) then
					player.onWork = false
					if ini.settings.autoClist then
						chatManager.addMessageToQueue("/clist 0", true, true)
					end
				end
			end
			imgui.BeginChild('', vec(50,8), false, imgui.WindowFlags.NoScrollbar)
				imgui.TextColoredRGB("Скилл: {4296f9}"..player.skill..' {FFFFFF}('..player.skillExp..'%)')
		  imgui.EndChild()
			imgui.SameLine()
			imgui.BeginChild('right', vec(50, 8), false, imgui.WindowFlags.NoScrollbar)
		 		imgui.TextColoredRGB("Ранг: {4296f9}"..player.rank..' {FFFFFF}('..player.rankExp..'%)')
			imgui.EndChild()
			imgui.BeginChild('bottom', vec(56.5, 8), false, imgui.WindowFlags.NoScrollbar)
				imgui.TextColoredRGB("ЗП: {4296f9}" ..player.salary.. ' / '..player.salaryLimit .. '{FFFFFF} вирт')
			imgui.EndChild()
			imgui.SameLine()
			imgui.BeginChild('bottom ', vec(43.5, 8), false, imgui.WindowFlags.NoScrollbar)
				imgui.TextColoredRGB("Чай: {4296f9}" ..player.tips .. '{FFFFFF} вирт')
			imgui.EndChild()

			if orderHandler.currentOrder then
				imgui.BeginChild('bottom  ', vec(100, 34), true, imgui.WindowFlags.NoScrollbar)
					imgui.TextColoredRGB("Клиент: {4296f9}" .. orderHandler.currentOrder.nickname .. '[' .. orderHandler.currentOrder.id .. ']')
					imgui.TextColoredRGB("Район: {4296f9}" .. orderHandler.currentOrder.zone .. '{FFFFFF},{4296f9} ' .. orderHandler.currentOrder.currentDistance .. '{FFFFFF} м')
					local buttonText = "Отменить вызов"
					if ini.settings.hotKeys then
						if ini.settings.key2 ~= 0 then
							buttonText = buttonText .. " [" ..vkeys.id_to_name(ini.settings.key2)
							if ini.settings.key2add ~= 0 then
								buttonText = buttonText .. " + " ..vkeys.id_to_name(ini.settings.key2add)
							end
							buttonText = buttonText .. ']'
						end
					end
					if imgui.Button(buttonText, vec(95, 10)) then
						orderHandler.cancelCurrentOrder()
					end
				imgui.EndChild()
			end

		imgui.End()
		imgui.PopStyleVar()
	end
end

imgui.bindHovered = false
function imgui.onDrawBindMenu()
	if isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or bindMenu.isBindEdit() then
		if not bindMenu.isBindEdit() then
			bindMenu.bindList = bindMenu.getBindList()
		end
		imgui.ShowCursor = true

		if not (imgui.bindHovered and imgui.IsMouseDragging(0) and (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or bindMenu.isBindEdit())) then
			imgui.SetNextWindowPos(vec(ini.settings.binderPosX, ini.settings.binderPosY))
			imgui.SetNextWindowSize(vec(105, 228))
		end

		imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
			imgui.Begin("Taximate Binder", _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysVerticalScrollbar)
			imgui.bindHovered = imgui.IsRootWindowOrAnyChildHovered()
			local newPos = imgui.GetWindowPos()
			local savePosX, savePosY = convertWindowScreenCoordsToGameScreenCoords(newPos.x, newPos.y)

			if (math.ceil(savePosX)~=math.ceil(ini.settings.binderPosX) or math.ceil(savePosY)~=math.ceil(ini.settings.binderPosY)) and (imgui.bindHovered and imgui.IsMouseDragging(0) and (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or bindMenu.isBindEdit())) then
				ini.settings.binderPosX = math.ceil(savePosX)
				ini.settings.binderPosY = math.ceil(savePosY)
				inicfg.save(ini,'Taximate/settings.ini')
			end

			if orderHandler.currentOrder then
				imgui.NewLine()
				imgui.SameLine(toScreenX(3))
				if imgui.CollapsingHeader('Отправить СМС клиенту', vec(97, 10)) then
					imgui.NewLine()
					imgui.SameLine(toScreenX(10))
					if imgui.Button('Скоро буду', vec(89, 10)) then
						chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Скоро буду')
					end
					imgui.NewLine()
					imgui.SameLine(toScreenX(10))
					if imgui.Button('Вызов отменён', vec(89, 10)) then
						chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Вызов отменён, закажите новое такси')
					end
					imgui.NewLine()
					imgui.SameLine(toScreenX(10))
					if imgui.Button('Да', vec(89, 10)) then
						chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Да')
					end
					imgui.NewLine()
					imgui.SameLine(toScreenX(10))
					if imgui.Button('Нет', vec(89, 10)) then
						chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Нет')
					end
				end
			end

			if not table.isEmpty(vehicleManager.passengersList) then
				imgui.NewLine()
				imgui.SameLine(toScreenX(3))
				if vehicleManager.maxPassengers then
					if imgui.CollapsingHeader('Меню действий с пассажирами') then
						for passengerIndex = 0, vehicleManager.maxPassengers-1 do
							if vehicleManager.passengersList[passengerIndex] then
								imgui.NewLine()
								imgui.SameLine(toScreenX(11))
								if imgui.CollapsingHeader(vehicleManager.passengersList[passengerIndex].nickname..'['..vehicleManager.passengersList[passengerIndex].id..']', vec(89, 10)) then
									imgui.NewLine()
									imgui.SameLine(toScreenX(20))
									imgui.PushID(passengerIndex)
									if imgui.Button('Выкинуть из автомобиля', vec(79, 10)) then
										chatManager.addMessageToQueue("/eject "..vehicleManager.passengersList[passengerIndex].id)
									end
									imgui.PopID()
								end
							end
						end
					end
				end
			end

			if imgui.Button("Добавить строку", vec(97,10)) then
				if not bindMenu.isBindEdit() then
					bindMenu.json[#bindMenu.json+1] = {text = "", key = 0, addKey = 0}
					bindMenu.save()
				end
			end

			for bindIndex, bind in pairs(bindMenu.bindList) do
				if bind then
					imgui.PushID(bindIndex)
					if bind.edit then
						imgui.PushItemWidth(toScreenX(40))
						imgui.PushStyleVar(imgui.StyleVar.FramePadding, vec(4,1.1))
						imgui.PushID(bindIndex)
						if imgui.InputText("", bind.buffer) then
							bindMenu.json[bindIndex].text = bind.buffer.v
							bindMenu.save()
						end
						imgui.PopID()
						imgui.PopStyleVar()
						imgui.PopItemWidth()
					else
						local buttonName = ""
						if ini.settings.hotKeys then
							if bind.key ~= 0 then
								buttonName = "["..vkeys.id_to_name(bind.key)
							end
							if bind.addKey ~= 0 then
								buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.addKey)
							end
							if buttonName ~= "" then
								buttonName = buttonName .. "] "
							end
						end
						buttonName = buttonName .. bind.buffer.v
						if imgui.Button(buttonName, vec(89.5,10)) then
							chatManager.addMessageToQueue(bind.buffer.v)
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
					if imgui.Button(buttonName, vec(23,10)) then
						imgui.key = 0
						imgui.addKey = 0
						imgui.showInputWindow = true
					end

					if not imgui.showInputWindow and imgui.key ~= 0 then
						if imgui.key == -1 then
							imgui.key = 0
							imgui.addKey = 0
						end
						bindMenu.json[bindIndex].key = imgui.key
						bindMenu.json[bindIndex].addKey = imgui.addKey
						bind.key = imgui.key
						bind.addKey = imgui.addKey
						imgui.key = 0
						imgui.addKey = 0
						bindMenu.save()
					end
					imgui.SameLine()
					if imgui.Button("Удалить", vec(22.7,10)) then
								bindMenu.bindList[bindIndex].edit = false
								bindMenu.deleteBind(bindIndex)
					end
					imgui.SameLine()
					if bindMenu.bindList[bindIndex] then
						if imgui.Button("-", vec(5,10)) or isKeyJustPressed(13) then
							bindMenu.json[bindIndex].text = bind.buffer.v
							bind.edit = false
							bindMenu.save()
						end
					end

				else
					if imgui.Button("+", vec(5,10)) then
						bind.edit = true
						for _bindIndex, _bind in pairs(bindMenu.bindList) do
							if _bindIndex ~= bindIndex then
								_bind.edit = false
								bindMenu.save()
							end
						end
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
		local isOrderExist = orderHandler.orderList[notification.orderNickname]
		local sizeWithButton = 0

		if notification.button then
			sizeWithButton = 12
		end

		if notification.active and (notification.time < os.clock() or (notification.button and not isOrderExist)) then
			notification.active = false
		end

		if not notification.showtime then
			if notification.time < os.clock() then
				if notification.button and isOrderExist then
					if orderHandler.orderList[notification.orderNickname].direction>0 then
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

				if notification.active and (vehicleManager.vehicleName or isKeysPressed(ini.settings.key1, ini.settings.key1add, true)) then
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
						if orderHandler.currentOrder then
							notfPos = 37
						end
						local notificationTitle = '{4296f9}Taximate notification\t\t\t\t\t{FFFFFF}'.. notification.date

						notfList.pos = { x = ini.settings.hudPosX, y = notfList.pos.y - (notfList.size.y + 15 + sizeWithButton)}
						imgui.SetNextWindowPos(imgui.ImVec2(toScreenX(notfList.pos.x),toScreenY(notfList.pos.y-notfPos)))
						imgui.SetNextWindowSize(vec(105, sizeWithButton + notfList.size.y + imgui.GetStyle().ItemSpacing.y + imgui.GetStyle().WindowPadding.y - 5))
							imgui.Begin('message #' .. notificationIndex, _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoTitleBar)
							imgui.TextColoredRGB(notificationTitle)
							imgui.Dummy(vec(0,2))
							if notification.button then
								if orderHandler.orderList[notification.orderNickname] then
									if orderHandler.orderList[notification.orderNickname].direction>0 then
									 notification.text = string.format(FORMAT_NOTIFICATIONS.newOrderPos, notification.orderNickname, orderHandler.orderList[notification.orderNickname].id, orderHandler.orderList[notification.orderNickname].distance, orderHandler.orderList[notification.orderNickname].zone)
									elseif orderHandler.orderList[notification.orderNickname].direction<0 then
									 notification.text = string.format(FORMAT_NOTIFICATIONS.newOrderNeg, notification.orderNickname, orderHandler.orderList[notification.orderNickname].id, orderHandler.orderList[notification.orderNickname].distance,
									 orderHandler.orderList[notification.orderNickname].zone)
								 	end
									if orderHandler.orderList[notification.orderNickname].zone ~= "Неизвестно" then
										 notification.text = notification.text .. ', {4296f9}' .. orderHandler.orderList[notification.orderNickname].zone
									end
								end
							end
							imgui.TextColoredRGB(notification.text)
							imgui.Dummy(vec(0,2))
							if notification.button then
								local acceptOrderText = "Принять вызов"
								if orderHandler.lastCorrectOrderNickname == notification.orderNickname then
									if ini.settings.hotKeys then
										if ini.settings.key2 ~= 0 then
											acceptOrderText = acceptOrderText .. " [" ..vkeys.id_to_name(ini.settings.key2)
											if ini.settings.key2add ~= 0 then
												acceptOrderText = acceptOrderText .. " + " ..vkeys.id_to_name(ini.settings.key2add)
											end
											acceptOrderText = acceptOrderText .. ']'
										end
									end
								end
								if imgui.Button(acceptOrderText, vec(100, 10)) then
									orderHandler.acceptOrder(notification.orderNickname, orderHandler.orderList[notification.orderNickname].time)
									imgui.Dummy(vec(0,2))
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
			pos = {
				x = ini.settings.hudPosX,
				y = ini.settings.hudPosY
			},
			size = {
				x = 100,
				y = 33
			}
		}
end

function imgui.onDrawSettings()
	imgui.ShowCursor = true
	local resX, resY = getScreenResolution()
	imgui.SetNextWindowSize(vec(200, 195))
	imgui.SetNextWindowPos(vec(220, 110),2)
	imgui.Begin('Taximate '..thisScript()['version'], imgui.showSettings, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
		imgui.BeginChild('top', vec(195, 9), false)
			imgui.BeginChild(" right",vec(63.5,9), false)
				if imgui.Selectable('\t\t\t  Функции', imgui.settingsTab == 1) then
					imgui.settingsTab = 1
				end
			imgui.EndChild()
			imgui.SameLine()
			imgui.BeginChild("  right",vec(63.5,9), false)
				if imgui.Selectable('\t\t\tПараметры', imgui.settingsTab == 2) then
					imgui.settingsTab = 2
				end
			imgui.EndChild()
			imgui.SameLine()
			imgui.BeginChild("   right",vec(64,9), false)
				if imgui.Selectable('\t\t\tИнформация', imgui.settingsTab == 3) then
					imgui.settingsTab = 3
				end
			imgui.EndChild()
		imgui.EndChild()
		imgui.BeginChild('bottom', vec(195, 170), true)
			if imgui.settingsTab == 1 then
				if imgui.Checkbox("Отображение Taximate Binder", imgui.ImBool(ini.settings.showBindMenu)) then
					ini.settings.showBindMenu = not ini.settings.showBindMenu
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Отображение Taximate HUD", imgui.ImBool(ini.settings.showHUD)) then
					ini.settings.showHUD = not ini.settings.showHUD
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Уведомления", imgui.ImBool(ini.settings.notifications)) then
					ini.settings.notifications = not ini.settings.notifications
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				if imgui.Checkbox("Звуковые уведомления, громкость: ", imgui.ImBool(ini.settings.notifications and ini.settings.sounds)) then
					ini.settings.sounds = not ini.settings.sounds
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.setTooltip("Для работы требуется выставить минимальную громкость игрового радио и перезапустить игру", 90)
				imgui.SameLine()
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(43))
				if imgui.SliderInt("", imgui.soundVolume, 0, 100) then
					if imgui.soundVolume.v < 0 or imgui.soundVolume.v > 100 then
						imgui.soundVolume.v = defaultSettings.soundVolume
					end
					ini.settings.soundVolume = imgui.soundVolume.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.setTooltip("Для работы требуется выставить минимальную громкость игрового радио и перезапустить игру", 90)
				if imgui.Checkbox("Автоматическая отправка СМС клиенту раз в", imgui.ImBool(ini.settings.sendSMS)) then
					ini.settings.sendSMS = not ini.settings.sendSMS
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(53))
				if imgui.SliderInt("сек", imgui.SMSTimer, 15, 90) then
					if imgui.SMSTimer.v < 15 or imgui.SMSTimer.v > 90 then
						imgui.SMSTimer.v = defaultSettings.SMSTimer
					end
					ini.settings.SMSTimer = imgui.SMSTimer.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Отправка СМС клиенту при отмене вызова", imgui.ImBool(ini.settings.sendSMSCancel)) then
					ini.settings.sendSMSCancel = not ini.settings.sendSMSCancel
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Сообщения от диспетчера",imgui.ImBool(ini.settings.dispatcherMessages)) then
					ini.settings.dispatcherMessages = not ini.settings.dispatcherMessages
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Обновление метки на карте, если клиент поблизости",imgui.ImBool(ini.settings.updateOrderMark)) then
					ini.settings.updateOrderMark = not ini.settings.updateOrderMark
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Принятие повторного вызова от клиента",imgui.ImBool(ini.settings.acceptRepeatOrder)) then
					ini.settings.acceptRepeatOrder = not ini.settings.acceptRepeatOrder
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Менять clist при начале / конце рабочего дня. Рабочий clist:",imgui.ImBool(ini.settings.autoClist)) then
					ini.settings.autoClist = not ini.settings.autoClist
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(28))
				if imgui.SliderInt(" ", imgui.workClist, 0, 33) then
					if imgui.workClist.v < 0 or imgui.workClist.v > 33 then
						imgui.workClist.v = defaultSettings.workClist
					end
					ini.settings.workClist = imgui.workClist.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Принятие вызовов от 3-х последних пассажиров",imgui.ImBool(ini.settings.acceptLastPassengersOrders)) then
					ini.settings.acceptLastPassengersOrders = not ini.settings.acceptLastPassengersOrders
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Показывать на карте игроков в транспорте",imgui.ImBool(ini.settings.markers)) then
					ini.settings.markers = not ini.settings.markers
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Заканчивать рабочий день при поломке/пустом баке",imgui.ImBool(ini.settings.finishWork)) then
					ini.settings.finishWork = not ini.settings.finishWork
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Обновление дистанции всех вызовов раз в", imgui.ImBool(ini.settings.ordersDistanceUpdate)) then
					ini.settings.ordersDistanceUpdate = not ini.settings.ordersDistanceUpdate
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(59))
				if imgui.SliderInt("сeк", imgui.ordersDistanceUpdateTimer, 1, 30) then
					if imgui.ordersDistanceUpdateTimer.v < 1 or imgui.ordersDistanceUpdateTimer.v > 30 then
						imgui.ordersDistanceUpdateTimer.v = defaultSettings.ordersDistanceUpdateTimer
					end
					ini.settings.ordersDistanceUpdateTimer = imgui.ordersDistanceUpdateTimer.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Горячие клавиши",imgui.ImBool(ini.settings.hotKeys)) then
					ini.settings.hotKeys = not ini.settings.hotKeys
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Совместимость с FastMap",imgui.ImBool(ini.settings.fastMapCompatibility)) then
					ini.settings.fastMapCompatibility = not ini.settings.fastMapCompatibility
					inicfg.save(ini,'Taximate/settings.ini')
				end
			elseif imgui.settingsTab == 2 then
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
				if imgui.Button(buttonText, vec(0,10)) then
					imgui.key = 0
					imgui.addKey = 0
					imgui.showInputWindow = true
					imgui.key1Edit = true
				end
				imgui.PopID()
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
				if imgui.Button(buttonText, vec(0,10)) then
					imgui.key = 0
					imgui.addKey = 0
					imgui.showInputWindow = true
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
				if imgui.Button(buttonText, vec(0,10)) then
					imgui.key = 0
					imgui.addKey = 0
					imgui.showInputWindow = true
					imgui.key3Edit = true
				end
				imgui.PopID()

				if not imgui.showInputWindow and imgui.key ~= 0 then
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
					end
					inicfg.save(ini,'Taximate/settings.ini')
					imgui.key1Edit = false
					imgui.key2Edit = false
					imgui.key3Edit = false
					imgui.key = 0
					imgui.addKey = 0
				end
				imgui.Text("Дистанция для автопринятия вызова:")
				imgui.SameLine()
				imgui.Dummy(vec(1.8,0))
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(85))
				if imgui.SliderInt("м", imgui.maxDistanceToAcceptOrder, 0, 7000) then
					if imgui.maxDistanceToAcceptOrder.v < 0 or imgui.maxDistanceToAcceptOrder.v > 7000 then
						imgui.maxDistanceToAcceptOrder.v = defaultSettings.maxDistanceToAcceptOrder
					end
					ini.settings.maxDistanceToAcceptOrder = imgui.maxDistanceToAcceptOrder.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.Text("Дистанция для получения доп. вызова:")
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(85))
				if imgui.SliderInt("м ", imgui.maxDistanceToGetOrder, 0, 7000) then
					if imgui.maxDistanceToGetOrder.v < 0 or imgui.maxDistanceToGetOrder.v > 7000 then
						imgui.maxDistanceToGetOrder.v = defaultSettings.maxDistanceToGetOrder
					end
					ini.settings.maxDistanceToGetOrder = imgui.maxDistanceToGetOrder.v
					inicfg.save(ini,'Taximate/settings.ini')
				end
			else
				if imgui.Checkbox("Автоматическая проверка обновлений", imgui.ImBool(ini.settings.checkUpdates)) then
					ini.settings.checkUpdates = not ini.settings.checkUpdates
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.setTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
				if imgui.Button("Проверить обновления") then
					checkUpdates()
				end
				imgui.setTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
				imgui.SameLine()
				if script_updates.update then
					if imgui.Button("Скачать новую версию") then
						update()
					end
				else
					imgui.Text("Обновления отсутствуют")
				end
				imgui.setTooltip("Антистиллеры и прочие скрипты могут блокировать проверку обновлений", 90)
				if imgui.Button("Перезапустить скрипт") then
					reload = true
					thisScript():reload()
				end
				imgui.Text("Связь:")
				imgui.SameLine()
				if imgui.Button("GitHub.com/21se/Taximate") then
					os.execute("start https://github.com/21se/Taximate/issues/new")
				end
				imgui.SameLine()
				if imgui.Button("VK.com/twonse") then
					os.execute("start https://vk.com/twonse")
				end
				imgui.SameLine()
				if imgui.Button("SRP Revolution (pivo)") then
					if server == "revolution" then
						local found = false
						local maxPlayerId = sampGetMaxPlayerId(false)
						for id = 0, maxPlayerId+1 do
							if sampIsPlayerConnected(id) then
								if sampGetPlayerNickname(id) == "pivo" then
									chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Свяжись с разработчиком прямо в игре - {00CED1}pivo[' .. id ..']')
									found = true
								end
							end
						end
						if not found then
							chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Разработчик сейчас не в сети :(')
						end
					end
				end
				imgui.Text("История обновлений")
				imgui.BeginChild('changelog', vec(190, 108), true)
					if script_updates.changelog then
						for index, key in pairs(script_updates.sorted_keys) do
							if imgui.CollapsingHeader('Версия '..key) then
								imgui.PushTextWrapPos(toScreenX(185))
								imgui.Text(script_updates.changelog[key])
								imgui.PopTextWrapPos()
							end
						end
					end
				imgui.EndChild()
			end
		imgui.EndChild()
	imgui.End()
end

function imgui.addNotification(text, time)
	notificationsQueue[#notificationsQueue+1] = {active = false, time = 0, showtime = time, date = os.date("%X"), text = text, button = false, orderNickname = nil}
end

function imgui.setTooltip(text, width)
	if imgui.IsItemHovered() then
		imgui.BeginTooltip()
		imgui.PushTextWrapPos(toScreenX(width))
		imgui.TextUnformatted(text)
		imgui.PopTextWrapPos()
		imgui.EndTooltip()
	end
end

function imgui.addNotificationWithButton(text, time, _orderNickname)
	notificationsQueue[#notificationsQueue+1] = {active = false, time = 0, showtime = time, date = os.date("%X"), text = text, button = true, orderNickname = _orderNickname}
end

local zones = {
	["Мэрия"] = { x = 1481.229248, y = -1749.487305, z = 15.445300},
	["Автошкола"] = { x = -2026.514404, y = -95.752701, z = 34.729801},
	["Автовокзал LS"] = { x = 1143.750122, y = -1746.589111, z = 13.135900},
	["ЖД вокзал LS"] = { x = 1808.494507, y = -1896.349854, z = 13.068900},
	["АВ/ЖД вокзал SF"] = { x = -1985.027222, y = 113.767799, z = 27.256201},
	["АВ/ЖД вокзал LV"] = { x = 2843.035156, y = 1343.983032, z = 10.352100},
	["Fort Carson"] = { x = 61.247101, y = 1189.191040, z = 18.397301},
	["Прием металла"] = { x = 2263.516846, y = -2537.962158, z = 8.374100},
	["Наркопритон"] = { x = 2182.824707, y = -1669.634644, z = 14.134600},
	["Аэропорт LS"] = { x = 1967.201050, y = -2173.359375, z = 13.056900},
	["Аэропорт SF"] = { x = -1551.542847, y = -436.707214, z = 5.571300},
	["Аэропорт LV"] = { x = 1726.291260, y = 1610.033325, z = 9.659000},
	["Vinewood"] = { x = 1380.432251, y = -897.429016, z = 36.463100},
	["Santa Maria"] = { x = 331.410309, y = -1802.567505, z = 4.184100},
	["Стадион SF"] = { x = -2133.911133, y = -444.985199, z = 35.335800},
	["Спортзал LV"] = { x = 2098.566895, y = 2480.085938, z = 10.820300},
	["Пейнтбол"] = { x = 2488.860107, y = 2776.471191, z = 10.787000},
	["Церковь SF"] = { x = -1981.333252, y = 1117.466675, z = 53.123600},
	["Военкомат"] = { x = -551.301514, y = 2593.905029, z = 53.928398},
	["Перегон. Получение"] = { x = 2476.624756, y = -2596.437256, z = 13.648400},
	["Перегон. Сдача"] = { x = -1705.791138, y = 12.411100, z = 3.554700},
	["Торговая площадка"] = { x = -1939.609131, y = 555.069824, z = 35.171902},
	["Черный рынок"] = { x = 2519.776367, y = -1272.694214, z = 34.883598},
	["Кладбище LS"] = { x = 815.756226, y = -1103.168091, z = 25.790300},
	["Банк LS"] = { x = 1411.718750, y = -1699.705566, z = 13.539500},
	["Банк SF"] = { x = -2226.506348, y = 251.924103, z = 35.320301},
	["Банк LV"] = { x = 2412.576660, y = 1123.766235, z = 10.820300},
	["Склад с алкоголем"] = { x = -49.508301, y = -297.973602, z = 4.979400},
	["Склад продуктов"] = { x = -502.780609, y = -553.796204, z = 25.087400},
	["Склад урожая"] = { x = 1629.969971, y = 2326.031494, z = 10.820300},
	["Автобусный парк"] = { x = 1638.358643, y = -1148.711914, z = 23.479000},
	["Машины хот-догов"] = { x = -2407.622803, y = 741.159424, z = 34.924900},
	["Инкассаторы"] = { x = -2206.516113, y = 312.605194, z = 35.443501},
	["Работа грузчика"] = { x = 2230.001709, y = -2211.310547, z = 13.546800},
	["Спортзал LV"] = { x = 2098.566895, y = 2480.085938, z = 10.820300},
	["Автоугонщики"] = { x = 2494.080078, y = -1464.709961, z = 24.020000},
	["Грабители ЛЭП"] = { x = 2285.899658, y = -2339.326904, z = 13.546900},
	["Стоянка электриков"] = { x = -84.297798, y = -1125.867188, z = 0.655700},
	["Ограбление домов"] = { x = 2444.0413, y = -1971.8397, z = 13.5469},
	["Клуб Alhambra"] = { x = 1827.609253, y = -1682.122070, z = 13.118200},
	["Клуб Jizzy"] = { x = -2593.454834, y = 1362.782349, z = 6.657800},
	["Клуб Pig Pen"] = { x = 2417.153076, y = -1244.189941, z = 23.380501},
	["Бар Grove street"] = { x = 2306.214355, y = -1651.560547, z = 14.055600},
	["Бар Misty"] = { x = -2246.219482, y = -90.975998, z = 34.886700},
	["Клуб Amnesia"] = { x = 2507.358398, y = 1242.260132, z = 10.826900},
	["Бар Big Spread Ranch"] = { x = 693.625305, y = 1967.683716, z = 5.539100},
	["Бар Lil Probe Inn"] = { x = -89.612503, y = 1378.249268, z = 10.469700},
	["Бар Tierra Robada"] = { x = -2501.242920, y = 2318.692627, z = 4.984300},
	["Comedy club"] = { x = 1879.190918, y = 2339.538330, z = 11.979900},
	["Казино 4 Дракона"] = { x = 2019.318115, y = 1007.755920, z = 10.820300},
	["Казино Калигула"] = { x = 2196.960693, y = 1677.085815, z = 12.367100},
	["Склад бара 4 Дракона"] = { x = 1908.672607, y = 965.244629, z = 10.820300},
	["Склад бара Калигула"] = { x = 2314.892822, y = 1733.299561, z = 10.820300},
	["Belagio"] = { x = 1658.526611, y = 2250.043457, z = 12.070100},
	["Sobrino de Botin"] = { x = 2269.751465, y = -74.159599, z = 27.772400},
	["Автосалон LS N"] = { x = 557.109619, y = -1285.791626, z = 16.809401},
	["Автосалон SF D/C"] = { x = -1987.325806, y = 288.925507, z = 33.982700},
	["Автосалон SF B/A"] = { x = -1638.351440, y = 1202.657227, z = 6.762800},
	["Автосалон LV B/A"] = { x = 2159.575195, y = 1385.734131, z = 10.386600},
	["Магазин одежды LS"] = { x = 461.512390, y = -1500.866211, z = 31.059700},
	["Магазин одежды SF"] = { x = -1694.672119, y = 951.845581, z = 24.890600},
	["Магазин одежды LV"] = { x = 2802.930664, y = 2430.718018, z = 11.062500},
	["Амму-нация LS"] = { x = 1363.999512, y = -1288.826660, z = 13.108200},
	["Амму-нация SF"] = { x = -2611.327393, y = 213.002808, z = 5.190800},
	["Амму-нация LV"] = { x = 2154.377686, y = 935.150208, z = 10.391700},
	["Вертолет LS"] = { x = 1571.372192, y = -1335.252197, z = 16.484400},
	["Вертолет SF"] = { x = -2241.166992, y = 2322.205566, z = 7.545400},
	["Вертолет LV"] = { x = 2614.588379, y = 2735.326416, z = 36.538601},
	["Больница SF"] = { x = -2658.259766, y = 627.981018, z = 14.453100},
	["Полиция LS"] = { x = 1548.657715, y = -1675.475220, z = 14.620200},
	["Полиция SF"] = { x = -1607.410034, y = 723.037170, z = 11.895400},
	["Полиция LV"] = { x = 2283.758789, y = 2420.525146, z = 10.381600},
	["ФБР"] = { x = -2418.072754, y = 497.657501, z = 29.606501},
	["Авианосец"] = { x = -1554.953613, y = 500.124207, z = 6.745500},
	["Зона 51"] = { x = 133.322205, y = 1994.773560, z = 19.049900},
	["Новости LS"] = { x = 1632.979248, y = -1712.134644, z = 12.878200},
	["Новости SF"] = { x = -2013.973755, y = 469.190094, z = 34.742901},
	["Новости LV"] = { x = 2617.339600, y = 1179.765137, z = 10.388400},
	["Yakuza"] = { x = 1538.844360, y = 2761.891602, z = 10.388200},
	["Русская мафия"] = { x = 1001.480103, y = 1690.514526, z = 10.486100},
	["La Cosa Nostra"] = { x = 1461.381958, y = 659.340027, z = 10.387200},
	["Grove street"] = { x = 2491.886963, y = -1666.881348, z = 12.910300},
	["Vagos"] = { x = 2803.555420, y = -1585.062500, z = 10.492400},
	["Ballas"] = { x = 2702.399414, y = -2003.425903, z = 12.972800},
	["Rifa"] = { x = 2184.550537, y = -1765.587158, z = 12.948300},
	["Aztecas"] = { x = 1723.966553, y = -2112.802734, z = 12.949000},
	["Ферма 0"] = { x = -381.502808, y = -1438.979248, z = 25.726601},
	["Ферма 1"] = { x = -112.575401, y = -10.423600, z = 3.109400},
	["Ферма 2"] = { x = -1060.398560, y = -1205.524048, z = 129.218704},
	["Ферма 3"] = { x = -5.595900, y = 67.837303, z = 3.117100},
	["Ферма 4"] = { x = 1925.693237, y = 170.401703, z = 37.281200},
	["Порт ЛС"] = { x = 2507.131348, y = -2234.151855, z = 13.546900},
	["Порт СФ"] = { x = -1731.500000, y = 118.919899, z = 3.549900},
	["Нефтезавод 1"] = { x = 256.260010, y = 1414.930054, z = 10.699900},
	["Нефтезавод 2"] = { x = -1046.780029, y = -670.650024, z = 32.349899},
	["Склад угля 1"] = { x = 832.456787, y = 863.901611, z = 12.665400},
	["Склад угля 2"] = { x = -2923.211, y = -1424.843, z = 13.577},
	["Гора Чилиад"] = { x = -2231.874, y = -1739.619, z = 481.343},
	["Лесопилка 1"] = { x = -449.269897, y = -65.660004, z = 59.409901},
	["Лесопилка 2"] = { x = -1978.709961, y = -2435.139893, z = 30.620001},
	["Дальнобойщики"] = { x = 2236.611816, y = 2770.693848, z = 10.302900},
	["Кладбище самолётов"] = {x = 252.94, y = 2504.34, z = 16.48},
	["Hell's Angels MC"] = { x = 681.496521, y = -475.403198, z = 16.335800},
	["Mongols MC"] = { x = -1265.713867, y = 2716.588623, z = 50.266300},
	["Pagans MC"] = { x = -2104.451904, y = -2481.883057, z = 30.625000},
	["Outlaws MC"] = { x = -309.605103, y = 1303.436035, z = 53.664200},
	["Sons of Silence MC"] = { x = 1243.829102, y = 203.576202, z = 19.554701},
	["Warlocks MC"] = { x = 661.681824, y = 1717.991211, z = 7.187500},
	["Highwaymen MC"] = { x = 22.934000, y = -2646.949219, z = 40.465599},
	["Bandidos MC"] = { x = -1940.291016, y = 2380.227783, z = 49.695301},
	["Free Souls MC"] = { x = -253.842606, y = 2603.138184, z = 62.858200},
	["Vagos MC"] = { x = -315.249115, y = 1773.921875, z = 43.640499},
	["Idlewood"] = { x = 1940.922241, y = -1772.977905, z = 13.640600},
	["Mulholland"] = { x = 1003.979614, y = -937.547302, z = 42.327900},
	["Flint"] = { x = -90.936501, y = -1169.390747, z = 2.417000},
	["Whetstone"] = { x = -1605.548340, y = -2714.580322, z = 48.533501},
	["Easter"] = { x = -1675.596558, y = 413.487213, z = 7.179500},
	["Juniper"] = { x = -2410.803467, y = 975.240906, z = 45.460800},
	["ElGuebrabos"] = { x = -1328.197510, y = 2677.596924, z = 50.062500},
	["BoneCounty"] = { x = 614.468323, y = 1692.853638, z = 7.187500},
	["Come-A-Lot"] = { x = 2115.459717, y = 920.206421, z = 10.820300},
	["PricklePine"] = { x = 2147.674561, y = 2747.945313, z = 10.820300},
	["Montgomery"] = { x = 1381.814453, y = 459.148010, z = 20.345100},
	["Dillimore"] = { x = 655.649109, y = -564.918518, z = 16.335800},
	["AngelPine"] = { x = -2243.743896, y = -2560.555420, z = 31.921801},
	["Julius"] = { x = 2640.000244, y = 1106.087646, z = 11.820300},
	["Emerald Isle"] = { x = 2202.513672, y = 2474.136230, z = 11.820300},
	["Redsands"] = { x = 1596.309814, y = 2199.004639, z = 11.820300},
	["Tierra Robada"] = { x = -1471.741943, y = 1863.972412, z = 33.632801},
	["Flats"] = { x = -2718.883301, y = 50.532200, z = 5.335900},
	["Palomino Creek"] = { x = 2250.245117, y = 52.701401, z = 23.667101},
	["Financial"] = { x = -1807.485352, y = 944.666626, z = 25.890600},
	["Garcia"] = { x = -2335.718750, y = -166.687805, z = 36.554501},
	["Esplanade"] = { x = -1721.592529, y = 1360.345215, z = 8.185100},
	["Marina Cluck"] = { x = 928.539917, y = -1352.939331, z = 14.343700},
	["Willowfield"] = { x = 2397.851563, y = -1899.040039, z = 14.546600},
	["Marina Burger"] = { x = 810.510010, y = -1616.193848, z = 14.546600},
	["Redsands West"] = { x = 1157.925537, y = 2072.282227, z = 12.062500},
	["Redsands East"] = { x = 1872.255249, y = 2071.863037, z = 12.062500},
	["Strip"] = { x = 2083.269775, y = 2224.697510, z = 12.023400},
	["Old Venturas Strip"] = { x = 2472.861816, y = 2034.192627, z = 12.062500},
	["Old Venturas Strip"] = { x = 2393.200684, y = 2041.559448, z = 11.820300},
	["Spinybed"] = { x = 2169.407715, y = 2795.919189, z = 11.820300},
	["Angel Pine"] = { x = -2155.095215, y = -2460.377930, z = 30.851601},
	["СТО LS"] = { x = 854.575928, y = -605.205322, z = 18.421801},
	["СТО SF"] = { x = -1799.868042, y = 1200.299316, z = 25.119400},
	["СТО LV"] = { x = 1658.380371, y = 2200.350342, z = 10.820300},
	["Гараж LS"] = { x = 1636.659180, y = -1525.564209, z = 13.306700},
	["Гараж SF"] = { x = -1979.227905, y = 436.112000, z = 25.910801},
	["Гараж LV"] = { x = 1447.295410, y = 2370.614990, z = 10.528000},
	["Больница LS"] = { x = 1181.302, y = -1323.499, z = 13.584},
	["Больница LV"] = { x = 1607.858, y = 1820.549, z = 10.828},
	["Jefferson Motel"] = { x = 2228.676, y = -1161.456, z = 25.783},
	["Glen Park"] = { x = 1970.055, y = -1204.361, z = 25.518},
	["Стадион LS"] = { x = 2704.779053, y = -1701.145874, z = 11.843800},
	["Стадион LV"] = { x = 1099.208, y = 1600.952, z = 12.546}
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

	style.WindowRounding = 2.0
	style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
	style.ChildWindowRounding = 2.0
	style.FrameRounding = 2.0
	style.ScrollbarSize = toScreenX(4.3)
	style.ScrollbarRounding = 0
	style.GrabMinSize = 8.0
	style.GrabRounding = 1.0
	style.WindowPadding = vec(2.5,2.5)
	style.FramePadding = vec(1,1)
	style.ItemSpacing = vec(2,2)
	style.ItemInnerSpacing = vec(2, 2)
	style.IndentSpacing = toScreenX(0)


	colors[clr.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
	colors[clr.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
	colors[clr.WindowBg]               = ImVec4(0.06, 0.06, 0.06, 0.94)
	colors[clr.ChildWindowBg]          = ImVec4(1.00, 1.00, 1.00, 0.00)
	colors[clr.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
	colors[clr.ComboBg]                = colors[clr.PopupBg]
	colors[clr.Border]                 = ImVec4(0.43, 0.43, 0.50, 0.50)
	colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
	colors[clr.FrameBg]                = ImVec4(0.16, 0.29, 0.48, 0.54)
	colors[clr.FrameBgHovered]         = ImVec4(0.26, 0.59, 0.98, 0.40)
	colors[clr.FrameBgActive]          = ImVec4(0.26, 0.59, 0.98, 0.67)
	colors[clr.TitleBg]                = ImVec4(0.16, 0.29, 0.48, 1.00)
	colors[clr.TitleBgActive]          = ImVec4(0.16, 0.29, 0.48, 1.00)
	colors[clr.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.51)
	colors[clr.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
	colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
	colors[clr.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
	colors[clr.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
	colors[clr.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
	colors[clr.CheckMark]              = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.SliderGrab]             = ImVec4(0.24, 0.52, 0.88, 1.00)
	colors[clr.SliderGrabActive]       = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.Button]                 = ImVec4(0.26, 0.59, 0.98, 0.40)
	colors[clr.ButtonHovered]          = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.ButtonActive]           = ImVec4(0.06, 0.53, 0.98, 1.00)
	colors[clr.Header]                 = ImVec4(0.26, 0.59, 0.98, 0.31)
	colors[clr.HeaderHovered]          = ImVec4(0.26, 0.59, 0.98, 0.80)
	colors[clr.HeaderActive]           = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.Separator]              = colors[clr.Border]
	colors[clr.SeparatorHovered]       = ImVec4(0.26, 0.59, 0.98, 0.78)
	colors[clr.SeparatorActive]        = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.ResizeGrip]             = ImVec4(0.26, 0.59, 0.98, 0.25)
	colors[clr.ResizeGripHovered]      = ImVec4(0.26, 0.59, 0.98, 0.67)
	colors[clr.ResizeGripActive]       = ImVec4(0.26, 0.59, 0.98, 0.95)
	colors[clr.CloseButton]            = ImVec4(0.41, 0.41, 0.41, 0.50)
	colors[clr.CloseButtonHovered]     = ImVec4(0.98, 0.39, 0.36, 1.00)
	colors[clr.CloseButtonActive]      = ImVec4(0.98, 0.39, 0.36, 1.00)
	colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
	colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
	colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
	colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
	colors[clr.TextSelectedBg]         = ImVec4(0.26, 0.59, 0.98, 0.35)
	colors[clr.ModalWindowDarkening]   = ImVec4(0.80, 0.80, 0.80, 0.35)
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
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImColor(r, g, b, a):GetVec4()
    end

    local render_text = function(text_)
        for w in text_:gmatch('[^\r\n]+') do
            local text, colors_, m = {}, {}, 1
            w = w:gsub('{(......)}', '{%1FF}')
            while w:find('{........}') do
                local n, k = w:find('{........}')
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
            else imgui.Text(w) end
        end
    end

    render_text(text)
end

function sampev.onSetRaceCheckpoint(type, position)
	vehicleManager.GPSMark = {x = position.x, y = position.y, z = position.z, time = os.clock()}
end

function getGPSMarkCoords3d()
	wait(500)
	local found = false
	if vehicleManager.GPSMark then
		found = os.clock() - vehicleManager.GPSMark.time <= 5
	end
  return found, vehicleManager.GPSMark.x, vehicleManager.GPSMark.y, vehicleManager.GPSMark.z
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
	return imgui.ImVec2(convertGameScreenCoordsToWindowScreenCoords(gX, gY))
end

function getDistanceToCoords3d(posX, posY, posZ)
	local charPosX, charPosY, charPosZ = getCharCoordinates(PLAYER_PED)
	local distance = math.ceil(getDistanceBetweenCoords3d(charPosX, charPosY, charPosZ, posX, posY, posZ))
	return distance
end

function checkUpdates()
  local fpath = os.tmpname()
  if doesFileExist(fpath) then os.remove(fpath) end
  downloadUrlToFile("https://raw.githubusercontent.com/21se/Taximate/dev/version.json", fpath, function(_, status, _, _)
    if status == 58 then
      if doesFileExist(fpath) then
        local file = io.open(fpath, 'r')
        if file then
          script_updates = decodeJson(file:read('*a'))
					script_updates.sorted_keys = {}
					if script_updates.changelog then
						for key in pairs(script_updates.changelog) do
							table.insert(script_updates.sorted_keys, key)
						end
						table.sort(script_updates.sorted_keys, function(a, b) return a > b end)
					end
          file:close()
          os.remove(fpath)
          if script_updates['version_num'] > thisScript()['version_num'] then
						chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Доступна новая версия скрипта. Обновление можно скачать в меню настроек - {00CED1}/taximate')
							script_updates.update = true
            return true
          end
        end
      end
    end
  end)
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
	return keycheck({k  = {key, addKey}, t = {'KeyDown', 'KeyPressed'}})
end

function update()
  downloadUrlToFile("https://raw.githubusercontent.com/21se/Taximate/dev/taximate.lua", thisScript().path, function(_, status, _, _)
    if status == 6 then
			chatManager.addChatMessage('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Скрипт обновлён. В случае возникновения ошибок обращаться в ВК - {00CED1}vk.com/twonse{FFFFFF}')
			reload = true
      thisScript():reload()
    end
  end)
end
