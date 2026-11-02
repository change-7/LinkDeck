import json
import sys
import os
import time

job_started = {}
chat_mode = "codex"
unavailable_states = 0
task_starts = 0
idle_termination = None
busy_service = None

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
    elif request.get("params", {}).get("name") in {"set_chat_busy", "set_gemini_busy", "clear_busy"}:
        busy_service = {"set_chat_busy": "chatgpt_state", "set_gemini_busy": "gemini_state"}.get(request["params"]["name"])
        result = {"content": [{"type": "text", "text": "{}"}]}
    elif request.get("params", {}).get("name") in {"chatgpt_state", "gemini_state"}:
        state = {"presentation": {"mode": chat_mode, "windowHidden": True, "humanInterventionRequired": False},
                 "activeTaskCount": int(busy_service == request["params"]["name"]), "busyPanelIndices": [],
                 "panels": [{"taskBusy": False, "promptBusy": False, "isLoading": False, "queuedTaskCount": 0, "state": "completed"}]}
        if idle_termination is not None:
            state["idleTermination"] = idle_termination
        result = {"content": [{"type": "text", "text": json.dumps(state)}]}
    elif request.get("params", {}).get("name") in {"chat_view_start_task", "chat_view_task_status"}:
        if request["params"]["name"] == "chat_view_start_task":
            task_starts += 1
        result = {"content": [{"type": "text", "text": json.dumps({"taskId": "chat-task", "status": "completed", "answer": "fixture answer", "taskStarts": task_starts, "unavailableStates": unavailable_states})}]}
    elif request.get("params", {}).get("name") in {"start_download", "burn_subtitles", "create_miu_event", "update_miu_event", "sync_miu_calendar", "control_device", "start_status_read", "send_files"}:
        name = request["params"]["name"]
        job_id = "fixture-job" if name in {"start_download", "burn_subtitles"} else f"{name}-fixture-job"
        job_started[job_id] = time.monotonic()
        id_key = "id" if name == "send_files" else "job_id" if name in {"start_download", "burn_subtitles"} else "jobID"
        result = {"content": [{"type": "text", "text": json.dumps({id_key: job_id, "phase": "downloading"})}]}
    elif request.get("params", {}).get("name") in {"get_download_status", "get_subtitle_status", "get_miu_job_status", "get_job_status", "get_job"}:
        name = request["params"]["name"]
        id_key = "id" if name == "get_job" else "job_id" if name in {"get_download_status", "get_subtitle_status"} else "jobID"
        job_id = request["params"].get("arguments", {}).get(id_key)
        if job_id not in job_started:
            result = {"isError": True, "content": [{"type": "text", "text": "Missing job id"}]}
        else:
            phase = ("succeeded" if name == "get_job" else "completed") if time.monotonic() - job_started[job_id] > 0.8 else "downloading"
            result = {"content": [{"type": "text", "text": json.dumps({id_key: job_id, "phase": phase})}]}
    else:
        result = {"content": [{"type": "text", "text": json.dumps(request["params"]["arguments"])}]}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
