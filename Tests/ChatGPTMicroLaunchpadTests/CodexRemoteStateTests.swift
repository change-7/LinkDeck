import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexRemoteStateTests: XCTestCase {
    @MainActor
    func testUsageRefresh_whenResponseIsMissingRetainsLastKnownUsage() {
        let existingWeekly = CodexWeeklyUsage(usedPercent: 33, resetsAt: nil)
        let refreshedWeekly = CodexWeeklyUsage(usedPercent: 41, resetsAt: nil)

        XCTAssertEqual(
            CodexAppServerClient.retainedUsage(existing: existingWeekly, refreshed: nil),
            existingWeekly,
            "A transient rate-limit failure must not blank the usage gauge."
        )
        XCTAssertEqual(
            CodexAppServerClient.retainedUsage(existing: existingWeekly, refreshed: refreshedWeekly),
            refreshedWeekly
        )
    }

    func testRemoteState_whenMacReportsUsedPercent_exposesMatchingRemainingPercent() {
        let usage = CodexWeeklyUsage(usedPercent: 33, resetsAt: nil)
        let fiveHourUsage = CodexFiveHourUsage(usedPercent: 16, resetsAt: nil)
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "Codex 작업 중",
            weeklyUsage: usage,
            fiveHourUsage: fiveHourUsage
        )

        XCTAssertEqual(state.usedPercent, 33)
        XCTAssertEqual(state.remainingPercent, 67)
        XCTAssertEqual(state.fiveHourUsedPercent, 16)
        XCTAssertEqual(state.fiveHourRemainingPercent, 84)
        XCTAssertEqual(state.completionSoundVolumePercent, 100)
        XCTAssertEqual(state.approvalSoundVolumePercent, 100)
    }

    func testRemoteApprovalSound_decodingOldMessageDefaultsToPhoneAtFullVolume() throws {
        let data = Data(#"{"type":"codexApprovalSound","protocolVersion":1,"id":"built-in","useBuiltIn":true,"configured":false}"#.utf8)

        let sound = try JSONDecoder().decode(CodexRemoteApprovalSound.self, from: data)

        XCTAssertEqual(sound.outputTarget, .phone)
        XCTAssertEqual(sound.volumePercent, 100)
        XCTAssertFalse(sound.outputTarget.playsOnMac)
        XCTAssertTrue(sound.outputTarget.playsOnPhone)
    }

    func testRemoteApprovalSound_roundTripsVolumeAndMigratesLegacyBothTarget() throws {
        let legacy = Data(#"{"id":"built-in","outputTarget":"both","volumePercent":37}"#.utf8)
        let sound = try JSONDecoder().decode(CodexRemoteApprovalSound.self, from: legacy)
        XCTAssertEqual(sound.outputTarget, .phone)
        XCTAssertEqual(sound.volumePercent, 37)
        XCTAssertEqual(try JSONDecoder().decode(CodexRemoteApprovalSound.self, from: JSONEncoder().encode(sound)), sound)
        let state = CodexRemoteState(macConnected: true, codexConnected: true, activity: .idle,
            message: "", weeklyUsage: nil, fiveHourUsage: nil, approvalSoundVolumePercent: 37)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertEqual(json["approvalSoundVolumePercent"] as? Int, 37)
    }

    func testRemoteState_whenSmartphoneButtonUsesClipboardText_omitsTextFromPhonePayload() throws {
        var pages = SmartphoneDefaults.pages()
        pages[2].buttons[0].action = PadAction(kind: .clipboardText, value: "비밀 텍스트\nsecret")

        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "대기",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphonePages: pages
        )

        XCTAssertEqual(state.smartphonePages[2].buttons[0].action.kind, .clipboardText)
        XCTAssertEqual(state.smartphonePages[2].buttons[0].action.value, "")
        let wireText = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertFalse(wireText.contains("비밀 텍스트"))
        XCTAssertFalse(wireText.contains("secret"))
    }

    func testRemoteState_whenSmartphoneAppFolderHasShortcuts_roundTripsAndSanitizesNestedClipboard() throws {
        var pages = SmartphoneDefaults.pages()
        let parentID = pages[0].buttons[0].id
        pages[0].buttons[0].action = PadAction(kind: .appFolder, value: "com.apple.finder")
        pages[0].buttons[0].folderShortcuts = [
            SmartphoneFolderShortcut(
                id: "\(parentID)_folder_0",
                title: "새 창",
                symbol: "plus",
                action: PadAction(kind: .shortcut, value: "cmd+n", targetAppBundleIdentifier: "com.apple.finder")
            ),
            SmartphoneFolderShortcut(
                id: "\(parentID)_folder_1",
                title: "비밀",
                symbol: "doc.on.clipboard",
                customIconData: Data([0x89, 0x50, 0x4E, 0x47]),
                action: PadAction(kind: .clipboardText, value: "비밀 단축키")
            )
        ]

        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphonePages: pages
        )
        let decoded = try JSONDecoder().decode(
            CodexRemoteState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].action.kind, .appFolder)
        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].folderShortcuts.count, 2)
        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].folderShortcuts[0].action.value, "cmd+n")
        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].folderShortcuts[1].action.value, "")
        XCTAssertNil(decoded.smartphonePages[0].buttons[0].folderShortcuts[1].customIconData)
    }

    func testRemoteState_whenUsageIsMissing_doesNotInventPhoneUsage() {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: false,
            activity: .idle,
            message: "Codex App Server 연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil
        )

        XCTAssertNil(state.usedPercent)
        XCTAssertNil(state.remainingPercent)
    }

    func testRemoteCommand_roundTripsItsStableWireFields() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "test-command",
            command: "codexApproval",
            decision: "accept",
            approvalRequestKey: "desktop:thread:request:approval"
        )

        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: encoded)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.approvalRequestKey, "desktop:thread:request:approval")
    }

    func testRemoteCommandResult_usesCommandResultEnvelope() throws {
        let result = CodexRemoteCommandResult(id: "test-command", success: true, message: "앱을 열었습니다.")

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "commandResult")
        XCTAssertEqual(object["protocolVersion"] as? Int, 1)
        XCTAssertEqual(object["id"] as? String, "test-command")
        XCTAssertEqual(object["success"] as? Bool, true)
    }

    func testSmartphoneDefaults_areIndependentFromMacLaunchpadPages() {
        let smartphonePages = SmartphoneDefaults.pages()

        XCTAssertEqual(smartphonePages.count, 3)
        XCTAssertEqual(smartphonePages.flatMap(\.buttons).count, 48)
        XCTAssertEqual(smartphonePages[0].buttons[0].action, PadAction(kind: .shortcut, value: "cmd+r"))
        XCTAssertNotEqual(smartphonePages[0].buttons[0].id, "grid_0_0")
    }

    func testSmartphoneDefaults_resolvesOnlyStoredButtonIDs() {
        let pages = SmartphoneDefaults.pages()
        let storedButton = pages[0].buttons[0]

        XCTAssertEqual(
            SmartphoneDefaults.button(id: storedButton.id, in: pages),
            storedButton
        )
        XCTAssertNil(SmartphoneDefaults.button(id: "missing-button", in: pages))
    }

    func testSmartphoneDefaults_resolvesNestedFolderShortcutIDs() {
        var pages = SmartphoneDefaults.pages()
        let parentID = pages[0].buttons[0].id
        let shortcut = SmartphoneFolderShortcut(
            id: "\(parentID)_folder_0",
            title: "새 창",
            action: PadAction(kind: .shortcut, value: "cmd+n")
        )
        pages[0].buttons[0].folderShortcuts = [shortcut]

        XCTAssertEqual(SmartphoneDefaults.action(id: parentID, in: pages), pages[0].buttons[0].action)
        XCTAssertEqual(SmartphoneDefaults.action(id: shortcut.id, in: pages), shortcut.action)
        XCTAssertNil(SmartphoneDefaults.action(id: "missing-button", in: pages))
    }

    func testSmartphoneButton_decodesLegacyPayloadWithoutFolderShortcuts() throws {
        let legacyPayload = #"{"id":"smartphone_page_0_button_0","title":"기존 버튼","symbol":"play.fill","action":{"kind":"shortcut","value":"cmd+r"}}"#.data(using: .utf8)!

        let button = try JSONDecoder().decode(SmartphoneButton.self, from: legacyPayload)

        XCTAssertEqual(button.title, "기존 버튼")
        XCTAssertEqual(button.action.value, "cmd+r")
        XCTAssertTrue(button.folderShortcuts.isEmpty)
    }

    func testPadAction_repairsLegacyAppBundleIDStoredAsShortcutValue() {
        let action = PadAction(
            kind: .shortcut,
            value: "com.openai.codex",
            targetAppBundleIdentifier: "com.openai.codex"
        )

        XCTAssertEqual(action.repairedForPersistence.value, "")
        XCTAssertEqual(action.repairedForPersistence.targetAppBundleIdentifier, "com.openai.codex")
    }

    func testSmartphoneDefaults_bridgeHelperReadsSharedPageNames() throws {
        let suiteName = "test.smartphone-bridge-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        var pages = SmartphoneDefaults.pages()
        pages[1].name = "집중 작업"
        preferences.set(try JSONEncoder().encode(pages), forKey: "chatgpt-micro-launchpad.smartphone-pages")

        XCTAssertEqual(SmartphoneDefaults.persistedPages(from: preferences)[1].name, "집중 작업")
    }

    func testRemoteState_transmitsSmartphoneButtonActionWithoutChangingMacPadShape() throws {
        var smartphonePages = SmartphoneDefaults.pages()
        smartphonePages[1].name = "집중 작업"
        smartphonePages[0].buttons[0].action = PadAction(kind: .url, value: "https://example.com")
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: false,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphonePages: smartphonePages
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].action, PadAction(kind: .url, value: "https://example.com"))
        XCTAssertEqual(decoded.smartphonePages[1].name, "집중 작업")
        XCTAssertEqual(decoded.smartphonePages[0].buttons.count, 16)
    }

    func testRemoteState_roundTripsSmartphoneIconAssets() throws {
        let asset = SmartphoneIconAsset(data: Data([0, 1, 2]).base64EncodedString())
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphoneIconAssets: ["smartphone_page_0_button_0": asset]
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.smartphoneIconAssets?["smartphone_page_0_button_0"], asset)
    }

    func testRemoteState_decodesLegacyPayloadWithoutIconAssets() throws {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil
        )
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        )
        object.removeValue(forKey: "smartphoneIconAssets")
        object.removeValue(forKey: "codexPhoneTheme")
        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.smartphoneIconAssets)
        XCTAssertNil(decoded.codexPhoneTheme)
        XCTAssertEqual(decoded.smartphonePages.count, 3)
    }

    func testRemoteIconAssetsEnvelope_usesDedicatedWireMessage() throws {
        let asset = SmartphoneIconAsset(data: Data([7, 8, 9]).base64EncodedString())
        let envelope = CodexRemoteIconAssets(assets: ["button": asset])
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "smartphoneIconAssets")
        XCTAssertEqual(object["protocolVersion"] as? Int, 1)
        XCTAssertNotNil((object["assets"] as? [String: Any])?["button"])
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsAppIconAssetsForRegisteredButtons() {
        let assets = SmartphoneIconAssetProvider.assets(for: SmartphoneDefaults.pages())

        XCTAssertNotNil(assets["smartphone_page_0_button_3"])
        XCTAssertEqual(assets["smartphone_page_0_button_3"]?.mimeType, "image/png")
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsTargetAppIconAssetsForShortcuts() {
        var pages = SmartphoneDefaults.pages()
        pages[0].buttons[0].action = PadAction(
            kind: .shortcut,
            value: "cmd+r",
            targetAppBundleIdentifier: "com.apple.Terminal"
        )

        let assets = SmartphoneIconAssetProvider.assets(for: pages)

        XCTAssertNotNil(assets["smartphone_page_0_button_0"])
        XCTAssertEqual(assets["smartphone_page_0_button_0"]?.mimeType, "image/png")
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsSFSymbolAssetsForNonAppButtons() {
        var pages = SmartphoneDefaults.pages()
        pages[0].buttons[0] = SmartphoneButton(
            id: "smartphone_page_0_button_0",
            title: "위",
            symbol: "arrow.up",
            action: PadAction(kind: .shortcut, value: "cmd+up")
        )

        let assets = SmartphoneIconAssetProvider.assets(for: pages)

        XCTAssertNotNil(assets["smartphone_page_0_button_0"])
        XCTAssertEqual(assets["smartphone_page_0_button_0"]?.kind, "sf-symbol")
        XCTAssertEqual(assets["smartphone_page_0_button_0"]?.mimeType, "image/png")
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsSFSymbolAssetsForFolderShortcuts() {
        var pages = SmartphoneDefaults.pages()
        pages[0].buttons[0].folderShortcuts = [
            SmartphoneFolderShortcut(
                id: "smartphone_page_0_button_0_folder_0",
                title: "위로",
                symbol: "arrow.up",
                action: PadAction(kind: .shortcut, value: "cmd+up")
            )
        ]

        let assets = SmartphoneIconAssetProvider.assets(for: pages)

        XCTAssertNotNil(assets["smartphone_page_0_button_0_folder_0"])
        XCTAssertEqual(assets["smartphone_page_0_button_0_folder_0"]?.kind, "sf-symbol")
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsCustomPNGAssetsForFolderShortcuts() throws {
        let tiffData = try XCTUnwrap(
            NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)?.tiffRepresentation
        )
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        let shortcutID = "smartphone_page_0_button_0_folder_0"
        let symbolShortcutID = "smartphone_page_0_button_0_folder_1"
        var pages = SmartphoneDefaults.pages()
        pages[0].buttons[0].folderShortcuts = [
            SmartphoneFolderShortcut(
                id: shortcutID,
                title: "이미지 버튼",
                symbol: "",
                customIconData: pngData
            ),
            SmartphoneFolderShortcut(
                id: symbolShortcutID,
                title: "PNG 우선 버튼",
                symbol: "heart.fill",
                customIconData: pngData
            )
        ]

        let assets = SmartphoneIconAssetProvider.assets(for: pages)
        let asset = try XCTUnwrap(assets[shortcutID])
        let symbolAsset = try XCTUnwrap(assets[symbolShortcutID])

        XCTAssertEqual(asset.kind, "custom")
        XCTAssertEqual(symbolAsset.kind, "custom")
        XCTAssertEqual(
            Data(base64Encoded: asset.data),
            SmartphoneIconData.normalizedPNGData(from: pngData)
        )
    }

    func testRemoteState_transmitsPendingApprovalPrompt() throws {
        let approval = CodexRemoteApproval(
            requestID: 42,
            title: "파일 변경 승인 필요",
            detail: "README.md를 수정합니다.",
            requestKey: "appServer:42"
        )
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .waitingForApproval,
            message: "Codex 승인을 기다리는 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            approval: approval
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.approval, approval)
    }

    func testRemoteApproval_decodesMessagesFromBeforeRequestRoutingFieldsWereAdded() throws {
        let data = Data(#"{"requestID":42,"title":"승인 필요","detail":"확인해 주세요"}"#.utf8)
        let approval = try JSONDecoder().decode(CodexRemoteApproval.self, from: data)

        XCTAssertEqual(approval.requestID, 42)
        XCTAssertEqual(approval.source, "appServer")
        XCTAssertTrue(approval.canRespond)
    }

    func testCodexDesktopApprovalKindRecognizesSupportedApprovalRequests() {
        XCTAssertEqual(CodexDesktopApprovalKind(method: "item/commandExecution/requestApproval"), .commandExecution)
        XCTAssertEqual(CodexDesktopApprovalKind(method: "item/fileChange/requestApproval"), .fileChange)
        XCTAssertEqual(CodexDesktopApprovalKind(method: "item/permissions/requestApproval"), .permissions)
        XCTAssertEqual(CodexDesktopApprovalKind(method: "mcpServer/elicitation/request"), .elicitation)
        XCTAssertEqual(CodexDesktopApprovalKind(method: "item/other/requestApproval"), .unsupported)
    }

    func testCodexDesktopElicitation_isSurfacedButCannotBeAnsweredByLinkDeck() {
        let approval = CodexDesktopPendingApproval(
            conversationID: "thread-3",
            requestID: .integer(8),
            requestKey: "desktop:thread-3:8:mcpServer/elicitation/request",
            method: "mcpServer/elicitation/request",
            title: "Codex 확인 필요",
            detail: "Allow this request?",
            requestedPermissions: nil
        )

        XCTAssertEqual(approval.kind, .elicitation)
        XCTAssertFalse(approval.canRespond)
        XCTAssertNil(CodexDesktopApprovalIPC.route(for: approval, decision: "accept"))
    }

    func testCodexDesktopIPC_parsesElicitationAndUnknownApprovalRequests() throws {
        let requests: CodexIPCJSONValue = .array([
            .object([
                "method": .string("mcpServer/elicitation/request"),
                "id": .integer(8),
                "params": .object([
                    "message": .string("Allow this request?"),
                    "serverName": .string("sample")
                ])
            ]),
            .object([
                "method": .string("item/networkAccess/requestApproval"),
                "id": .integer(9),
                "params": .object(["reason": .string("Network access")])
            ])
        ])

        let approvals = CodexDesktopApprovalIPC.approvals(in: requests, conversationID: "thread-3")

        XCTAssertEqual(approvals.count, 2)
        XCTAssertEqual(approvals[0].title, "Codex 확인 필요")
        XCTAssertEqual(approvals[0].detail, "Allow this request?\nMCP 서버: sample")
        XCTAssertFalse(approvals[0].canRespond)
        XCTAssertEqual(approvals[1].kind, .unsupported)
        XCTAssertEqual(approvals[1].detail, "Network access")
        XCTAssertFalse(approvals[1].canRespond)
    }

    @MainActor
    func testAppServerElicitation_isRecognizedForPhoneAlertsWithoutUnsafeAutoResponse() {
        let method = "mcpServer/elicitation/request"

        XCTAssertTrue(CodexAppServerClient.isRemoteApprovalRequest(method))
        XCTAssertEqual(CodexAppServerClient.remoteApprovalTitle(for: method), "Codex 확인 필요")
        XCTAssertEqual(
            CodexAppServerClient.remoteApprovalDetail(from: [
                "message": "Allow this request?",
                "serverName": "sample"
            ]),
            "Allow this request?\nMCP 서버: sample"
        )
    }

    func testCodexDesktopCommandApproval_routesTheDecisionToItsThreadAndRequest() throws {
        let approval = CodexDesktopPendingApproval(
            conversationID: "thread-1",
            requestID: .integer(42),
            requestKey: "desktop:thread-1:42:item/commandExecution/requestApproval",
            method: "item/commandExecution/requestApproval",
            title: "명령 실행 승인 필요",
            detail: "",
            requestedPermissions: nil
        )

        let route = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval, decision: "accept"))

        XCTAssertEqual(route.method, "thread-follower-command-approval-decision")
        XCTAssertEqual(route.params["conversationId"] as? String, "thread-1")
        XCTAssertEqual(route.params["requestId"] as? Int, 42)
        XCTAssertEqual(route.params["decision"] as? String, "accept")
    }

    func testCodexDesktopPermissionApproval_sendsRequestedPermissionsOnlyOnAccept() throws {
        let approval = CodexDesktopPendingApproval(
            conversationID: "thread-2",
            requestID: .string("permission-request"),
            requestKey: "desktop:thread-2:permission-request:item/permissions/requestApproval",
            method: "item/permissions/requestApproval",
            title: "권한 승인 필요",
            detail: "",
            requestedPermissions: .object(["network": .bool(true)])
        )

        let route = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval, decision: "accept"))
        let response = try XCTUnwrap(route.params["response"] as? [String: Any])
        let permissions = try XCTUnwrap(response["permissions"] as? [String: Any])

        XCTAssertEqual(route.method, "thread-follower-permissions-request-approval-response")
        XCTAssertEqual(response["scope"] as? String, "turn")
        XCTAssertEqual(permissions["network"] as? Bool, true)
        XCTAssertTrue(approval.canRespond)
    }

    @MainActor
    func testRemoteActivity_pendingApprovalTakesPrecedenceOverDesktopRunningActivity() {
        XCTAssertEqual(
            CodexAppServerClient.remoteActivity(
                desktopActivity: .running,
                appServerActivity: .running,
                hasPendingApproval: true
            ),
            .waitingForApproval
        )
    }

    @MainActor
    func testRemoteActivity_desktopCompletionOverridesStaleAppServerRunning() {
        XCTAssertEqual(
            CodexAppServerClient.remoteActivity(
                desktopActivity: .completed,
                appServerActivity: .running,
                hasPendingApproval: false
            ),
            .completed,
            "A stale app-server running state must not hide desktop task completion."
        )
    }

    func testRemoteState_transmitsActiveSessionCount() throws {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "2개 작업 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            activeSessionCount: 2
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.activeSessionCount, 2)
    }

    func testRemoteState_roundTripsSelectedPhoneTheme() throws {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "Codex 작업 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            codexPhoneTheme: .pixelSpace
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.codexPhoneTheme, .pixelSpace)

        let dotMatrixState = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .completed,
            message: "Codex 작업 완료",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            codexPhoneTheme: .dotMatrix
        )
        let dotMatrixDecoded = try JSONDecoder().decode(
            CodexRemoteState.self,
            from: JSONEncoder().encode(dotMatrixState)
        )
        XCTAssertEqual(dotMatrixDecoded.codexPhoneTheme, .dotMatrix)

        let pixelQuestState = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "Codex 퀘스트 진행 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            codexPhoneTheme: .pixelQuest
        )
        let pixelQuestData = try JSONEncoder().encode(pixelQuestState)
        let pixelQuestDecoded = try JSONDecoder().decode(CodexRemoteState.self, from: pixelQuestData)

        XCTAssertEqual(pixelQuestDecoded.codexPhoneTheme?.rawValue, "pixelQuest")
        XCTAssertEqual(pixelQuestDecoded.codexPhoneTheme, .pixelQuest)
    }

    func testRemoteCommand_roundTripsSmartphoneActionPayload() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "phone-button",
            command: "smartphoneButton",
            buttonID: "smartphone_page_0_button_0",
            action: PadAction(kind: .shortcut, value: "cmd+shift+4")
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.buttonID, "smartphone_page_0_button_0")
        XCTAssertEqual(decoded.action, PadAction(kind: .shortcut, value: "cmd+shift+4"))
    }

    func testRemoteCommand_roundTripsTerminalCommandActionPayload() throws {
        let action = PadAction(kind: .terminalCommand, value: "open -a Safari")
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "phone-terminal-button",
            command: "smartphoneButton",
            buttonID: "smartphone_page_0_button_0",
            action: action
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.action, action)
    }

    func testTerminalAutomationBundleDeclaresAppleEventsUsageDescription() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("script/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["NSAppleEventsUsageDescription"] as? String,
            "LinkDeck이 등록된 터미널 명령을 실행하거나 브라우저의 현재 탭에서 웹페이지를 열기 위해 앱을 제어합니다."
        )
    }

    @MainActor
    func testTerminalCommandScript_createsCommandWindowBeforeActivatingTerminal() {
        let source = MacActionRunner.terminalAppleScript(for: "echo test")
        let commandOffset = source.distance(from: source.startIndex, to: source.range(of: "do script")!.lowerBound)
        let activateOffset = source.distance(from: source.startIndex, to: source.range(of: "activate")!.lowerBound)

        XCTAssertLessThan(commandOffset, activateOffset)
    }

    @MainActor
    func testTerminalCommandScript_reusesExistingFrontWindowInsteadOfOpeningAnother() {
        let source = MacActionRunner.terminalAppleScript(for: "echo test")

        XCTAssertTrue(source.contains("reopen"))
        XCTAssertTrue(source.contains("repeat until (count of windows) > 0"))
        XCTAssertTrue(source.contains("in front window"))
    }

    @MainActor
    func testShortcutTargetActivation_forcesTheTargetAppToTheFront() {
        XCTAssertTrue(MacActionRunner.targetAppActivationOptions.contains(.activateAllWindows))
    }

    @MainActor
    func testShortcutTargetActivation_waitsForLaunchedAppBeforeDispatching() {
        XCTAssertGreaterThan(MacActionRunner.targetAppActivationRetryCount, 0)
        XCTAssertGreaterThan(MacActionRunner.targetAppActivationRetryInterval, 0)
    }

    func testRemoteCommand_roundTripsCodexApprovalDecision() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "approval-response",
            command: "codexApproval",
            decision: "accept"
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.decision, "accept")
    }
}
