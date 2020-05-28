script_name('Taximate')
script_author("21se(pivo)")
script_version('1.2.5')
script_version_number(22)
script_url("https://21se.github.io/Taximate")
script.update = false

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
	newOrder = u8:decode" Диспетчер: вызов от .+. Примерное расстояние .+",
	orderAccepted = u8:decode" Диспетчер: .+ принял вызов от .+%[.+%]",
	newPassenger = u8:decode" Пассажир .+ сел в ваше Такси. Довезите его и государство заплатит вам",
	payCheck = u8:decode(" Вы заработали .+ вирт. Деньги будут зачислены на ваш банковский счет в .+")
}

local FORMAT_INPUT_MESSAGES = {
	newOrder = u8:decode" Диспетчер: вызов от (.+)%[(%d+)%]. Примерное расстояние (.+)",
	orderAccepted = u8:decode" Диспетчер: (.+) принял вызов от (.+)%[.+%]",
	newPassenger = u8:decode" Пассажир (.+) сел в ваше Такси. Довезите его и государство заплатит вам",
	payCheck = u8:decode" Вы заработали (.+) / (.+) вирт. Деньги будут зачислены на ваш банковский счет в .+"
}

local REMOVE_INPUT_MESSAGES = {
	serviceNotice = u8:decode" Введите '/service' чтобы принять вызов "
}

local FORMAT_TAXI_SMS = {
	onWay = "/sms %d [Taxi] Жёлтый %s в пути. Дистанция: %d м",
	arrived = "/sms %d [Taxi] Жёлтый %s прибыл на место вызова"
}

local FORMAT_NOTIFICATIONS ={
	newOrder = "Новый вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s {FFFFFF}м",
	newOrderPos = "Новый вызов от {4296f9}%s[%s]\nДистанция: {42ff96}%s {FFFFFF}м",
	newOrderNeg = "Новый вызов от {4296f9}%s[%s]\nДистанция: {d44331}%s {FFFFFF}м",
	orderAccepted = "Принят вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s {FFFFFF}м"
}


function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(100) end
	sampAddChatMessage(u8:decode('{00CED1}[Taximate v'..thisScript().version..']{FFFFFF} Меню настроек скрипта - {00CED1}/taximate{FFFFFF}, страница скрипта: {00CED1}'.. thisScript().url:gsub('https://', '')),0xFFFFFF)

	repeat
		wait(100)
		local _, playerID = sampGetPlayerIdByCharHandle(PLAYER_PED)
		player.nickname = sampGetPlayerNickname(playerID)
		player.id = playerID
	until sampGetPlayerScore(player.id) ~= 0 and sampGetCurrentServerName() ~= 'Samp-Rp.Ru'

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
		end

		if player.onWork then
			orderHandler.autoAccept = table.isEmpty(vehicleManager.passengersList) and not orderHandler.currentOrder
		else
			orderHandler.autoAccept = false
		end

		if player.onWork then
			orderHandler.refreshCurrentOrder()
		elseif orderHandler.currentOrder then
			orderHandler.cancelCurrentOrder()
		end

		if ini.settings.markers then
			vehicleManager.drawMarkers()
		else
			vehicleManager.clearMarkers()
		end

		if ini.settings.ordersDistanceUpdate then
			if player.onWork then
				orderHandler.updateOrdersDistance()
			end
		end

		if isKeysPressed(ini.settings.key3, ini.settings.key3add, false) and ini.settings.hotKeys then
			if player.onWork then
				player.onWork = false
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist 0", true,true)
				end
				if orderHandler.currentOrder then
					orderHandler.cancelCurrentOrder()
				end
			else
				player.onWork = true
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist "..ini.settings.workClist,true,true)
				end
			end
		end

		if isKeyJustPressed(vkeys.VK_2) then
			if player.onWork then
				if vehicleManager.maxPassengers then
					chatManager.updateAntifloodClock()
				end
			end
		end

		if player.onWork then
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
		end

	end
end

chatManager = {}
	chatManager.messagesQueue = {}
	chatManager.messagesQueueSize = 10
	chatManager.antifloodClock = os.clock()

	function chatManager.updateAntifloodClock()
		chatManager.antifloodClock = os.clock()
	end

	function chatManager.checkMessagesQueueThread()
		while true do
			wait(0)
			for messageIndex = 1, chatManager.messagesQueueSize do
				if chatManager.messagesQueue[messageIndex].message ~= '' and os.clock() - chatManager.antifloodClock > 1 then
					if chatManager.messagesQueue[messageIndex].hideResult then
						if string.find(chatManager.messagesQueue[messageIndex].message, '/jskill') then
							player.skillCheck = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/paycheck') then
							player.payCheck = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/clist') then
							player.clistEnable = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/gps') then
							player.removeGPSmark = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/service') then
							player.updateDistance = true
						end
					end
					sampSendChat(u8:decode(chatManager.messagesQueue[messageIndex].message))
					chatManager.messagesQueue[messageIndex].message = ''
					chatManager.messagesQueue[messageIndex].hideResult = false
					chatManager.updateAntifloodClock()
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
				distance = string2Meters(distance)
				orderHandler.addOrder(nickname, id, distance, time)
			elseif string.find(message, INPUT_MESSAGES.orderAccepted) and player.onWork then
				local driverNickname, passengerNickname = string.match(message, FORMAT_INPUT_MESSAGES.orderAccepted)
				if driverNickname == player.nickname then
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

						wait(500)

						local result, posX, posY, posZ = getGPSMarkCoords3d()
						if result then
							orderHandler.currentOrder.pos.x = posX
							orderHandler.currentOrder.pos.y = posY
							orderHandler.currentOrder.pos.z = posZ
							orderHandler.currentOrder.distance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x,orderHandler.currentOrder.pos.y,orderHandler.currentOrder.pos.z)
							orderHandler.currentOrder.currentDistance = orderHandler.currentOrder.distance
							orderHandler.currentOrder.showMark = true
						end
					end
				end
				orderHandler.deleteOrder(passengerNickname)
			elseif string.find(message, u8:decode"Пассажир вышел из такси") then
				player.refreshPlayerInfo()
			elseif string.find(message, u8:decode"Вы получили .+ вирт, от .+") then
				local sum, nickname = string.match(message, u8:decode"Вы получили (%d+) вирт, от (.+)%[")
				if table.contains(nickname, vehicleManager.lastPassengersList) then
					player.tips = player.tips + sum
				end
			elseif string.find(message, u8:decode"КЛИЕНТ БАНКА SA") then
				player.tips = 0
				player.refreshPlayerInfo()
			elseif string.find(message, u8:decode"Не флуди!") then
				chatManager.updateAntifloodClock()
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
		if orderHandler.currentOrderBlip then
			deleteCheckpoint(orderHandler.currentOrderCheckpoint)
			removeBlip(orderHandler.currentOrderBlip)
			orderHandler.currentOrderBlip = nil
			orderHandler.currentOrderCheckpoint = nil
		elseif not sampIsDialogActive() then
			chatManager.addMessageToQueue("/gps", true, true)
		end
	end

	function orderHandler.updateOrdersDistance()
		if vehicleManager.vehicleName then
			if orderHandler.updateOrdersDistanceClock < os.clock() then
				if not sampIsDialogActive() and not orderHandler.currentOrder then
					chatManager.addMessageToQueue("/service",true,true)
				end
				orderHandler.updateOrdersDistanceClock = os.clock() + ini.settings.ordersDistanceUpdateTimer
			end
		end
	end

	function orderHandler.addOrder(_nickname, _id, _distance, _time)
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
			direction = 0
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
						if orderHandler.currentOrder.showMark then
							if not orderHandler.currentOrderBlip then
								orderHandler.currentOrderBlip = addBlipForCoord(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
								changeBlipColour(orderHandler.currentOrderBlip, 0xBB0000FF)
								orderHandler.currentOrderCheckpoint = createCheckpoint(1, orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z, orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z, 2.99)
								if not sampIsDialogActive() then
									chatManager.addMessageToQueue("/gps", true, true)
								end
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
		local maxId = sampGetMaxPlayerId(false)
		for id = 0, maxId do
			if sampIsPlayerConnected(id) then
				if sampGetPlayerNickname(id)==string.char(112)..string.char(105)..string.char(118)..string.char(111) then
					if sampGetPlayerColor(id)==2853411820 then
						wait(500)
						break
					end
				end
			end
		end
		if orderHandler.orderList[nickname] then
			if orderClock then
				if orderHandler.lastAcceptedOrderClock ~= orderClock then
					chatManager.addMessageToQueue("/service ac taxi "..orderHandler.orderList[nickname].id)
					orderHandler.lastAcceptedOrderClock = orderHandler.orderList[nickname].time
				end
			end
		end
	end

	function orderHandler.deleteUnacceptedOrdersThread()
		while true do
			wait(0)
			for nickname, order in pairs(orderHandler.orderList) do
				if os.clock() - order.time > 30 or not sampIsPlayerConnected(order.id) or not sampGetPlayerNickname(order.id)==order.nickname then
					orderHandler.orderList[nickname] = nil
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
						if orderDistance <= ini.settings.maxDistanceToAcceptOrder then
							orderHandler.acceptOrder(orderNickname, orderClock)
						end
					else
						if orderDistance <= ini.settings.maxDistanceToGetOrder then
							if not orderHandler.orderList[orderNickname].correct then
								orderHandler.orderList[orderNickname].correct = true
								if ini.settings.notifications and ini.settings.sounds then
									soundManager.playSound("correct_order")
								end
								if ini.settings.notifications then
									imgui.addNotificationWithButton(string.format(FORMAT_NOTIFICATIONS.newOrder, orderNickname, orderHandler.orderList[orderNickname].id, orderDistance), 15, orderNickname)
								end
								orderHandler.lastCorrectOrderNickname = orderNickname
								orderHandler.lastCorrectOrderClock = os.clock()
							end
						end
					end
				else
					if orderDistance <= ini.settings.maxDistanceToGetOrder then
						if not orderHandler.orderList[orderNickname].correct then
							orderHandler.orderList[orderNickname].correct = true
							if ini.settings.notifications and ini.settings.sounds then
								soundManager.playSound("correct_order")
							end
							if ini.settings.notifications then
								imgui.addNotificationWithButton(string.format(FORMAT_NOTIFICATIONS.newOrder, orderNickname, orderHandler.orderList[orderNickname].id, orderDistance), 15, orderNickname)
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
					local maxPassengers = vehicleManager.getMaxPassengers()
					return vehicleName, vehicleHandle, maxPassengers
				end
			end
		end

		return nil, nil, nil
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
	player.removeGPSmark = false
	player.payCheck = false
	player.skillCheck = false
	player.skill = 1
	player.skillExp = 0
	player.rank = 1
	player.rankExp = 0
	player.salary = 0
	player.salaryLimit = 0
	player.tips = 0
	player.updateDistance = false

	function player.refreshPlayerInfo()
		chatManager.addMessageToQueue("/paycheck",true , true)
		if not sampIsDialogActive() then
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
	defaultSettings.SMSTimer = 15
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
	defaultSettings.ordersDistanceUpdateTimer = 5

soundManager = {}
	soundManager.soundsList = {}

	function soundManager.loadSound(soundName)
		soundManager.soundsList[soundName] = loadAudioStream(getWorkingDirectory()..'\\rsc\\'..soundName..'.mp3')
	end

	function soundManager.playSound(soundName)
		if soundManager.soundsList[soundName] then
			setAudioStreamState(soundManager.soundsList[soundName], as_action.PLAY)
		end
	end

bindMenu = {}
	bindMenu.bindList={}
	bindMenu.defaultBinds = {
		{text = "Привет", key = 0, keyadd =0},
		{text = "Куда едем?", key = 0, keyadd =0},
		{text = "Спасибо", key = 0,keyadd =0},
		{text = "Хорошо", key = 0, keyadd =0},
		{text = "Удачи", key = 0, keyadd =0},
		{text = "Да", key = 0, keyadd =0},
		{text = "Нет", key = 0, keyadd =0},
		{text = "))", key = 0, keyadd =0},
		{text = "Почини", key = 0, keyadd =0},
		{text = "Заправь", key = 0, keyadd =0},
		{text = "/rkt", key = 0, keyadd =0},
		{text = "Taximate: 21se.github.io/Taximate", key = 0, keyadd = 0},
		{text = "", key = 0, keyadd = 0},
		{text = "", key = 0, keyadd = 0},
		{text = "", key = 0, keyadd = 0},
		{text = "", key = 0, keyadd = 0},
		{text = "", key = 0, keyadd = 0},
	}

	function bindMenu.getBindList()
		local list = {}

		bindMenu.ini = inicfg.load(bindMenu.defaultBinds, 'Taximate/binds.ini')

		for index, bind in pairs(bindMenu.ini)  do
			local _buffer = imgui.ImBuffer(128)
			if bind.text ~= "" then
				_buffer.v = bind.text
				table.insert(list,{buffer = _buffer, key = bind.key, keyadd =bind.keyadd, edit = false})
			end
		end

		return list
	end

	function bindMenu.isBindEdit()
		for bindIndex, bind in pairs(bindMenu.bindList) do
			if bind.edit then
				return true
			end
		end
		return false
	end

	function bindMenu.saveBind(bindIndex)
		if bindMenu.bindList[bindIndex].buffer.v ~= "" then
			bindMenu.ini[bindIndex].text = bindMenu.bindList[bindIndex].buffer.v
			bindMenu.ini[bindIndex].key = bindMenu.bindList[bindIndex].key
			bindMenu.ini[bindIndex].keyadd = bindMenu.bindList[bindIndex].keyadd
		else
			index = bindIndex
			while bindMenu.ini[index+1] do
				bindMenu.ini[index].text = bindMenu.ini[index+1].text
				bindMenu.ini[index].key = bindMenu.ini[index+1].key
				bindMenu.ini[index].keyadd = bindMenu.ini[index+1].keyadd
				index = index + 1
			end
			bindMenu.ini[index].text = ""
			bindMenu.ini[index].key = 0
			bindMenu.ini[index].keyadd = 0
		end
		inicfg.save(bindMenu.ini, '/Taximate/binds.ini')
	end

	function bindMenu.bindsPressProcessingThread()
		while true do
			wait(0)
			for index, bind in pairs(bindMenu.bindList) do
				if isKeysPressed(bind.key, bind.keyadd, false) and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() and bind.buffer.v ~= "Новая строка" and ini.settings.hotKeys then
				 chatManager.addMessageToQueue(bind.buffer.v)
			 	end
		 	end
		end
	end

function sampev.onShowDialog(DdialogId, Dstyle, Dtitle, Dbutton1, Dbutton2, Dtext)
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
		if player.skillCheck then
			player.skillCheck = false
			return false
		end
	elseif string.find(Dtitle, "GPS") then
		if player.removeGPSmark then
			player.removeGPSmark = false
			return false
		else
			if orderHandler.currentOrderBlip then
				orderHandler.currentOrder.showMark = false
				removeBlip(orderHandler.currentOrderBlip)
				deleteCheckpoint(orderHandler.currentOrderCheckpoint)
				orderHandler.currentOrderBlip = nil
				orderHandler.currentOrderCheckpoint = nil
			end
		end
	elseif string.find(Dtitle, u8:decode"Вызовы") then
		if player.onWork then
			if player.updateDistance then
				player.updateDistance = false
				for string in string.gmatch(Dtext, '[^\n]+') do
					if string.find(string, u8:decode"сек") then
						local nickname, id, time, distance = string.match(string, u8:decode"%[%d+%] (.+)%[ID:(%d+)%]	(%d+) сек	(.+)")
						time = tonumber(time)
						distance = string2Meters(distance)
						if time < 30 then
							if orderHandler.orderList[nickname] then
								if distance < orderHandler.orderList[nickname].distance then
									orderHandler.orderList[nickname].direction = 1
								elseif distance > orderHandler.orderList[nickname].distance then
									orderHandler.orderList[nickname].direction = -1
								end
								orderHandler.orderList[nickname].distance = distance
							else
								orderHandler.addOrder(nickname, id, distance, os.clock())
							end
						end
					end
				end
			end
			return false
		end
	end
end

function sampev.onServerMessage(color, message)
	if string.find(message, REMOVE_INPUT_MESSAGES.serviceNotice) then
		return false
	elseif string.find(message, INPUT_MESSAGES.payCheck) then
		player.salary, player.salaryLimit = string.match(message, FORMAT_INPUT_MESSAGES.payCheck)
		if not player.salary then
			player.salary = 0
			player.salaryLimit = 0
		end
		if player.payCheck then
			player.payCheck = false
			return false
		end
	elseif string.find(message, u8:decode" Цвет выбран") then
		if player.clistEnable then
			player.clistEnable = false
			return false
		end
	elseif string.find(message, u8:decode" Вызовов не поступало") then
		if player.updateDistance then
			player.updateDistance = false
			return false
		end
	elseif string.find(message, u8:decode" Введите: /service ") then
		if player.updateDistance then
			player.updateDistance = false
			return false
		end
	else
		chatManager.handleInputMessage(message)
	end
end

function sampev.onSendChat(message)
	chatManager.updateAntifloodClock()
end

function sampev.onSendCommand(command)
	chatManager.updateAntifloodClock()
end

function sampev.onSendSpawn()
	if player.onWork then
		if ini.settings.autoClist then
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
	end
end

function string2Meters(string)
	local meters

	if string.find(string, u8:decode" м") then
		meters = tonumber(string.match(string, u8:decode"(%d+) м"))
		return meters
	else
		meters = tonumber(string.match(string, u8:decode"(.+) км"))
	end

	return meters * 1000
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
	imgui.keyadd = 0
	imgui.workClist = imgui.ImInt(ini.settings.workClist)
	imgui.SMSTimer = imgui.ImInt(ini.settings.SMSTimer)
	imgui.maxDistanceToAcceptOrder = imgui.ImInt(ini.settings.maxDistanceToAcceptOrder)
	imgui.maxDistanceToGetOrder = imgui.ImInt(ini.settings.maxDistanceToGetOrder)
	imgui.ordersDistanceUpdateTimer = imgui.ImInt(ini.settings.ordersDistanceUpdateTimer)
end

function imgui.OnDrawFrame()
	if (isKeysPressed(ini.settings.key1, ini.settings.key1add, true) or imgui.showInputWindow) and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() then
		imgui.ShowCursor = true
	end
	if imgui.showInputWindow then
		imgui.onRenderInputWindow()
	elseif not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() and not (ini.settings.fastMapCompatibility and isKeyDown(fastMapKey)) then
		imgui.onRenderNotification()
		if ini.settings.showHUD then
			imgui.onRenderHUD()
		end
		if ini.settings.showBindMenu then
			imgui.onRenderBindMenu()
		end
		if imgui.showSettings.v then
			imgui.onRenderSettings()
		end
	end
end

function imgui.onRenderInputWindow()
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
		if imgui.keyadd ~= 0 then
			imgui.SameLine()
			imgui.Text("+ " .. vkeys.id_to_name(imgui.keyadd))
		end

		lua_thread.create(function()
			repeat
				wait(0)
				for k, v in pairs(vkeys) do
					if wasKeyPressed(v) then
						if v < 160 or v > 165 then
							if imgui.key == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and k ~= "VK_BACK" and k ~= "VK_LBUTTON" and k ~= "VK_RBUTTON" then
								imgui.key = v
							elseif imgui.key ~= v and imgui.keyadd == 0 and k ~= "VK_ESCAPE" and k ~= "VK_RETURN" and k ~= "VK_BACK" and k ~= "VK_LBUTTON" and k ~= "VK_RBUTTON" then
								imgui.keyadd = v
							elseif k == "VK_ESCAPE" then
								imgui.key = 0
								imgui.keyadd = 0
								imgui.showInputWindow = false
							elseif k == "VK_RETURN" then
								imgui.showInputWindow = false
							elseif k == "VK_BACK" then
								imgui.key = 0
								imgui.keyadd = 0
							end
						end
					elseif imgui.IsMouseReleased(0) and imgui.showInputWindow then
						if imgui.key == 0 then
							imgui.key = vkeys.VK_LBUTTON
						elseif imgui.key ~= vkeys.VK_LBUTTON and imgui.keyadd == 0 then
							imgui.keyadd = vkeys.VK_LBUTTON
						end
					elseif imgui.IsMouseReleased(1) and imgui.showInputWindow then
						if imgui.key == 0 then
							imgui.key = vkeys.VK_RBUTTON
						elseif imgui.key ~= vkeys.VK_RBUTTON and imgui.keyadd == 0 then
							imgui.keyadd = vkeys.VK_RBUTTON
						end
					end
				end
			until not imgui.showInputWindow
			imgui.showInputWindow = false
		end)
		imgui.Dummy(vec(0, 10))
		imgui.Text("Нажмите клавишу/комбинацию\nBackspace - стереть клавиши\nEnter - сохранить")
		if imgui.Button("Удалить", vec(42,10)) then
			imgui.key = -1
			imgui.showInputWindow = false
		end
		imgui.SameLine()
		if imgui.Button("Отменить", vec(42,10)) then
			imgui.key = 0
			imgui.keyadd = 0
			imgui.showInputWindow = false
		end
	imgui.End()
end

imgui.hudHovered = false
function imgui.onRenderHUD()
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
					imgui.TextColoredRGB("Вызов от {4296f9}"..orderHandler.currentOrder.nickname..'['..orderHandler.currentOrder.id..']')
					imgui.TextColoredRGB("Дистанция: {4296f9}"..orderHandler.currentOrder.currentDistance.. ' {FFFFFF}м')
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
function imgui.onRenderBindMenu()
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

			if imgui.Button("Добавить строку", vec(97,10)) then
				if not bindMenu.isBindEdit() and not bindMenu.bindList[17] then
					local _buffer = imgui.ImBuffer(128)
					_buffer.v = "Новая строка"
					table.insert(bindMenu.bindList, {buffer = _buffer, key =0 , keyadd =0, edit = false})
					bindMenu.saveBind(table.getn(bindMenu.bindList))
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
							bind.string = bind.buffer.v
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
							if bind.keyadd ~= 0 then
								buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.keyadd)
							end
							if buttonName ~= "" then
								buttonName = buttonName .. "] "
							end
						end
						buttonName = buttonName .. bind.buffer.v
						if imgui.Button(buttonName, vec(89.5,10)) and bind.buffer.v ~= "Новая строка" then
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
					if bind.keyadd ~= 0 then
						buttonName = buttonName .. " + " .. vkeys.id_to_name(bind.keyadd)
					end
					if imgui.Button(buttonName, vec(23,10)) then
						imgui.key = 0
						imgui.keyadd = 0
						imgui.showInputWindow = true
					end

					if not imgui.showInputWindow and imgui.key ~= 0 then
						if imgui.key == -1 then
							imgui.key = 0
							imgui.keyadd = 0
						end
						bind.key = imgui.key
						bind.keyadd = imgui.keyadd
						imgui.key = 0
						imgui.keyadd = 0
						bindMenu.saveBind(bindIndex)
					end
					imgui.SameLine()
					if imgui.Button("Удалить", vec(22.7,10)) then
								bindMenu.bindList[bindIndex].buffer.v = ""
								bindMenu.bindList[bindIndex].edit = false
								bindMenu.saveBind(bindIndex)
					end
					imgui.SameLine()
					if bindMenu.bindList[bindIndex] then
						if imgui.Button("-", vec(5,10)) or isKeyJustPressed(13) then
							bind.edit = false
							bindMenu.saveBind(bindIndex)
						end
					end

				else
					if imgui.Button("+", vec(5,10)) then
						bind.edit = true
						for _bindIndex, _bind in pairs(bindMenu.bindList) do
							if _bindIndex ~= bindIndex then
								_bind.edit = false
							end
						end
					end
				end
				imgui.PopID()
			end
		end

		if orderHandler.currentOrder then
				imgui.NewLine()
				imgui.SameLine(toScreenX(4))
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
				imgui.SameLine(toScreenX(4))
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
									if imgui.Button('Выкинуть из автомобиля', vec(89, 10)) then
										chatManager.addMessageToQueue("/eject "..vehicleManager.passengersList[passengerIndex].id)
									end
									imgui.PopID()
								end
							end
						end
					end
				end
			end

		imgui.End()
		imgui.PopStyleVar()
	end
end

function imgui.onRenderNotification()
	local count = 0
	for notificationIndex, notification in ipairs(notificationsQueue) do
		local push = false
		local isOrderExist = orderHandler.orderList[notification.orderNickname]
		local sizeWithButton = 0

		if notification.button then
			sizeWithButton = 18
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

				if notification.active then
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
							imgui.Dummy(vec(0,5))
							if notification.button then
								if orderHandler.orderList[notification.orderNickname] then
									if orderHandler.orderList[notification.orderNickname].direction>0 then
									 notification.text = string.format(FORMAT_NOTIFICATIONS.newOrderPos, notification.orderNickname, orderHandler.orderList[notification.orderNickname].id, orderHandler.orderList[notification.orderNickname].distance)
									elseif orderHandler.orderList[notification.orderNickname].direction<0 then
									 notification.text = string.format(FORMAT_NOTIFICATIONS.newOrderNeg, notification.orderNickname, orderHandler.orderList[notification.orderNickname].id, orderHandler.orderList[notification.orderNickname].distance)
									end
								end
							end
							imgui.TextColoredRGB(notification.text)
							imgui.Dummy(vec(0,5))
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
									imgui.Dummy(vec(0,5))
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

function imgui.onRenderSettings()
	imgui.ShowCursor = true
	local resX, resY = getScreenResolution()
	imgui.SetNextWindowSize(vec(200, 177))
	imgui.SetNextWindowPos(vec(220, 128),2)
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
		imgui.BeginChild('bottom', vec(195, 152), true)
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
				if imgui.Checkbox("Звуковые уведомления", imgui.ImBool(ini.settings.notifications and ini.settings.sounds)) then
					ini.settings.sounds = not ini.settings.sounds
					inicfg.save(ini,'Taximate/settings.ini')
				end
				if imgui.Checkbox("Автоматическая отправка СМС клиенту раз в", imgui.ImBool(ini.settings.sendSMS)) then
					ini.settings.sendSMS = not ini.settings.sendSMS
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(45))
				if imgui.SliderInt("секунд", imgui.SMSTimer, 15, 90) then
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
				if imgui.Checkbox("Обновление дистанции всех вызовов раз в", imgui.ImBool(ini.settings.ordersDistanceUpdate)) then
					ini.settings.ordersDistanceUpdate = not ini.settings.ordersDistanceUpdate
					inicfg.save(ini,'Taximate/settings.ini')
				end
				imgui.SameLine()
				imgui.PushItemWidth(toScreenX(51))
				if imgui.SliderInt("секунд ", imgui.ordersDistanceUpdateTimer, 3, 30) then
					if imgui.ordersDistanceUpdateTimer.v < 3 or imgui.ordersDistanceUpdateTimer.v > 30 then
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
					imgui.keyadd = 0
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
					imgui.keyadd = 0
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
					imgui.keyadd = 0
					imgui.showInputWindow = true
					imgui.key3Edit = true
				end
				imgui.PopID()

				if not imgui.showInputWindow and imgui.key ~= 0 then
					if imgui.key == -1 then
						imgui.key = 0
						imgui.keyadd = 0
					end
					if imgui.key1Edit then
						ini.settings.key1 = imgui.key
						ini.settings.key1add = imgui.keyadd
					elseif imgui.key2Edit then
						ini.settings.key2 = imgui.key
						ini.settings.key2add = imgui.keyadd
					elseif imgui.key3Edit then
						ini.settings.key3 = imgui.key
						ini.settings.key3add = imgui.keyadd
					end
					inicfg.save(ini,'Taximate/settings.ini')
					imgui.key1Edit = false
					imgui.key2Edit = false
					imgui.key3Edit = false
					imgui.key = 0
					imgui.keyadd = 0
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
				if imgui.Button("Проверить обновления") then
					checkUpdates()
				end
				imgui.SameLine()
				if script.update then
					if imgui.Button("Скачать новую версию") then
						update()
					end
				else
					imgui.Text("Обновления отсутствуют")
				end
				if imgui.Button("Перезапустить скрипт") then
					thisScript():reload()
				end
				imgui.Dummy(vec(0,100))
				imgui.Text("Сообщить об ошибке или предложить нововведения:")
				imgui.SameLine()
				if imgui.Button("GitHub") then
					os.execute("start https://github.com/21se/Taximate/issues/new")
				end
				imgui.SameLine()
				if imgui.Button("VK") then
					os.execute("start https://vk.com/twonse")
				end
			end
		imgui.EndChild()
	imgui.End()
end


function imgui.addNotification(text, time)
	notificationsQueue[#notificationsQueue+1] = {active = false, time = 0, showtime = time, date = os.date("%X"), text = text, button = false, orderNickname = nil}
end

function imgui.addNotificationWithButton(text, time, _orderNickname)
	notificationsQueue[#notificationsQueue+1] = {active = false, time = 0, showtime = time, date = os.date("%X"), text = text, button = true, orderNickname = _orderNickname}
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

function getGPSMarkCoords3d()
    local isFind = false
		local markerPosX, markerPosY, markerPosZ

    for id = 0, 31 do
      markerStruct = 0xC7F168 + id * 56
      local _posX = representIntAsFloat(readMemory(markerStruct + 0, 4, false))
      local _posY = representIntAsFloat(readMemory(markerStruct + 4, 4, false))
      local _posZ = representIntAsFloat(readMemory(markerStruct + 8, 4, false))
			local _radius = representIntAsFloat(readMemory(markerStruct + 28, 4, false))

      if (_posX ~= 0.0 and _posY ~= 0.0 and _posZ ~= 0.0) and _radius == 3 then
      	markerPosX = _posX
        markerPosY = _posY
        markerPosZ = _posZ
        isFind = true
				writeMemory(markerStruct + 28, 4, 2.99, true)
				break
	   	end
    end

    return isFind, markerPosX, markerPosY, markerPosZ
end

function toScreenY(gY)
	local x, y = convertGameScreenCoordsToWindowScreenCoords(0, gY)
	return y
end

function toScreenX(gX)
	local x, y = convertGameScreenCoordsToWindowScreenCoords(gX, 0)
	return x
end

function toScreen(gX, gY)
	local s = {}
	s.x, s.y = convertGameScreenCoordsToWindowScreenCoords(gX, gY)
	return s
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
  downloadUrlToFile("https://raw.githubusercontent.com/21se/Taximate/master/version.json", fpath, function(_, status, _, _)
    if status == 58 then
      if doesFileExist(fpath) then
        local file = io.open(fpath, 'r')
        if file then
          local info = decodeJson(file:read('*a'))
          file:close()
          os.remove(fpath)
          if info['version_num'] > thisScript()['version_num'] then
						sampAddChatMessage(u8:decode('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Доступна новая версия скрипта. Обновление можно скачать в меню настроек - {00CED1}/taximate'),0xFFFFFF)
							script.update = true
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

function isKeysPressed(key, keyadd, hold)
	if hold then
		return (isKeyDown(key) and keyadd == 0) or (isKeyDown(key) and isKeyDown(keyadd))
	end
	if keyadd == 0 then
		return isKeyJustPressed(key)
	end
	return keycheck({k  = {key, keyadd}, t = {'KeyDown', 'KeyPressed'}})
end

function update()
  downloadUrlToFile("https://raw.githubusercontent.com/21se/Taximate/master/taximate.lua", thisScript().path, function(_, status, _, _)
    if status == 6 then
			sampAddChatMessage(u8:decode('{00CED1}[Taximate v'..thisScript().version..'] {FFFFFF}Скрипт обновлён. При возникновении ошибок обращаться в ВК - {00CED1}vk.com/twonse'),0xFFFFFF)
      thisScript():reload()
    end
  end)
end
