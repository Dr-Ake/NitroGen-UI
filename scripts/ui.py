import os
import sys
import queue
import threading
import subprocess
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import psutil
import win32gui
import win32process


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CKPT = ROOT / "ng.pt"


class NitroGenUI(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("NitroGen Launcher")
        self.minsize(760, 520)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

        self.server_proc = None
        self.agent_proc = None
        self.log_queue = queue.Queue()

        self._init_vars()
        self._build_ui()
        self.after(100, self._drain_log_queue)

    def _init_vars(self) -> None:
        ckpt_default = str(DEFAULT_CKPT) if DEFAULT_CKPT.exists() else ""
        self.ckpt_var = tk.StringVar(value=ckpt_default)
        self.port_var = tk.StringVar(value="5555")
        self.cfg_var = tk.StringVar(value="1.0")
        self.ctx_var = tk.StringVar(value="1")
        self.old_layout_var = tk.BooleanVar(value=False)

        self.process_var = tk.StringVar(value="celeste.exe")
        self.allow_menu_var = tk.BooleanVar(value=False)
        self.speedhack_var = tk.BooleanVar(value=True)
        self.fast_frame_var = tk.BooleanVar(value=True)

        self.server_status_var = tk.StringVar(value="stopped")
        self.agent_status_var = tk.StringVar(value="stopped")

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        server_frame = ttk.LabelFrame(self, text="Model Server")
        server_frame.grid(row=0, column=0, sticky="ew", padx=12, pady=(12, 6))
        server_frame.columnconfigure(1, weight=1)

        ttk.Label(server_frame, text="Checkpoint").grid(row=0, column=0, sticky="w", padx=8, pady=6)
        ttk.Entry(server_frame, textvariable=self.ckpt_var).grid(row=0, column=1, sticky="ew", padx=8, pady=6)
        ttk.Button(server_frame, text="Browse", command=self._choose_ckpt).grid(row=0, column=2, padx=8, pady=6)

        config_frame = ttk.Frame(server_frame)
        config_frame.grid(row=1, column=0, columnspan=3, sticky="ew", padx=8, pady=4)
        ttk.Label(config_frame, text="Port").grid(row=0, column=0, sticky="w")
        ttk.Entry(config_frame, textvariable=self.port_var, width=10).grid(row=0, column=1, sticky="w", padx=(6, 16))

        ttk.Label(config_frame, text="CFG").grid(row=0, column=2, sticky="w")
        ttk.Entry(config_frame, textvariable=self.cfg_var, width=6).grid(row=0, column=3, sticky="w", padx=(6, 16))

        ttk.Label(config_frame, text="Ctx").grid(row=0, column=4, sticky="w")
        ttk.Entry(config_frame, textvariable=self.ctx_var, width=6).grid(row=0, column=5, sticky="w", padx=(6, 16))

        ttk.Checkbutton(config_frame, text="Old layout", variable=self.old_layout_var).grid(
            row=0, column=6, sticky="w"
        )

        server_controls = ttk.Frame(server_frame)
        server_controls.grid(row=0, column=3, rowspan=3, padx=8, pady=6, sticky="ns")
        self.start_server_btn = ttk.Button(server_controls, text="Start server", command=self._start_server)
        self.start_server_btn.pack(fill="x", pady=(0, 6))
        self.stop_server_btn = ttk.Button(server_controls, text="Stop server", command=self._stop_server, state="disabled")
        self.stop_server_btn.pack(fill="x")

        ttk.Label(server_frame, text="Status:").grid(row=2, column=0, sticky="w", padx=8, pady=6)
        ttk.Label(server_frame, textvariable=self.server_status_var).grid(row=2, column=1, sticky="w", padx=8, pady=6)

        agent_frame = ttk.LabelFrame(self, text="Agent Runner")
        agent_frame.grid(row=1, column=0, sticky="ew", padx=12, pady=6)
        agent_frame.columnconfigure(1, weight=1)

        ttk.Label(agent_frame, text="Game process").grid(row=0, column=0, sticky="w", padx=8, pady=6)
        process_frame = ttk.Frame(agent_frame)
        process_frame.grid(row=0, column=1, sticky="ew", padx=8, pady=6)
        process_frame.columnconfigure(0, weight=1)
        self.process_combo = ttk.Combobox(process_frame, textvariable=self.process_var)
        self.process_combo.grid(row=0, column=0, sticky="ew")
        ttk.Button(process_frame, text="Refresh", command=self._refresh_process_list).grid(
            row=0, column=1, padx=(6, 0)
        )

        agent_options = ttk.Frame(agent_frame)
        agent_options.grid(row=1, column=1, sticky="w", padx=8, pady=(2, 4))
        ttk.Checkbutton(agent_options, text="Allow menu actions", variable=self.allow_menu_var).grid(
            row=0, column=0, sticky="w"
        )
        ttk.Checkbutton(agent_options, text="Enable speedhack injection", variable=self.speedhack_var).grid(
            row=1, column=0, sticky="w", pady=(2, 0)
        )
        ttk.Checkbutton(agent_options, text="Fast frame read (DXCAM)", variable=self.fast_frame_var).grid(
            row=2, column=0, sticky="w", pady=(2, 0)
        )

        agent_controls = ttk.Frame(agent_frame)
        agent_controls.grid(row=0, column=2, rowspan=2, padx=8, pady=6, sticky="ns")
        self.start_agent_btn = ttk.Button(agent_controls, text="Start agent", command=self._start_agent)
        self.start_agent_btn.pack(fill="x", pady=(0, 6))
        self.stop_agent_btn = ttk.Button(agent_controls, text="Stop agent", command=self._stop_agent, state="disabled")
        self.stop_agent_btn.pack(fill="x")

        ttk.Label(agent_frame, text="Status:").grid(row=2, column=0, sticky="w", padx=8, pady=6)
        ttk.Label(agent_frame, textvariable=self.agent_status_var).grid(row=2, column=1, sticky="w", padx=8, pady=6)

        log_frame = ttk.LabelFrame(self, text="Logs")
        log_frame.grid(row=2, column=0, sticky="nsew", padx=12, pady=(6, 12))
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)

        self.log_text = tk.Text(log_frame, height=12, wrap="word", state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew", padx=(8, 0), pady=8)
        log_scroll = ttk.Scrollbar(log_frame, orient="vertical", command=self.log_text.yview)
        log_scroll.grid(row=0, column=1, sticky="ns", padx=(0, 8), pady=8)
        self.log_text.configure(yscrollcommand=log_scroll.set)

        log_buttons = ttk.Frame(log_frame)
        log_buttons.grid(row=1, column=0, columnspan=2, sticky="e", padx=8, pady=(0, 8))
        ttk.Button(log_buttons, text="Clear logs", command=self._clear_logs).pack()

        self._refresh_process_list()

    def _get_visible_processes(self) -> list[str]:
        processes = []
        seen_pids = set()

        def enum_window_callback(hwnd, _):
            if not win32gui.IsWindowVisible(hwnd):
                return True
            title = win32gui.GetWindowText(hwnd)
            if not title:
                return True
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            if not pid or pid in seen_pids:
                return True
            seen_pids.add(pid)
            try:
                name = psutil.Process(pid).name()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                return True
            if name:
                processes.append(name)
            return True

        win32gui.EnumWindows(enum_window_callback, None)
        return sorted(set(processes), key=str.lower)

    def _refresh_process_list(self) -> None:
        try:
            processes = self._get_visible_processes()
        except Exception as exc:
            messagebox.showwarning("Process list error", f"Failed to refresh process list: {exc}")
            processes = []

        current = self.process_var.get().strip()
        if current and current not in processes:
            processes = [current] + processes
        self.process_combo["values"] = processes
        if not current and processes:
            self.process_var.set(processes[0])

    def _append_log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text)
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _drain_log_queue(self) -> None:
        try:
            while True:
                item = self.log_queue.get_nowait()
                kind = item[0]
                if kind == "log":
                    _, tag, line = item
                    self._append_log(f"[{tag}] {line}")
                elif kind == "exit":
                    _, tag, code = item
                    if tag == "server":
                        self.server_proc = None
                        self.server_status_var.set(f"stopped (code {code})")
                        self.start_server_btn.configure(state="normal")
                        self.stop_server_btn.configure(state="disabled")
                    elif tag == "agent":
                        self.agent_proc = None
                        self.agent_status_var.set(f"stopped (code {code})")
                        self.start_agent_btn.configure(state="normal")
                        self.stop_agent_btn.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(100, self._drain_log_queue)

    def _choose_ckpt(self) -> None:
        path = filedialog.askopenfilename(
            title="Select checkpoint",
            initialdir=str(ROOT),
            filetypes=[("Model checkpoint", "*.pt"), ("All files", "*.*")],
        )
        if path:
            self.ckpt_var.set(path)

    def _validate_port(self) -> str | None:
        port = self.port_var.get().strip()
        if not port.isdigit():
            messagebox.showerror("Invalid port", "Port must be a number.")
            return None
        return port

    def _start_server(self) -> None:
        if self.server_proc is not None:
            messagebox.showinfo("Server already running", "The model server is already running.")
            return

        ckpt = Path(self.ckpt_var.get().strip())
        if not ckpt.is_file():
            messagebox.showerror("Missing checkpoint", "Select a valid checkpoint file.")
            return

        port = self._validate_port()
        if port is None:
            return

        cmd = [
            sys.executable,
            str(ROOT / "scripts" / "serve.py"),
            str(ckpt),
            "--port",
            port,
            "--cfg",
            self.cfg_var.get().strip(),
            "--ctx",
            self.ctx_var.get().strip(),
        ]
        if self.old_layout_var.get():
            cmd.append("--old-layout")

        self._append_log(f"[ui] Starting server: {' '.join(cmd)}\n")
        self.server_proc = self._launch_process(cmd, "server")
        self.server_status_var.set(f"running (port {port})")
        self.start_server_btn.configure(state="disabled")
        self.stop_server_btn.configure(state="normal")

    def _stop_server(self) -> None:
        self._stop_process("server")

    def _start_agent(self) -> None:
        if self.agent_proc is not None:
            messagebox.showinfo("Agent already running", "The agent is already running.")
            return

        port = self._validate_port()
        if port is None:
            return

        process_name = self.process_var.get().strip()
        if not process_name:
            messagebox.showerror("Missing process", "Enter the game executable name (e.g. celeste.exe).")
            return

        cmd = [
            sys.executable,
            str(ROOT / "scripts" / "play.py"),
            "--process",
            process_name,
            "--port",
            port,
        ]
        if self.allow_menu_var.get():
            cmd.append("--allow-menu")
        if not self.speedhack_var.get():
            cmd.append("--no-speedhack")
        cmd.extend([
            "--screenshot-backend",
            "dxcam" if self.fast_frame_var.get() else "pyautogui",
        ])

        self._append_log(f"[ui] Starting agent: {' '.join(cmd)}\n")
        self.agent_proc = self._launch_process(cmd, "agent")
        self.agent_status_var.set(f"running (port {port})")
        self.start_agent_btn.configure(state="disabled")
        self.stop_agent_btn.configure(state="normal")

    def _stop_agent(self) -> None:
        self._stop_process("agent")

    def _launch_process(self, cmd: list[str], tag: str) -> subprocess.Popen:
        proc = subprocess.Popen(
            cmd,
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        thread = threading.Thread(target=self._read_process_output, args=(proc, tag), daemon=True)
        thread.start()
        return proc

    def _read_process_output(self, proc: subprocess.Popen, tag: str) -> None:
        if proc.stdout is None:
            return
        for line in proc.stdout:
            self.log_queue.put(("log", tag, line))
        code = proc.wait()
        self.log_queue.put(("exit", tag, code))

    def _stop_process(self, tag: str) -> None:
        proc = self.server_proc if tag == "server" else self.agent_proc
        if proc is None:
            return

        self._append_log(f"[ui] Stopping {tag}...\n")
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    def _clear_logs(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    def _on_close(self) -> None:
        if self.server_proc is not None:
            self._stop_process("server")
        if self.agent_proc is not None:
            self._stop_process("agent")
        self.destroy()


if __name__ == "__main__":
    if sys.platform.startswith("win") and os.environ.get("TK_SILENCE_DEPRECATION"):
        os.environ["TK_SILENCE_DEPRECATION"] = "1"
    app = NitroGenUI()
    app.mainloop()
