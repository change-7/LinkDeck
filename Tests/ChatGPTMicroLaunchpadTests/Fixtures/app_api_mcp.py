import json
import sys
import os
import time

job_started = 0
chat_mode = "codex"
unavailable_states = 0
task_starts = 0
idle_termination = None

for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    method = request["method"]
    if method == "initialize":
        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                  "serverInfo": {"name": "LinkDeck test fixture", "version": "1"}}
    elif method == "tools/list":
        second_page = "cursor" in request.get("params", {})
        names = ["echo"] if second_page else ["hidden"]
        result = {"tools": [{"name": name, "description": "Test echo",
                             "inputSchema": {"type": "object"}} for name in names]}
        if not second_page:
            result["nextCursor"] = "second"
    elif request.get("params", {}).get("name") == "pid":
        result = {"content": [{"type": "text", "text": str(os.getpid())}]}
    elif request.get("params", {}).get("name") == "manual_chat_view":
        chat_mode = "manual"
        result = {"content": [{"type": "text", "text": "{}"}]}
    elif request.get("params", {}).get("name") in {"app_managed_chat_view", "app_managed_manual_chat_view"}:
        idle_termination = {"managedByApp": True,
                            "enabled": request["params"]["name"] == "app_managed_chat_view"}
        result = {"content": [{"type": "text", "text": "{}"}]}
    elif request.get("params", {}).get("name") == "simulate_cold_chat_view":
        unavailable_states = 2
        result = {"content": [{"type": "text", "text": "{}"}]}
    elif request.get("params", {}).get("name") == "chatgpt_state" and unavailable_states:
        unavailable_states -= 1
        result = {"isError": True, "content": [{"type": "text", "text": "Connection refused"}]}
    elif request.get("params", {}).get("name") == "chatgpt_state":
        state = {"presentation": {"mode": chat_mode, "windowHidden": True, "humanInterventionRequired": False},
                 "activeTaskCount": 0, "busyPanelIndices": [],
                 "panels": [{"taskBusy": False, "promptBusy": False, "isLoading": False, "queuedTaskCount": 0, "state": "completed"}]}
        if idle_termination is not None:
            state["idleTermination"] = idle_termination
        result = {"content": [{"type": "text", "text": json.dumps(state)}]}
    elif request.get("params", {}).get("name") in {"chat_view_start_task", "chat_view_task_status"}:
        if request["params"]["name"] == "chat_view_start_task":
            task_starts += 1
        result = {"content": [{"type": "text", "text": json.dumps({"taskId": "chat-task", "status": "completed", "answer": "fixture answer", "taskStarts": task_starts, "unavailableStates": unavailable_states})}]}
    elif request.get("params", {}).get("name") in {"start_download", "burn_subtitles"}:
        job_started = time.monotonic()
        result = {"content": [{"type": "text", "text": json.dumps({"job_id": "fixture-job", "phase": "downloading"})}]}
    elif request.get("params", {}).get("name") in {"get_download_status", "get_subtitle_status"}:
        phase = "completed" if time.monotonic() - job_started > 0.8 else "downloading"
        result = {"content": [{"type": "text", "text": json.dumps({"job_id": "fixture-job", "phase": phase})}]}
    else:
        result = {"content": [{"type": "text", "text": json.dumps(request["params"]["arguments"])}]}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
