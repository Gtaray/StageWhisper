
OOB_MSGTYPE_STAGEWHISPER = "stagewhisper";
WHISPER_ROOT_PATH = "stagewhisper";
WHISPER_MSG_PATH = "messages";
WHISPER_GM_ALIAS_PATH = "gmalias";

local fProcessWhisperHelper;

function onInit()
	if Session.IsHost then
		local whispernode = DB.createNode(StageWhisper.WHISPER_ROOT_PATH);
		DB.setPublic(whispernode, true);
		StageWhisper.loadDefaultGmAlias();
		StageWhisper.loadDefaultWhisperMessages();

		OptionsManager.registerButton("library_recordtype_label_whispers", "whispers", StageWhisper.WHISPER_ROOT_PATH);
	end

	fProcessWhisperHelper = ChatManager.processWhisperHelper;
	ChatManager.processWhisperHelper = StageWhisper.processWhisperHelper;
	
	OOBManager.registerOOBMsgHandler(StageWhisper.OOB_MSGTYPE_STAGEWHISPER, StageWhisper.handleWhisper);
end

-----------------------------------------------------------
-- DATA MANAGEMENT
-----------------------------------------------------------
function loadDefaultGmAlias()
	if not Session.IsHost then
		return;
	end

	local root = DB.findNode(StageWhisper.WHISPER_ROOT_PATH);
	if not root then
		root = DB.createNode(StageWhisper.WHISPER_ROOT_PATH);
	end
	if not root then
		return;
	end

	if DB.getValue(root, StageWhisper.WHISPER_GM_ALIAS_PATH, "") == "" then
		DB.setValue(root, StageWhisper.WHISPER_GM_ALIAS_PATH, "string", Interface.getString("default_gm_alias"));
	end
end

function getGmAlias()
	local root = DB.findNode(StageWhisper.WHISPER_ROOT_PATH);
	if not root then
		return Interface.getString("default_gm_alias");
	end

	local sAlias = DB.getValue(root, StageWhisper.WHISPER_GM_ALIAS_PATH, "");

	-- If the alias is not set, then we grab the default
	if sAlias == "" then
		sAlias = Interface.getString("default_gm_alias");
	end

	return sAlias;
end

function loadDefaultWhisperMessages()
	if not Session.IsHost then
		return;
	end

	local root = DB.findNode(StageWhisper.WHISPER_ROOT_PATH);
	if not root then
		root = DB.createNode(StageWhisper.WHISPER_ROOT_PATH);
	end
	if not root then
		return;
	end
	local messages = DB.createChild(root, StageWhisper.WHISPER_MSG_PATH);
	if not messages then
		return;
	end

	-- Loop through every msg_default# string and add them if there are no whisper messages
	if DB.getChildCount(root, StageWhisper.WHISPER_MSG_PATH) == 0 then
		local sMsg = nil;
		local nCount = 1;
		repeat
			sTextRes = "msg_default" .. nCount;
			sMsg = Interface.getString(sTextRes);

			if (sMsg or "") ~= "" then
				local newNode = DB.createChild(messages);
				if newNode then
					DB.setValue(newNode, "label", "string", sMsg)
				end
			end
			nCount = nCount + 1;
		until (sMsg or "") == ""
	end
end

function getWhisperMessages() 
	local root = DB.findNode(StageWhisper.WHISPER_ROOT_PATH);
	if not root then
		return;
	end

	local whispers = {};
	for _, node in ipairs(DB.getChildList(root, StageWhisper.WHISPER_MSG_PATH)) do
		local sMsg = DB.getValue(node, "label", "");
		if sMsg ~= "" then
			table.insert(whispers, sMsg);
		end
	end

	return whispers;
end

function getRandomWhisperMessage()
	local whispers = StageWhisper.getWhisperMessages();
	if #whispers == 0 then
		return nil;
	end

	if #whispers == 1 then
		return whispers[1];
	end

	return whispers[math.random(#whispers)];
end

-----------------------------------------------------------
-- CHAT
-----------------------------------------------------------
function processWhisperHelper(sRecipient, sMessage)
	-- Send the original whisper
	fProcessWhisperHelper(sRecipient, sMessage);

	if not sRecipient or (sMessage or "") == "" then
		return;
	end

	local sStageWhisperText = StageWhisper.getRandomWhisperMessage();
	if not sStageWhisperText then
		return;
	end

	-- Now send a message to everyone that the whisper occurred
	local sRecipientID = nil;
	if sRecipient == "GM" then
		sRecipientID = "gm";
	else
		for _,vID in ipairs(User.getAllActiveIdentities()) do
			local sIdentity = User.getIdentityLabel(vID);
			if sIdentity == sRecipient then
				sRecipientID = vID;
			end
		end
	end

	-- Get the sender of the message
	local sSender;
	if Session.IsHost then
		sSender = "gm";
	else
		sSender = User.getCurrentIdentity();
		if not sSender then
			return;
		end
	end

	local msgOOB = {};
	msgOOB.type = StageWhisper.OOB_MSGTYPE_STAGEWHISPER;
	msgOOB.sender = sSender;
	msgOOB.receiver = sRecipientID;
	msgOOB.text = sStageWhisperText;

	Comm.deliverOOBMessage(msgOOB);
end

function handleWhisper(msgOOB)
	-- Validate
	if not msgOOB.sender or not msgOOB.receiver or not msgOOB.text then
		return;
	end

	local bShowToGm = Session.IsHost and OptionsManager.isOption("SHPW", "off");

	local bShowMessage = false; -- If all else fails, don't display a message
	if Session.IsHost then
		bShowMessage = OptionsManager.isOption("SHPW", "off") and not (msgOOB.receiver == "gm" or msgOOB.sender == "gm");
	else
		bShowMessage = not (User.isOwnedIdentity(msgOOB.receiver) or User.isOwnedIdentity(msgOOB.sender));
	end

	if not bShowMessage then
		return;
	end

	StageWhisper.printNotification(msgOOB.sender, msgOOB.receiver, msgOOB.text);
end

function printNotification(sSender, sReceiver, sText)
	local sText = StageWhisper.replaceTokens(sSender, sReceiver, sText);

	-- Capitalize the first letter of the text
	sText = (sText:gsub("^%l", string.upper))

	local msg = { font = "whisperfont", sender = "", mode="", icon = { "indicator_whisper" } };

	if sSender == "gm" then
		table.insert(msg.icon, "portrait_gm_token");
	else
		table.insert(msg.icon, "portrait_" .. sSender .. "_chat");
	end
	msg.text = sText;

	Comm.addChatMessage(msg);
end

function replaceTokens(sSenderId, sReceiverId, sText)
	local sSenderName = StageWhisper.resolveIdentityName(sSenderId)

	local sReceiverName;
	if sSenderId == sReceiverId then
		sReceiverName = "themself";
	else
		sReceiverName = StageWhisper.resolveIdentityName(sReceiverId);
	end

	if sSenderName then
		sText = sText:gsub("%[S%]", sSenderName);
	end
	
	if sReceiverName then
		sText = sText:gsub("%[R%]", sReceiverName);
	end

	return sText;
end

function resolveIdentityName(sIdentity)
	if not sIdentity then
		return nil;
	end
	if sIdentity == "gm" then
		return StageWhisper.getGmAlias();
	else
		return User.getIdentityLabel(sIdentity);
	end
end