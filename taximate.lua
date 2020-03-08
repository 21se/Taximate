script_name('Taximate')
script_author("21se")
script_version('1.0.3')
script_version_number(4)
script.update = false

local inicfg = require 'inicfg'
local ini = {}
local sampev = require 'lib.samp.events'
local imgui = require 'imgui'
local as_action = require 'moonloader'.audiostream_state
local encoding = require 'encoding'
			encoding.default = 'CP1251'
local u8 = encoding.UTF8
local toScreen = convertGameScreenCoordsToWindowScreenCoords
local notificationsQueue = {}
local sX, sY = toScreen(630, 438)

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
	payCheck = u8:decode(" Вы заработали .+ / .+ вирт. Деньги будут зачислены на ваш банковский счет в .+")
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
	orderAccepted = "Принят вызов от {4296f9}%s[%s]\nДистанция: {4296f9}%s {FFFFFF}м"
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

	if not doesDirectoryExist(getWorkingDirectory()..'\\config') then createDirectory(getWorkingDirectory()..'\\config') end
	if not doesDirectoryExist(getWorkingDirectory()..'\\config\\Taximate') then createDirectory(getWorkingDirectory()..'\\config\\Taximate') end
	ini = inicfg.load({settings = defaultSettings}, 'Taximate/settings.ini')
	imgui.initBuffers()
	soundManager.loadSound("new_order")
	soundManager.loadSound("correct_order")
	soundManager.loadSound("new_passenger")
	imgui.ApplyCustomStyle()
	imgui.GetIO().Fonts:Clear()
	imgui.GetIO().Fonts:AddFontFromFileTTF("C:\\Windows\\Fonts\\arial.ttf", 18.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
	imgui.smallFont = imgui.GetIO().Fonts:AddFontFromFileTTF("C:\\Windows\\Fonts\\arial.ttf", 16.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
	imgui.RebuildFonts()
	imgui.Process = true
	chatManager.initQueue()
	player.refreshPlayerInfo()
  lua_thread.create(chatManager.checkMessagesQueueThread)
	lua_thread.create(vehicleManager.refreshVehicleInfoThread)
	lua_thread.create(orderHandler.deleteUnacceptedOrdersThread)
	sampRegisterChatCommand("taximate", function() imgui.showSettings.v = not imgui.showSettings.v end)
	if ini.settings.checkUpdates then
		lua_thread.create(checkUpdates)
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
		else
			if orderHandler.currentOrder then
				orderHandler.cancelCurrentOrder()
			end
		end


		if ((isKeyJustPressed(88) and isKeyDown(82)) or (isKeyJustPressed(82) and isKeyDown(88))) and ini.settings.hotKeys then
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


		if player.onWork then
			if not orderHandler.currentOrder then
				if orderHandler.lastCorrectOrderNickname then
					if ((isKeyJustPressed(88) and isKeyDown(160)) or (isKeyJustPressed(160) and isKeyDown(88))) and ini.settings.hotKeys then
						orderHandler.acceptOrder(orderHandler.lastCorrectOrderNickname, orderHandler.lastCorrectOrderClock)
					end
				end
			else
				if ((isKeyJustPressed(88) and isKeyDown(160)) or (isKeyJustPressed(160) and isKeyDown(88))) and ini.settings.hotKeys then
					orderHandler.cancelCurrentOrder()
				end
			end
		end

		if player.onWork then
			if orderHandler.currentOrder then
				chatManager.sendTaxiNotification(orderHandler.currentOrder)
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
				if chatManager.messagesQueue[messageIndex].message ~= '' and os.clock() - chatManager.antifloodClock > ini.settings.antifloodDelay then
					if chatManager.messagesQueue[messageIndex].hideResult then
						if string.find(chatManager.messagesQueue[messageIndex].message, '/jskill') then
							player.skillCheck = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/paycheck') then
							player.payCheck = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/clist') then
							player.clistEnable = true
						elseif string.find(chatManager.messagesQueue[messageIndex].message,'/gps') then
							player.removeGPSmark = true
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
		if ini.settings.sendSMS and vehicleManager.vehicleName then
			if not currentOrder.arrived then
				if currentOrder.SMSClock < os.clock() then
					chatManager.addMessageToQueue(string.format(FORMAT_TAXI_SMS.onWay, currentOrder.id, vehicleManager.vehicleName, currentOrder.currentDistance))
					currentOrder.SMSClock = os.clock() + ini.settings.SMSTimer
				elseif currentOrder.currentDistance < 30 then
					chatManager.addMessageToQueue(string.format(FORMAT_TAXI_SMS.arrived, currentOrder.id, vehicleManager.vehicleName))
					currentOrder.arrived = true
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
						end
					elseif orderHandler.orderList[passengerNickname] then
						if ini.settings.notifications and ini.settings.sounds then
							soundManager.playSound("new_order")
						end
						if ini.settings.notifications then
							imgui.addNotification(string.format(FORMAT_NOTIFICATIONS.orderAccepted, orderHandler.orderList[passengerNickname].nickname, orderHandler.orderList[passengerNickname].id, orderHandler.orderList[passengerNickname].distance), 10)
						end
						orderHandler.currentOrder = orderHandler.orderList[passengerNickname]

						result, posX, posY, posZ = getGPSMarkCoords3d()
						if result then
							orderHandler.currentOrder.pos.x = posX
							orderHandler.currentOrder.pos.y = posY
							orderHandler.currentOrder.pos.z = posZ
						end

						orderHandler.currentOrder.distance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x,orderHandler.currentOrder.pos.y,orderHandler.currentOrder.pos.z)

						orderHandler.currentOrder.SMSClock = os.clock()
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
		orderHandler.currentOrder = nil
		if orderHandler.currentOrderBlip then
			deleteCheckpoint(orderHandler.currentOrderCheckpoint)
			removeBlip(orderHandler.currentOrderBlip)
			orderHandler.currentOrderBlip = nil
			orderHandler.currentOrderCheckpoint = nil
		else
			chatManager.addMessageToQueue("/gps", true, true)
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
			showMark = true,
			SMSClock = os.clock()-ini.settings.SMSTimer,
			arrived = false
		}
	end

	function orderHandler.refreshCurrentOrder()
		if orderHandler.currentOrder then
			if vehicleManager.vehicleName then
				local charInStream, charHandle = sampGetCharHandleBySampPlayerId(orderHandler.currentOrder.id)
				if charInStream and ini.settings.updateOrderMark then
					orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z = getCharCoordinates(charHandle)
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
				orderHandler.currentOrder.currentDistance = getDistanceToCoords3d(orderHandler.currentOrder.pos.x, orderHandler.currentOrder.pos.y, orderHandler.currentOrder.pos.z)
				if vehicleManager.isPassengerInVehicle(vehicleManager.vehicleHandle, orderHandler.currentOrder.nickname) then
					orderHandler.currentOrder = nil
				end
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
				if os.clock() - order.time > ini.settings.deleteOrderDelay then
					orderHandler.orderList[nickname] = nil
				end
			end
		end
	end

	function orderHandler.getOrder()
		for keyIndex, key in ipairs(table.getTableKeysSortedByValue(orderHandler.orderList, "distance", true)) do
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
		elseif orderNickname == orderHandler.currentOrder.nickname and ini.settings.acceptRepeatOrder then
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
		for seatIndex = 0, 2 do
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

	function player.refreshPlayerInfo()
		chatManager.addMessageToQueue("/paycheck",true , true)
		chatManager.addMessageToQueue("/jskill", true, true)
	end

defaultSettings = {}
	defaultSettings.checkUpdates = true
	defaultSettings.showHUD = true
	defaultSettings.showBindMenu = true
	defaultSettings.sounds = true
	defaultSettings.notifications = true
	defaultSettings.sendSMS = true
	defaultSettings.updateOrderMark = true
	defaultSettings.acceptRepeatOrder = true
	defaultSettings.autoClist = true
	defaultSettings.workClist = 19
	defaultSettings.acceptLastPassengersOrders = false
	defaultSettings.hotKeys = true
	defaultSettings.SMSTimer = 15
	defaultSettings.maxDistanceToAcceptOrder = 1400
	defaultSettings.maxDistanceToGetOrder = 1000
	defaultSettings.antifloodDelay = 1.0
	defaultSettings.deleteOrderDelay = 30

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
	bindMenu.bindList = {}

	function bindMenu.getBindList()
		local list = {}

		if doesFileExist(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt') then
			local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', 'r')
			for line in file:lines() do
				local _buffer = imgui.ImBuffer(128)
			  _buffer.v = line
				table.insert(list,{buffer = _buffer, edit = false})
			end
			io.close(file)
		else

			local text = "Привет\nКуда едем?\nСпасибо\nХорошо\nУдачи\nДа\nНет\n))\nПочини\nЗаправь\n/rkt"
			local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "w")
			file:write(text)
			io.close(file)

			local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', 'r')
			for line in file:lines() do
				local _buffer = imgui.ImBuffer(128)
				_buffer.v = line
				table.insert(list,{buffer = _buffer, edit = false})
			end
			io.close(file)
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

	function bindMenu.saveBind(bindIndex, bind)
		bind.edit = false
		local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "r")
		local bindText = ''
		if file ~= nil then
			for _bindIndex, _bind in pairs(bindMenu.bindList) do
				bindText = bindText.._bind.buffer.v.."\n"
			end
			bindMenu.bindList[bindIndex] = nil
			io.close(file)
		end

		file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "w")
		file:write(bindText)
		file:flush()
		io.close(file)
	end

	function bindMenu.deleteBind(bindIndex)
		local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "r")
		local bindText = ''
		if file ~= nil then
			for _bindIndex, _bind in pairs(bindMenu.bindList) do
				if _bindIndex ~= bindIndex then
					bindText = bindText.._bind.buffer.v.."\n"
				end
			end
			bindMenu.bindList[bindIndex] = nil
			io.close(file)
		end

		file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "w")
		file:write(bindText)
		file:flush()
		io.close(file)
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
	elseif Dstyle == 2 and string.find(Dtitle, "GPS") then
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
	end
end

function sampev.onServerMessage(color, message)
	if string.find(message, REMOVE_INPUT_MESSAGES.serviceNotice) then
		return false
	elseif string.find(message, INPUT_MESSAGES.payCheck) then
		player.salary, player.salaryLimit = string.match(message, FORMAT_INPUT_MESSAGES.payCheck)
		if player.payCheck then
			player.payCheck = false
			return false
		end
	elseif string.find(message, u8:decode" Цвет выбран") then
		if player.clistEnable then
			player.clistEnable = false
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

function onScriptTerminate(script, quitGame)
	if script == thisScript() then
		removeBlip(orderHandler.currentOrderBlip)
		deleteCheckpoint(orderHandler.currentOrderCheckpoint)
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

imgui.settingsTab = 1
imgui.showSettings = imgui.ImBool(false)

function imgui.initBuffers()
	imgui.antifloodDelayBuffer = imgui.ImBuffer(4)
	imgui.deleteOrderDelayBuffer = imgui.ImBuffer(3)
	imgui.clistBuffer = imgui.ImBuffer(3)
	imgui.SMSTimerBuffer = imgui.ImBuffer(3)
	imgui.maxDistanceToAcceptOrderBuffer = imgui.ImBuffer(5)
	imgui.maxDistanceToGetOrderBuffer = imgui.ImBuffer(5)
	imgui.antifloodDelayBuffer.v = tostring(ini.settings.antifloodDelay)
	imgui.deleteOrderDelayBuffer.v = tostring(ini.settings.deleteOrderDelay)
	imgui.clistBuffer.v = tostring(ini.settings.workClist)
	imgui.SMSTimerBuffer.v = tostring(ini.settings.SMSTimer)
	imgui.maxDistanceToAcceptOrderBuffer.v = tostring(ini.settings.maxDistanceToAcceptOrder)
	imgui.maxDistanceToGetOrderBuffer.v = tostring(ini.settings.maxDistanceToGetOrder)
end

function imgui.OnDrawFrame()
	if isKeyDown(88) and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() then
		imgui.ShowCursor = true
	end
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

function imgui.onRenderHUD()
	if vehicleManager.vehicleName or isKeyDown(88) then
		local windowSizeY = 110
		local windowPosY = 0
		if orderHandler.currentOrder then
			windowSizeY = 200
			windowPosY = 90
		end
		imgui.SetNextWindowPos(imgui.ImVec2(sX - 395,sY - 320-windowPosY))
		imgui.SetNextWindowSize(imgui.ImVec2(notfList.size.x, windowSizeY))
		imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
		imgui.Begin("Taximate HUD", _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoMove)

		if not player.onWork then
			local buttonText = "Начать рабочий день"
			if ini.settings.hotKeys then
				buttonText = buttonText .. " [X + R]"
			end
			if imgui.Button(buttonText, imgui.ImVec2(300, 0)) then
				player.onWork = true
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist "..ini.settings.workClist, true, true)
				end
			end
		else
			local buttonText = "Закончить рабочий день"
			if ini.settings.hotKeys then
				buttonText = buttonText .. " [X + R]"
			end
			if imgui.Button(buttonText, imgui.ImVec2(300, 0)) then
				player.onWork = false
				if ini.settings.autoClist then
					chatManager.addMessageToQueue("/clist 0", true, true)
				end
			end
		end

		imgui.BeginChild('', imgui.ImVec2(150,20), false, imgui.WindowFlags.NoScrollbar)
		imgui.TextColoredRGB("Скилл: {4296f9}"..player.skill..' {FFFFFF}('..player.skillExp..'%)')
	  imgui.EndChild()
		imgui.SameLine()
		imgui.BeginChild('right', imgui.ImVec2(0, 20), false, imgui.WindowFlags.NoScrollbar)
	 	imgui.TextColoredRGB("Ранг: {4296f9}"..player.rank..' {FFFFFF}('..player.rankExp..'%)')
		imgui.EndChild()
		imgui.BeginChild('bottom', imgui.ImVec2(170, 20), false, imgui.WindowFlags.NoScrollbar)
		imgui.TextColoredRGB("ЗП: {4296f9}" ..player.salary.. ' / '..player.salaryLimit .. '{FFFFFF} вирт')
		imgui.EndChild()
		imgui.SameLine()
		imgui.BeginChild('bottom ', imgui.ImVec2(0, 20), false, imgui.WindowFlags.NoScrollbar)
		imgui.TextColoredRGB("Чай: {4296f9}" ..player.tips .. '{FFFFFF} вирт')
		imgui.EndChild()

		if orderHandler.currentOrder then
			imgui.BeginChild('bottom  ', imgui.ImVec2(300, 0), true, imgui.WindowFlags.NoScrollbar)
			imgui.TextColoredRGB("Вызов от {4296f9}"..orderHandler.currentOrder.nickname..'['..orderHandler.currentOrder.id..']')
			imgui.TextColoredRGB("Дистанция: {4296f9}"..orderHandler.currentOrder.currentDistance.. ' {FFFFFF}м')
			local buttonText = "Отменить вызов"
			if ini.settings.hotKeys then
				buttonText = buttonText .. " [SHIFT + X]"
			end
			if imgui.Button(buttonText, imgui.ImVec2(285, 0)) then
				orderHandler.cancelCurrentOrder()
			end
			imgui.EndChild()
		end

		imgui.End()
		imgui.PopStyleVar()
	end
end

function imgui.onRenderBindMenu()
	if (isKeyDown(88) or bindMenu.isBindEdit()) and not sampIsDialogActive() and not sampIsChatInputActive() and not isPauseMenuActive() then
		if not bindMenu.isBindEdit() then
			bindMenu.bindList = bindMenu.getBindList()
		end
		imgui.ShowCursor = true
		imgui.SetNextWindowPos(imgui.ImVec2(105,250))
		imgui.SetNextWindowSize(imgui.ImVec2(315, 550))
		imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.95)
		imgui.Begin("Taximate Binder", _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + 		imgui.WindowFlags.AlwaysVerticalScrollbar)
		imgui.PushFont(imgui.smallFont)

		if imgui.Button("Добавить строку", imgui.ImVec2(289,0)) then
			if not bindMenu.isBindEdit() then
				local file = io.open(getWorkingDirectory()..'\\config\\Taximate\\bind_list.txt', "a")
				file:write(''.."\n")
				file:flush()
				io.close(file)
			end
		end

		for bindIndex, bind in pairs(bindMenu.bindList) do
			imgui.PushID(bindIndex)
			if bind.edit then
				imgui.PushItemWidth(194)
				imgui.PushStyleVar(imgui.StyleVar.FramePadding, imgui.ImVec2(15,4))
				imgui.PushID(bindIndex)
				if imgui.InputText("", bind.buffer) then
					bind.string = bind.buffer.v
				end
				imgui.PopID()
				imgui.PopStyleVar()
				imgui.PopItemWidth()
			else
				if imgui.Button(bind.buffer.v, imgui.ImVec2(265,25)) then
					chatManager.addMessageToQueue(bind.buffer.v)
				end
			end
			imgui.PopID()
			imgui.SameLine()
			imgui.PushID(bindIndex)
			if bind.edit then
				if imgui.Button("Удалить", imgui.ImVec2(0,25)) then
					bindMenu.deleteBind(bindIndex)
				end
				imgui.SameLine()
				if bindMenu.bindList[bindIndex] then
					if imgui.Button("-", imgui.ImVec2(16,25)) or isKeyJustPressed(13) then
						bindMenu.saveBind(bindIndex, bind)
					end
				end
			else
				if imgui.Button("+", imgui.ImVec2(16,25)) then
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

		if orderHandler.currentOrder then
			imgui.NewLine()
			imgui.SameLine(11)
			if imgui.CollapsingHeader('Отправить СМС клиенту', imgui.ImVec2(290, 0)) then
				imgui.NewLine()
				imgui.SameLine(30)
				if imgui.Button('Скоро буду', imgui.ImVec2(267, 0)) then
					chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Скоро буду')
				end
				imgui.NewLine()
				imgui.SameLine(30)
				if imgui.Button('Я не приеду, вызовите новое такси', imgui.ImVec2(267, 0)) then
					chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Я не приеду, вызовите новое такси')
				end
				imgui.NewLine()
				imgui.SameLine(30)
				if imgui.Button('Да', imgui.ImVec2(267, 0)) then
					chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Да')
				end
				imgui.NewLine()
				imgui.SameLine(30)
				if imgui.Button('Нет', imgui.ImVec2(267, 0)) then
					chatManager.addMessageToQueue("/sms "..orderHandler.currentOrder.id.. ' [Taxi] Нет')
				end
			end
		end


		if not table.isEmpty(vehicleManager.passengersList) then
			imgui.NewLine()
			imgui.SameLine(11)
			if vehicleManager.maxPassengers then
				if imgui.CollapsingHeader('Меню действий с пассажирами') then
					for passengerIndex = 0, vehicleManager.maxPassengers-1 do
						if vehicleManager.passengersList[passengerIndex] then
							imgui.NewLine()
							imgui.SameLine(33)
							if imgui.CollapsingHeader(vehicleManager.passengersList[passengerIndex].nickname..'['..vehicleManager.passengersList[passengerIndex].id..']', imgui.ImVec2(0, 0)) then
								imgui.NewLine()
								imgui.SameLine(60)
								imgui.PushID(passengerIndex)
								if imgui.Button('Выкинуть из автомобиля', imgui.ImVec2(237, 0)) then
									chatManager.addMessageToQueue("/eject "..vehicleManager.passengersList[passengerIndex].id)
								end
								imgui.PopID()
							end
						end
					end
				end
			end
		end

		imgui.PopFont()
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
			sizeWithButton = 50
		end

		if notification.active and (notification.time < os.clock() or (notification.button and not isOrderExist)) then
			notification.active = false
		end
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

				local notificationTitle = '{4296f9}Taximate notification\t\t\t\t\t{FFFFFF}'.. notification.date
				notfList.pos = imgui.ImVec2(notfList.pos.x, notfList.pos.y - (sizeWithButton+notfList.size.y + (count == 1 and 8 or 13)))
				imgui.SetNextWindowPos(notfList.pos, _, imgui.ImVec2(0.0, 0.0))

				imgui.SetNextWindowSize(imgui.ImVec2(315, sizeWithButton+ notfList.size.y + imgui.GetStyle().ItemSpacing.y + imgui.GetStyle().WindowPadding.y))
				imgui.Begin('message #' .. notificationIndex, _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoTitleBar)
				imgui.TextColoredRGB(notificationTitle)
				imgui.NewLine()
				imgui.TextColoredRGB(notification.text)
				imgui.NewLine()
				if notification.button then
					local acceptOrderText = "Принять вызов"
					if orderHandler.lastCorrectOrderNickname == notification.orderNickname and ini.settings.hotKeys then
						acceptOrderText = acceptOrderText .. " [SHIFT + X]"
					end
					if imgui.Button(acceptOrderText, imgui.ImVec2(300, 0))
					then
						orderHandler.acceptOrder(notification.orderNickname, orderHandler.orderList[notification.orderNickname].time)
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
	notfList = {
		pos = {
			x = sX - 395,
			y = sY - 440
		},
		npos = {
			x = sX - 200,
			y = sY
		},
		size = {
			x = 315,
			y = 90
		}
	}
	if not orderHandler.currentOrder then
		notfList.pos.y = notfList.pos.y+90
	end
end

function imgui.onRenderSettings()
	imgui.ShowCursor = true
	local resX, resY = getScreenResolution()
	imgui.SetNextWindowSize(imgui.ImVec2(600, 390), 2)
	imgui.SetNextWindowPos(imgui.ImVec2(resX/2, resY/2), 2, imgui.ImVec2(0.5, 0.5))
	imgui.Begin('Taximate '..thisScript()['version'], imgui.showSettings, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
	imgui.BeginChild('top', imgui.ImVec2(0, 20), false)
	imgui.BeginChild(" right",imgui.ImVec2(190,20), false)
	if imgui.Selectable('\t\t\t  Функции', imgui.settingsTab == 1) then
		imgui.settingsTab = 1
	end
	imgui.EndChild()
	imgui.SameLine()
	imgui.BeginChild("  right",imgui.ImVec2(190,20), false)
	if imgui.Selectable('\t\t\tПараметры', imgui.settingsTab == 2) then
		imgui.settingsTab = 2
	end
	imgui.EndChild()
	imgui.SameLine()
	imgui.BeginChild("   right",imgui.ImVec2(190,20), false)
	if imgui.Selectable('\t\tИнформация', imgui.settingsTab == 3) then
		imgui.settingsTab = 3
	end
	imgui.EndChild()
	imgui.EndChild()
	imgui.BeginChild('bottom', imgui.ImVec2(0, 0), true)
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
		imgui.PushItemWidth(25)
		if imgui.InputText("секунд", imgui.SMSTimerBuffer) then
			if tonumber(imgui.SMSTimerBuffer.v) == nil or tonumber(imgui.SMSTimerBuffer.v) < 0 or tonumber(imgui.SMSTimerBuffer.v) > 99 then
				imgui.SMSTimerBuffer.v = '15'
			end
				ini.settings.SMSTimer = tonumber(imgui.SMSTimerBuffer.v)
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
		imgui.PushItemWidth(25)
		if imgui.InputText("", imgui.clistBuffer) then
			if tonumber(imgui.clistBuffer.v) == nil or tonumber(imgui.clistBuffer.v) < 0 or tonumber(imgui.clistBuffer.v) > 33 then
				imgui.clistBuffer.v = tostring(defaultSettings.workClist)
			end
				ini.settings.workClist = '19'
			inicfg.save(ini,'Taximate/settings.ini')
		end
		imgui.PopItemWidth()
		if imgui.Checkbox("Принятие вызовов от 3-х последних пассажиров",imgui.ImBool(ini.settings.acceptLastPassengersOrders)) then
			ini.settings.acceptLastPassengersOrders = not ini.settings.acceptLastPassengersOrders
			inicfg.save(ini,'Taximate/settings.ini')
		end
		if imgui.Checkbox("Горячие клавиши",imgui.ImBool(ini.settings.hotKeys)) then
			ini.settings.hotKeys = not ini.settings.hotKeys
			inicfg.save(ini,'Taximate/settings.ini')
		end
	elseif imgui.settingsTab == 2 then
		imgui.Text("Дистанция для автопринятия вызова:")
		imgui.SameLine()
		imgui.PushItemWidth(50)
		if imgui.InputText("м ", imgui.maxDistanceToAcceptOrderBuffer) then
			if tonumber(imgui.maxDistanceToAcceptOrderBuffer.v) == nil or tonumber(imgui.maxDistanceToAcceptOrderBuffer.v) < 0 or tonumber(imgui.maxDistanceToAcceptOrderBuffer.v) > 9999 then
				imgui.maxDistanceToAcceptOrderBuffer.v = '1400'
			end
				ini.settings.maxDistanceToAcceptOrder = tonumber(imgui.maxDistanceToAcceptOrderBuffer.v)
			inicfg.save(ini,'Taximate/settings.ini')
		end
		imgui.Text("Дистанция для получения доп. вызова:")
		imgui.SameLine()
		imgui.PushItemWidth(50)
		if imgui.InputText("м", imgui.maxDistanceToGetOrderBuffer) then
			if tonumber(imgui.maxDistanceToGetOrderBuffer.v) == nil or tonumber(imgui.maxDistanceToGetOrderBuffer.v) < 0 or tonumber(imgui.maxDistanceToGetOrderBuffer.v) > 9999 then
				imgui.maxDistanceToGetOrderBuffer.v = '1000'
			end
				ini.settings.maxDistanceToGetOrder = tonumber(imgui.maxDistanceToGetOrderBuffer.v)
			inicfg.save(ini,'Taximate/settings.ini')
		end
		imgui.Text("Задержка антифлуда:")
		imgui.SameLine()
		imgui.PushItemWidth(30)
		if imgui.InputText("с", imgui.antifloodDelayBuffer) then
			if tonumber(imgui.antifloodDelayBuffer.v) == nil or tonumber(imgui.antifloodDelayBuffer.v) < 0 or tonumber(imgui.antifloodDelayBuffer.v) > 999 then
				imgui.antifloodDelayBuffer.v = '1.0'
			end
				ini.settings.antifloodDelay = tonumber(imgui.antifloodDelayBuffer.v)
			inicfg.save(ini,'Taximate/settings.ini')
		end
		imgui.Text("Принимать заказы не старше:")
		imgui.SameLine()
		imgui.PushItemWidth(25)
		if imgui.InputText("с ", imgui.deleteOrderDelayBuffer) then
			if tonumber(imgui.deleteOrderDelayBuffer.v) == nil or tonumber(imgui.deleteOrderDelayBuffer.v) < 0 or tonumber(imgui.deleteOrderDelayBuffer.v) > 99 then
				imgui.deleteOrderDelayBuffer.v = '30'
			end
				ini.settings.deleteOrderDelay = tonumber(imgui.deleteOrderDelayBuffer.v)
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
		imgui.NewLine()
		imgui.Text("Обратная связь в ВК - vk.com/twonse")
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
	style.ScrollbarSize = 13.0
	style.ScrollbarRounding = 0
	style.GrabMinSize = 8.0
	style.GrabRounding = 1.0

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

      if (_posX ~= 0.0 or _posY ~= 0.0 or _posZ ~= 0.0) and _radius == 3 then
      	markerPosX = _posX
        markerPosY = _posY
        markerPosZ = _posZ
        isFind = true
	   	end
    end

    return isFind, markerPosX, markerPosY, markerPosZ
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
            sampAddChatMessage(u8:decode'[Taximate] Доступна новая версия скрипта. Обновление можно скачать в меню настроек (/taximate)', 0x00CED1)
							script.update = true
            return true
          end
        end
      end
    end
  end)
end

function update()
  downloadUrlToFile("https://raw.githubusercontent.com/21se/Taximate/master/taximate.lua", thisScript().path, function(_, status, _, _)
    if status == 6 then
			sampAddChatMessage(u8:decode'[Taximate] Скрипт обновлён. При возникновении ошибок обращаться в ВК - vk.com/twonse', 0x00CED1)
      thisScript():reload()
    end
  end)
end
