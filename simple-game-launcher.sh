#!/bin/bash

export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1
export SDL_GAMECONTROLLER_IGNORE_DEVICES="$SDL_GAMECONTROLLER_IGNORE_DEVICES,0x057e/0x2009,0x057e/0x2006,0x057e/0x2007,0x0e6f/0x0180,0x0e6f/0x0184,0x0e6f/0x0185,0x0e6f/0x0188,0x20d6/0xa711,0x20d6/0xa712,0x20d6/0xa713"

exec python3 - <<'END_PYTHON'
import os
import sys
import json
import time
import shutil
import subprocess
import threading
import tarfile
import urllib.request
import urllib.error
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

def fetch_proton_releases():
    all_releases = []

    ge_url = "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=100"
    try:
        req = urllib.request.Request(
            ge_url,
            headers={"User-Agent": "SimpleGameLauncher-ProtonManager"}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            for item in data:
                tag_name = item.get("tag_name")
                tarball_url = None
                for asset in item.get("assets", []):
                    name = asset.get("name", "")
                    if name.endswith(".tar.gz") and not name.endswith(".sha512sum"):
                        tarball_url = asset.get("browser_download_url")
                        break
                if tag_name and tarball_url:
                    all_releases.append({
                        "provider": "GE-Proton",
                        "tag": tag_name,
                        "url": tarball_url
                    })
    except Exception as e:
        print(f"Error fetching GE-Proton releases: {e}")

    dw_url = "https://dawn.wine/api/v1/repos/dawn-winery/dwproton/releases?limit=100"
    try:
        req = urllib.request.Request(
            dw_url,
            headers={"User-Agent": "SimpleGameLauncher-ProtonManager"}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            for item in data:
                tag_name = item.get("tag_name") or item.get("name")
                tarball_url = None
                for asset in item.get("assets", []):
                    name = asset.get("name", "")
                    if (name.endswith(".tar.gz") or name.endswith(".tar.xz")) and not name.endswith(".sha512sum"):
                        tarball_url = asset.get("browser_download_url")
                        break
                if tag_name and tarball_url:
                    all_releases.append({
                        "provider": "DW-Proton",
                        "tag": tag_name,
                        "url": tarball_url
                    })
    except Exception as e:
        print(f"Error fetching DW-Proton releases: {e}")

    cachy_url = "https://api.github.com/repos/CachyOS/proton-cachyos/releases?per_page=100"
    try:
        req = urllib.request.Request(
            cachy_url,
            headers={"User-Agent": "SimpleGameLauncher-ProtonManager"}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            for item in data:
                tag_name = item.get("tag_name")
                tarball_url = None
                for asset in item.get("assets", []):
                    name = asset.get("name", "")
                    if (name.endswith(".tar.gz") or name.endswith(".tar.xz")) and not name.endswith(".sha512sum") and "arm64" not in name:
                        tarball_url = asset.get("browser_download_url")
                        if "_x86_64." in name or name.endswith(".tar.gz"):
                            break
                if tag_name and not tarball_url:
                    for asset in item.get("assets", []):
                        name = asset.get("name", "")
                        if (name.endswith(".tar.gz") or name.endswith(".tar.xz")) and not name.endswith(".sha512sum") and "arm64" not in name:
                            tarball_url = asset.get("browser_download_url")
                            break
                if tag_name and tarball_url:
                    all_releases.append({
                        "provider": "Proton-CachyOS",
                        "tag": tag_name,
                        "url": tarball_url
                    })
    except Exception as e:
        print(f"Error fetching Proton-CachyOS releases: {e}")

    em_url = "https://api.github.com/repos/Etaash-mathamsetty/Proton/releases?per_page=100"
    try:
        req = urllib.request.Request(
            em_url,
            headers={"User-Agent": "SimpleGameLauncher-ProtonManager"}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            for item in data:
                tag_name = item.get("tag_name")
                tarball_url = None
                for asset in item.get("assets", []):
                    name = asset.get("name", "")
                    if (name.endswith(".tar.gz") or name.endswith(".tar.xz")) and not name.endswith(".sha512sum"):
                        tarball_url = asset.get("browser_download_url")
                        break
                if tag_name and tarball_url:
                    all_releases.append({
                        "provider": "Proton-EM",
                        "tag": tag_name,
                        "url": tarball_url
                    })
    except Exception as e:
        print(f"Error fetching Proton-EM releases: {e}")

    return all_releases

class SimpleGameLauncher(tk.Tk):
    def __init__(self):
        super().__init__()

        self.app_name = "Simple Game Launcher"
        self.title(self.app_name)
        self.minsize(680, 420)

        self.config_dir = os.path.expanduser("~/.local/share/simple-game-launcher")
        self.config_file = os.path.join(self.config_dir, "config.json")
        self.default_prefix_dir = os.path.join(self.config_dir, "prefixes")

        os.makedirs(self.config_dir, exist_ok=True)
        os.makedirs(self.default_prefix_dir, exist_ok=True)

        self.config = self.load_config()
        self.geometry(self.config.get("geometry", "720x460"))

        self.running_processes = {}
        self.process_start_times = {}
        self.proton_versions = {}
        self.find_proton_versions()
        self.umu_path = self.find_umu_binary()

        self.create_widgets()
        self.populate_game_list()

        self.update_running_statuses()

        self.protocol("WM_DELETE_WINDOW", self.on_exit)

    def load_config(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {"geometry": "720x460", "games": []}

    def save_config(self):
        self.config["geometry"] = self.geometry()
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4)
        except Exception:
            pass

    def on_exit(self):
        self.finalize_all_active_playtimes()
        for p in self.running_processes.values():
            if p.poll() is None:
                try:
                    p.terminate()
                except Exception:
                    pass
        self.save_config()
        self.destroy()

    def finalize_all_active_playtimes(self):
        current_time = time.time()
        for index_key, start_t in list(self.process_start_times.items()):
            elapsed_minutes = int((current_time - start_t) / 60)
            if elapsed_minutes > 0:
                if 0 <= index_key < len(self.config.get("games", [])):
                    current_playtime = self.config["games"][index_key].get("playtime_minutes", 0)
                    self.config["games"][index_key]["playtime_minutes"] = current_playtime + elapsed_minutes
            self.process_start_times[index_key] = current_time

    def find_proton_versions(self):
        self.proton_versions.clear()
        steam_paths = [
            os.path.expanduser("~/.local/share/Steam"),
            os.path.expanduser("~/.steam/steam"),
            os.path.expanduser("~/.steam/root"),
            os.path.expanduser("~/.var/app/com.valvesoftware.Steam/data/Steam")
        ]

        for base_path in steam_paths:
            comp_dir = os.path.join(base_path, "compatibilitytools.d")
            if os.path.exists(comp_dir):
                for item in os.listdir(comp_dir):
                    item_path = os.path.join(comp_dir, item)
                    if os.path.isdir(item_path) and (os.path.exists(os.path.join(item_path, "proton")) or os.path.exists(os.path.join(item_path, "version"))):
                        self.proton_versions[item] = item_path

    def find_umu_binary(self):
        umu = shutil.which("umu-run")
        if umu:
            return umu

        common_paths = [
            "/usr/bin/umu-run",
            "/usr/local/bin/umu-run",
            os.path.expanduser("~/.local/bin/umu-run")
        ]
        for path in common_paths:
            if os.path.exists(path):
                return path
        return None

    def create_widgets(self):
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        search_frame = ttk.Frame(self, padding=(10, 5, 10, 0))
        search_frame.grid(row=0, column=0, columnspan=2, sticky="ew")
        search_frame.columnconfigure(1, weight=1)

        ttk.Label(search_frame, text="🔍 Search:").grid(row=0, column=0, sticky="w", padx=(0, 5))
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *args: self.populate_game_list())
        search_entry = ttk.Entry(search_frame, textvariable=self.search_var)
        search_entry.grid(row=0, column=1, sticky="ew")

        columns = ("name", "proton", "playtime", "status")
        self.tree = ttk.Treeview(self, columns=columns, show="headings", selectmode="browse")
        self.tree.heading("name", text="Game Name")
        self.tree.heading("proton", text="Runner Version")
        self.tree.heading("playtime", text="Playtime")
        self.tree.heading("status", text="Status")

        self.tree.column("name", width=240, anchor="w")
        self.tree.column("proton", width=140, anchor="center")
        self.tree.column("playtime", width=100, anchor="center")
        self.tree.column("status", width=110, anchor="center")

        self.tree.grid(row=1, column=0, sticky="nsew", padx=10, pady=5)

        scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        scrollbar.grid(row=1, column=1, sticky="ns", pady=5, padx=(0, 10))

        self.tree.bind("<Double-1>", self.on_tree_double_click)
        self.tree.bind("<Return>", lambda event: self.play_game())
        self.tree.bind("<Shift-F10>", self.show_context_menu_keyboard)
        self.tree.bind("<Menu>", self.show_context_menu_keyboard)

        self.context_menu = tk.Menu(self, tearoff=0)
        self.context_menu.add_command(label="✏️ Edit Game", command=self.edit_game)
        self.context_menu.add_command(label="📋 Duplicate Game", command=self.duplicate_game)
        self.context_menu.add_command(label="🗑️ Remove Game", command=self.remove_game)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="📜 Create Direct Launch Script", command=self.create_direct_launch_script)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="🍷 Run winecfg", command=lambda: self.run_prefix_tool("winecfg"))
        self.context_menu.add_command(label="⏹ Run wineboot -k", command=lambda: self.run_prefix_tool("wineboot_k"))
        self.context_menu.add_command(label="🖥️ Run Wine Explorer", command=lambda: self.run_prefix_tool("explorer"))
        self.context_menu.add_command(label="🖥️ Run CMD", command=lambda: self.run_prefix_tool("cmd"))
        self.context_menu.add_separator()
        self.context_menu.add_command(label="📁 Browse Game EXE Location", command=self.browse_game_exe_location)
        self.context_menu.add_command(label="📁 Browse Prefix Location", command=self.browse_prefix_folder)
        self.context_menu.add_command(label="📂 Run .exe inside Prefix", command=self.run_exe_in_prefix)

        self.tree.bind("<Button-3>", self.show_context_menu_mouse)
        self.tree.bind("<Button-2>", self.show_context_menu_mouse)
        self.bind("<Button-1>", self.dismiss_context_menu)

        btn_frame = ttk.Frame(self)
        btn_frame.grid(row=2, column=0, columnspan=2, pady=(5, 10))

        self.btn_add = ttk.Button(btn_frame, text="Add Game", command=self.add_game)
        self.btn_add.pack(side=tk.LEFT, padx=5)

        self.btn_play = ttk.Button(btn_frame, text="▶ Play", command=self.play_game)
        self.btn_play.pack(side=tk.LEFT, padx=10)

        self.btn_stop = ttk.Button(btn_frame, text="⏹ Stop", command=self.stop_game)
        self.btn_stop.pack(side=tk.LEFT, padx=5)

        self.btn_proton_mgr = ttk.Button(btn_frame, text="⚙️ Proton Manager", command=self.open_proton_manager)
        self.btn_proton_mgr.pack(side=tk.LEFT, padx=5)

        self.btn_exit = ttk.Button(btn_frame, text="Exit", command=self.on_exit)
        self.btn_exit.pack(side=tk.RIGHT, padx=5)

        self.tree.focus_set()

    def open_proton_manager(self):
        manager_win = tk.Toplevel(self)
        manager_win.title("Proton Manager")
        manager_win.geometry("660x480")
        manager_win.minsize(540, 400)
        manager_win.transient(self)
        manager_win.grab_set()

        manager_win.columnconfigure(0, weight=1)
        manager_win.rowconfigure(1, weight=1)

        top_frame = ttk.Frame(manager_win, padding=10)
        top_frame.grid(row=0, column=0, sticky="ew")
        top_frame.columnconfigure(1, weight=1)

        ttk.Label(top_frame, text="Repository:").grid(row=0, column=0, sticky="w", padx=(0, 5))
        repo_var = tk.StringVar(value="GE-Proton")
        repo_combo = ttk.Combobox(
            top_frame,
            textvariable=repo_var,
            values=["GE-Proton", "DW-Proton", "Proton-CachyOS", "Proton-EM"],
            state="readonly",
            width=20
        )
        repo_combo.grid(row=0, column=1, sticky="w", padx=(0, 10))

        info_label = ttk.Label(top_frame, text="Initializing...", font=("Arial", 9, "italic"))
        info_label.grid(row=0, column=2, sticky="e")

        frame = ttk.Frame(manager_win, padding=(10, 0, 10, 10))
        frame.grid(row=1, column=0, sticky="nsew")
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)

        columns = ("version", "status", "tag")
        tree = ttk.Treeview(frame, columns=columns, show="headings", selectmode="browse")
        tree.heading("version", text="Release Tag / Version")
        tree.heading("status", text="Status")
        tree.heading("tag", text="Internal Folder ID")

        tree.column("version", width=240, anchor="w")
        tree.column("status", width=120, anchor="center")
        tree.column("tag", width=200, anchor="center")

        tree.grid(row=0, column=0, sticky="nsew")

        scrollbar = ttk.Scrollbar(frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        scrollbar.grid(row=0, column=1, sticky="ns")

        btn_action_frame = ttk.Frame(manager_win, padding=10)
        btn_action_frame.grid(row=2, column=0, sticky="ew")

        status_var = tk.StringVar(value="Ready")
        status_bar = ttk.Label(manager_win, textvariable=status_var, font=("Arial", 8, "italic"), padding=(10, 0))
        status_bar.grid(row=3, column=0, sticky="w", pady=(0, 5))

        releases_cache = []

        def populate_tree_for_current_repo():
            tree.delete(*tree.get_children())
            selected_provider = repo_var.get()
            self.find_proton_versions()

            filtered = [r for r in releases_cache if r["provider"] == selected_provider]
            for rel in filtered:
                tag = rel["tag"]
                is_installed = tag in self.proton_versions
                status_text = "Installed 🟢" if is_installed else "Not Installed"
                tree.insert("", tk.END, values=(tag, status_text, tag))
            info_label.config(text=f"Loaded {len(filtered)} versions for {selected_provider}.")

        def load_releases():
            info_label.config(text="Fetching up to 100 releases online...")
            releases = fetch_proton_releases()
            releases_cache.clear()
            releases_cache.extend(releases)
            manager_win.after(0, populate_tree_for_current_repo)

        repo_combo.bind("<<ComboboxSelected>>", lambda e: populate_tree_for_current_repo())
        threading.Thread(target=load_releases, daemon=True).start()

        steam_paths = [
            os.path.expanduser("~/.local/share/Steam"),
            os.path.expanduser("~/.steam/steam"),
            os.path.expanduser("~/.steam/root"),
            os.path.expanduser("~/.var/app/com.valvesoftware.Steam/data/Steam")
        ]
        target_comp_dir = None
        for base_path in steam_paths:
            if os.path.exists(base_path):
                target_comp_dir = os.path.join(base_path, "compatibilitytools.d")
                break
        if not target_comp_dir:
            target_comp_dir = os.path.expanduser("~/.local/share/Steam/compatibilitytools.d")

        def browse_compatibility_tools():
            os.makedirs(target_comp_dir, exist_ok=True)
            try:
                subprocess.Popen(["xdg-open", target_comp_dir])
            except Exception as e:
                messagebox.showerror("Error", f"Could not open compatibilitytools.d folder:\n{str(e)}", parent=manager_win)

        def install_selected():
            selected = tree.selection()
            if not selected:
                messagebox.showwarning("Warning", "Please select a Proton version to install.", parent=manager_win)
                return
            item_values = tree.item(selected[0], "values")
            tag = item_values[0]

            target_url = None
            for rel in releases_cache:
                if rel["tag"] == tag and rel["provider"] == repo_var.get():
                    target_url = rel["url"]
                    break

            if not target_url:
                messagebox.showerror("Error", "Could not find download URL for this version.", parent=manager_win)
                return

            if tag in self.proton_versions:
                messagebox.showinfo("Info", f"{tag} is already installed.", parent=manager_win)
                return

            os.makedirs(target_comp_dir, exist_ok=True)

            def do_download():
                try:
                    manager_win.after(0, lambda: status_var.set(f"Downloading {tag}..."))
                    temp_archive = os.path.join(self.config_dir, f"{tag}.tar.gz" if target_url.endswith(".tar.gz") else f"{tag}.tar.xz")

                    req = urllib.request.Request(target_url, headers={"User-Agent": "SimpleGameLauncher"})
                    with urllib.request.urlopen(req) as resp, open(temp_archive, 'wb') as out_file:
                        shutil.copyfileobj(resp, out_file)

                    manager_win.after(0, lambda: status_var.set(f"Extracting {tag} to compatibilitytools.d..."))
                    if temp_archive.endswith(".tar.gz"):
                        with tarfile.open(temp_archive, 'r:gz') as tar:
                            tar.extractall(path=target_comp_dir)
                    else:
                        with tarfile.open(temp_archive, 'r:xz') as tar:
                            tar.extractall(path=target_comp_dir)

                    if os.path.exists(temp_archive):
                        os.remove(temp_archive)

                    def finish():
                        status_var.set(f"Successfully installed {tag}!")
                        self.find_proton_versions()
                        tree.set(selected[0], "status", "Installed 🟢")
                        messagebox.showinfo("Success", f"{tag} has been installed successfully!", parent=manager_win)

                    manager_win.after(0, finish)
                except Exception as e:
                    manager_win.after(0, lambda: messagebox.showerror("Download Error", f"Failed to download/install {tag}:\n{str(e)}", parent=manager_win))
                    manager_win.after(0, lambda: status_var.set("Installation failed."))

            threading.Thread(target=do_download, daemon=True).start()

        def delete_selected():
            selected = tree.selection()
            if not selected:
                messagebox.showwarning("Warning", "Please select a Proton version to delete.", parent=manager_win)
                return
            item_values = tree.item(selected[0], "values")
            tag = item_values[0]

            if tag not in self.proton_versions:
                messagebox.showinfo("Info", f"{tag} is not installed.", parent=manager_win)
                return

            if not messagebox.askyesno("Confirm Deletion", f"Are you sure you want to delete {tag} from disk?", parent=manager_win):
                return

            try:
                proton_path = self.proton_versions[tag]
                if os.path.exists(proton_path):
                    shutil.rmtree(proton_path)
                self.find_proton_versions()
                tree.set(selected[0], "status", "Not Installed")
                status_var.set(f"Deleted {tag}")
                messagebox.showinfo("Success", f"Successfully deleted {tag}.", parent=manager_win)
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete {tag}:\n{str(e)}", parent=manager_win)

        btn_install = ttk.Button(btn_action_frame, text="⬇ Install", command=install_selected)
        btn_install.pack(side=tk.LEFT, padx=(0, 5))

        btn_delete = ttk.Button(btn_action_frame, text="🗑️ Delete", command=delete_selected)
        btn_delete.pack(side=tk.LEFT, padx=(0, 5))

        btn_browse_tools = ttk.Button(btn_action_frame, text="📁 Browse Folder", command=browse_compatibility_tools)
        btn_browse_tools.pack(side=tk.LEFT, padx=(0, 5))

        btn_refresh = ttk.Button(btn_action_frame, text="🔄 Refresh", command=lambda: threading.Thread(target=load_releases, daemon=True).start())
        btn_refresh.pack(side=tk.LEFT)

        btn_close = ttk.Button(btn_action_frame, text="Close", command=manager_win.destroy)
        btn_close.pack(side=tk.RIGHT)

    def on_tree_double_click(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            self.tree.selection_set(item)
            self.play_game()

    def show_context_menu_mouse(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            self.tree.selection_set(item)
            try:
                self.context_menu.tk_popup(event.x_root, event.y_root)
            finally:
                self.context_menu.grab_release()

    def show_context_menu_keyboard(self, event=None):
        selection = self.tree.selection()
        if selection:
            try:
                bbox = self.tree.bbox(selection[0])
                if bbox:
                    x = self.tree.winfo_rootx() + bbox[0] + 20
                    y = self.tree.winfo_rooty() + bbox[1] + 20
                    self.context_menu.tk_popup(x, y)
                    return
            except Exception:
                pass
            self.context_menu.tk_popup(self.winfo_rootx() + 100, self.winfo_rooty() + 100)

    def dismiss_context_menu(self, event=None):
        try:
            self.context_menu.unpost()
        except Exception:
            pass

    def format_playtime(self, total_minutes):
        if total_minutes < 60:
            return f"{total_minutes}m"
        hours = total_minutes // 60
        mins = total_minutes % 60
        return f"{hours}h {mins}m"

    def populate_game_list(self):
        selected_iid = self.tree.selection()
        selected_index = int(selected_iid[0]) if selected_iid else None

        for item in self.tree.get_children():
            self.tree.delete(item)

        filter_text = self.search_var.get().strip().lower()

        for index, game in enumerate(self.config.get("games", [])):
            game_name = game["name"]
            if filter_text and filter_text not in game_name.lower():
                continue

            status = "Stopped"
            if index in self.running_processes:
                if self.running_processes[index].poll() is None:
                    status = "Running 🟢"
                else:
                    del self.running_processes[index]
                    if index in self.process_start_times:
                        del self.process_start_times[index]

            runner_display = game.get("proton", "Not Set")
            if game.get("custom_binary"):
                runner_display = f"Custom: {os.path.basename(game['custom_binary'])}"

            stored_mins = game.get("playtime_minutes", 0)
            if index in self.process_start_times:
                active_mins = int((time.time() - self.process_start_times[index]) / 60)
                stored_mins += active_mins

            playtime_display = self.format_playtime(stored_mins)

            self.tree.insert("", tk.END, iid=str(index), values=(game_name, runner_display, playtime_display, status))

        if selected_index is not None and self.tree.exists(str(selected_index)):
            self.tree.selection_set(str(selected_index))
        else:
            children = self.tree.get_children()
            if children and not self.tree.selection():
                self.tree.selection_set(children[0])

    def update_running_statuses(self):
        current_time = time.time()
        need_refresh = False

        for index, game in enumerate(self.config.get("games", [])):
            item_id = str(index)
            if self.tree.exists(item_id):
                status = "Stopped"
                if index in self.running_processes:
                    if self.running_processes[index].poll() is None:
                        status = "Running 🟢"
                    else:
                        del self.running_processes[index]
                        if index in self.process_start_times:
                            elapsed = int((current_time - self.process_start_times[index]) / 60)
                            if elapsed > 0:
                                game["playtime_minutes"] = game.get("playtime_minutes", 0) + elapsed
                            del self.process_start_times[index]
                            self.save_config()
                        need_refresh = True

                current_values = self.tree.item(item_id, "values")
                if current_values:
                    stored_mins = game.get("playtime_minutes", 0)
                    if index in self.process_start_times:
                        stored_mins += int((current_time - self.process_start_times[index]) / 60)
                    new_playtime_str = self.format_playtime(stored_mins)

                    if current_values[2] != new_playtime_str or current_values[3] != status:
                        self.tree.item(item_id, values=(current_values[0], current_values[1], new_playtime_str, status))

        if need_refresh:
            self.populate_game_list()

        self.after(1000, self.update_running_statuses)

    def open_game_dialog(self, title, game_data=None):
        if game_data is None:
            game_data = {}

        dialog = tk.Toplevel(self)
        dialog.title(title)
        dialog.minsize(540, 0)
        dialog.resizable(False, False)
        dialog.transient(self)
        dialog.grab_set()

        result = {}

        form_frame = ttk.Frame(dialog, padding=10)
        form_frame.pack(fill=tk.BOTH, expand=True)
        form_frame.columnconfigure(1, weight=1)

        ttk.Label(form_frame, text="Game Name:").grid(row=0, column=0, sticky="e", pady=5, padx=5)
        name_var = tk.StringVar(value=game_data.get("name", ""))
        name_entry = ttk.Entry(form_frame, textvariable=name_var, width=35)
        name_entry.grid(row=0, column=1, sticky="ew", pady=5, padx=5)
        name_entry.focus_set()

        ttk.Label(form_frame, text="Executable (.exe):").grid(row=1, column=0, sticky="e", pady=5, padx=5)
        path_var = tk.StringVar(value=game_data.get("path", ""))
        ttk.Entry(form_frame, textvariable=path_var, width=30).grid(row=1, column=1, sticky="ew", pady=5, padx=5)

        def browse_exe():
            filename = filedialog.askopenfilename(title="Select Executable", filetypes=[("Windows Executables", "*.exe"), ("All Files", "*.*")])
            if filename:
                path_var.set(filename)
                if not name_var.get().strip():
                    name_var.set(os.path.splitext(os.path.basename(filename))[0])
        ttk.Button(form_frame, text="Browse", command=browse_exe).grid(row=1, column=2, padx=5)

        ttk.Label(form_frame, text="Steam Proton:").grid(row=2, column=0, sticky="e", pady=5, padx=5)
        proton_var = tk.StringVar(value=game_data.get("proton", ""))
        available_protons = sorted(list(self.proton_versions.keys()))
        combo = ttk.Combobox(form_frame, textvariable=proton_var, values=available_protons, state="readonly", width=33)
        combo.grid(row=2, column=1, sticky="ew", pady=5, padx=5)
        if not proton_var.get() and available_protons:
            combo.current(0)

        ttk.Label(form_frame, text="Custom Binary/Wine:").grid(row=3, column=0, sticky="e", pady=5, padx=5)
        custom_bin_var = tk.StringVar(value=game_data.get("custom_binary", ""))
        ttk.Entry(form_frame, textvariable=custom_bin_var, width=30).grid(row=3, column=1, sticky="ew", pady=5, padx=5)

        def browse_custom_bin():
            filename = filedialog.askopenfilename(title="Select Custom Runner Executable")
            if filename:
                custom_bin_var.set(filename)
        ttk.Button(form_frame, text="Browse", command=browse_custom_bin).grid(row=3, column=2, padx=5)

        ttk.Label(form_frame, text="Custom Prefix (Opt):").grid(row=4, column=0, sticky="e", pady=5, padx=5)
        prefix_var = tk.StringVar(value=game_data.get("prefix", ""))
        prefix_entry = ttk.Entry(form_frame, textvariable=prefix_var, width=30)
        prefix_entry.grid(row=4, column=1, sticky="ew", pady=5, padx=5)

        def browse_prefix():
            dirname = filedialog.askdirectory(title="Select Prefix Directory")
            if dirname:
                prefix_var.set(dirname)
                use_default_prefix_var.set(False)
                prefix_entry.configure(state="normal")
        ttk.Button(form_frame, text="Browse", command=browse_prefix).grid(row=4, column=2, padx=5)

        is_default_prefix = game_data.get("use_default_prefix", False)
        use_default_prefix_var = tk.BooleanVar(value=is_default_prefix)

        def toggle_default_prefix():
            if use_default_prefix_var.get():
                prefix_var.set("")
                prefix_entry.configure(state="disabled")
            else:
                prefix_entry.configure(state="normal")

        default_prefix_check = ttk.Checkbutton(
            form_frame,
            text="Use 'default' prefix directory",
            variable=use_default_prefix_var,
            command=toggle_default_prefix
        )
        default_prefix_check.grid(row=5, column=1, sticky="w", pady=(0, 2), padx=5)

        if is_default_prefix:
            prefix_entry.configure(state="disabled")

        options_frame = ttk.Frame(form_frame)
        options_frame.grid(row=6, column=1, sticky="w", pady=(0, 5), padx=5)

        use_wow64_var = tk.BooleanVar(value=game_data.get("use_wow64", False))
        wow64_check = ttk.Checkbutton(options_frame, text="Use PROTON_USE_WOW64", variable=use_wow64_var)
        wow64_check.pack(side=tk.TOP, anchor="w", pady=(0, 2))

        use_umu_var = tk.BooleanVar(value=game_data.get("use_umu", False))
        umu_check = ttk.Checkbutton(options_frame, text="Use UMU (umu-run)", variable=use_umu_var)
        if self.umu_path:
            umu_check.pack(side=tk.TOP, anchor="w", pady=(0, 2))
        else:
            use_umu_var.set(False)

        enable_dxvk_vkd3d_var = tk.BooleanVar(value=game_data.get("enable_dxvk_vkd3d", False))
        dxvk_vkd3d_check = ttk.Checkbutton(options_frame, text="Enable DXVK & VKD3D (WINEDLLOVERRIDES)", variable=enable_dxvk_vkd3d_var)
        dxvk_vkd3d_check.pack(side=tk.TOP, anchor="w", pady=(0, 2))

        ttk.Label(form_frame, text="Env Variables:").grid(row=7, column=0, sticky="e", pady=5, padx=5)
        env_var = tk.StringVar(value=game_data.get("env", ""))
        ttk.Entry(form_frame, textvariable=env_var, width=35).grid(row=7, column=1, sticky="ew", pady=5, padx=5)

        tools_frame = ttk.LabelFrame(form_frame, text=" Advanced Tools Customization ", padding=10)
        tools_frame.grid(row=8, column=0, columnspan=3, sticky="ew", pady=10)
        tools_frame.columnconfigure(1, weight=1)

        ttk.Label(tools_frame, text="MangoHud Args:").grid(row=0, column=0, sticky="e", pady=5, padx=5)
        mangohud_var = tk.StringVar(value=game_data.get("mangohud_args", ""))
        ttk.Entry(tools_frame, textvariable=mangohud_var, width=30).grid(row=0, column=1, sticky="ew", pady=5, padx=5)
        ttk.Label(tools_frame, text="(leave blank to disable)", font=("Arial", 8, "italic")).grid(row=0, column=2, sticky="w", padx=5)

        ttk.Label(tools_frame, text="Gamescope Args:").grid(row=1, column=0, sticky="e", pady=5, padx=5)
        gamescope_var = tk.StringVar(value=game_data.get("gamescope_args", ""))
        ttk.Entry(tools_frame, textvariable=gamescope_var, width=30).grid(row=1, column=1, sticky="ew", pady=5, padx=5)
        ttk.Label(tools_frame, text="(e.g., -W 1280 -H 800 -r 60)", font=("Arial", 8, "italic")).grid(row=1, column=2, sticky="w", padx=5)

        def on_save(event=None):
            if not name_var.get().strip():
                messagebox.showerror("Error", "Game name cannot be empty.", parent=dialog)
                return
            if not path_var.get().strip():
                messagebox.showerror("Error", "Executable path cannot be empty.", parent=dialog)
                return
            if not proton_var.get() and not custom_bin_var.get().strip() and not use_umu_var.get():
                messagebox.showerror("Error", "Please pick either a Steam Proton version, Custom Binary, or enable UMU.", parent=dialog)
                return

            result["name"] = name_var.get().strip()
            result["path"] = path_var.get().strip()
            result["proton"] = proton_var.get()
            result["custom_binary"] = custom_bin_var.get().strip()
            result["use_default_prefix"] = use_default_prefix_var.get()
            result["prefix"] = "" if use_default_prefix_var.get() else prefix_var.get().strip()
            result["use_wow64"] = use_wow64_var.get()
            result["use_umu"] = use_umu_var.get()
            result["enable_dxvk_vkd3d"] = enable_dxvk_vkd3d_var.get()
            result["env"] = env_var.get().strip()
            result["mangohud_args"] = mangohud_var.get().strip()
            result["gamescope_args"] = gamescope_var.get().strip()
            result["playtime_minutes"] = game_data.get("playtime_minutes", 0)
            dialog.destroy()

        save_btn = ttk.Button(form_frame, text="Save Configuration", command=on_save)
        save_btn.grid(row=9, column=0, columnspan=3, pady=10)

        dialog.bind("<Return>", on_save)
        dialog.update_idletasks()
        dialog.geometry("")
        self.wait_window(dialog)
        return result

    def add_game(self):
        details = self.open_game_dialog("Add New Game")
        if details:
            if "games" not in self.config:
                self.config["games"] = []
            self.config["games"].append(details)
            self.save_config()
            self.populate_game_list()

    def edit_game(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game to edit.")
            return

        index = int(selection[0])
        current_game = self.config["games"][index]

        details = self.open_game_dialog(f"Edit Game: {current_game['name']}", current_game)
        if details:
            self.config["games"][index] = details
            self.save_config()
            self.populate_game_list()

    def duplicate_game(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game to duplicate.")
            return

        index = int(selection[0])
        original_game = self.config["games"][index]

        new_game = original_game.copy()
        new_game["name"] = f"{new_game['name']} (Copy)"
        new_game["playtime_minutes"] = 0

        self.config["games"].append(new_game)
        self.save_config()
        self.populate_game_list()

        new_index = str(len(self.config["games"]) - 1)
        if self.tree.exists(new_index):
            self.tree.selection_set(new_index)
            self.tree.see(new_index)

    def create_direct_launch_script(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game first.")
            return

        index = int(selection[0])
        game = self.config["games"][index]
        game_name = game["name"]

        safe_filename = "".join(c for c in game_name if c.isalnum() or c in (' ', '-', '_')).strip().replace(' ', '_').lower()

        file_path = filedialog.asksaveasfilename(
            title="Save Direct Launch Script",
            initialfile=f"play_{safe_filename}.sh",
            defaultextension=".sh",
            filetypes=[("Bash Script", "*.sh"), ("All Files", "*.*")]
        )

        if not file_path:
            return

        try:
            runner_cmd, env, _, _ = self.get_game_runner_env(game)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to build environment configuration:\n{str(e)}")
            return

        exe_path = game["path"]
        gamescope_args = game.get("gamescope_args", "")
        mangohud_args = game.get("mangohud_args", "")

        cmd_parts = []
        if gamescope_args:
            cmd_parts.extend(["gamescope"] + gamescope_args.split() + ["--"])
        if mangohud_args:
            cmd_parts.append("mangohud")
        cmd_parts.extend(runner_cmd)
        cmd_parts.append(f'"{exe_path}"')

        env_exports = ""
        for k, v in env.items():
            escaped_v = str(v).replace('"', '\\"')
            env_exports += f'export {k}="{escaped_v}"\n'

        script_content = f"""#!/bin/bash
export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1
export SDL_GAMECONTROLLER_IGNORE_DEVICES="$SDL_GAMECONTROLLER_IGNORE_DEVICES,0x057e/0x2009,0x057e/0x2006,0x057e/0x2007,0x0e6f/0x0180,0x0e6f/0x0184,0x0e6f/0x0185,0x0e6f/0x0188,0x20d6/0xa711,0x20d6/0xa712,0x20d6/0xa713"

{env_exports}
"""
        if mangohud_args and "=" not in mangohud_args:
            script_content += f'export MANGOHUD_CONFIG="{mangohud_args}"\n'

        script_content += f"""
cd "{os.path.dirname(exe_path)}"

{" ".join(cmd_parts)}
"""

        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(script_content)
            os.chmod(file_path, 0o755)
            messagebox.showinfo("Success", f"Direct launch script created successfully at:\n{file_path}")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save launch script:\n{str(e)}")

    def remove_game(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game to remove.")
            return

        index = int(selection[0])
        game = self.config["games"][index]
        game_name = game["name"]

        dialog = tk.Toplevel(self)
        dialog.title("Confirm Removal")
        dialog.minsize(380, 0)
        dialog.resizable(False, False)
        dialog.transient(self)
        dialog.grab_set()

        content_frame = ttk.Frame(dialog, padding=15)
        content_frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(content_frame, text=f"Remove '{game_name}' from launcher?", font=("Arial", 10, "bold")).pack(anchor="w", pady=(0, 10))

        delete_prefix_var = tk.BooleanVar(value=False)
        prefix_checkbox = ttk.Checkbutton(content_frame, text="🗑️ Also delete wine/proton prefix folder", variable=delete_prefix_var)
        prefix_checkbox.pack(anchor="w", pady=(0, 15))

        btn_frame = ttk.Frame(content_frame)
        btn_frame.pack(fill=tk.X, pady=(5, 0))

        confirmed = {"val": False}

        def on_confirm():
            confirmed["val"] = True
            dialog.destroy()

        def on_cancel():
            dialog.destroy()

        ttk.Button(btn_frame, text="Yes, Remove", command=on_confirm, width=15).pack(side=tk.LEFT, padx=(0, 10))
        ttk.Button(btn_frame, text="Cancel", command=on_cancel, width=12).pack(side=tk.LEFT)

        dialog.update_idletasks()
        dialog.geometry("")
        self.wait_window(dialog)

        if not confirmed["val"]:
            return

        if delete_prefix_var.get():
            if game.get("use_default_prefix", False):
                messagebox.showinfo("Protected Prefix", "Prefix deletion skipped: This game uses the protected 'default' prefix directory and can only be deleted manually.", parent=self)
            else:
                try:
                    _, _, base_prefix, _ = self.get_game_runner_env(game)
                    if os.path.exists(base_prefix):
                        shutil.rmtree(base_prefix)
                except Exception as e:
                    messagebox.showerror("Error", f"Failed to delete prefix directory:\n{str(e)}")

        if index in self.running_processes:
            try:
                self.running_processes[index].terminate()
            except Exception:
                pass
            del self.running_processes[index]
        if index in self.process_start_times:
            del self.process_start_times[index]

        del self.config["games"][index]
        self.save_config()
        self.populate_game_list()

    def get_game_runner_env(self, game):
        if game.get("use_default_prefix", False):
            base_prefix = os.path.join(self.default_prefix_dir, "default")
        elif game.get("prefix"):
            base_prefix = os.path.expanduser(game["prefix"])
        else:
            safe_name = "".join(c for c in game["name"] if c.isalnum() or c in (' ', '-', '_')).strip().replace(' ', '_')
            base_prefix = os.path.join(self.default_prefix_dir, safe_name)

        pfx_dir = os.path.join(base_prefix, "pfx")
        os.makedirs(pfx_dir, exist_ok=True)

        env = os.environ.copy()

        if game.get("use_wow64", False):
            env["PROTON_USE_WOW64"] = "1"

        runner_cmd = []
        custom_binary = game.get("custom_binary", "").strip()
        use_umu = game.get("use_umu", False) and self.umu_path

        if use_umu:
            env["WINEPREFIX"] = pfx_dir
            env["STEAM_COMPAT_DATA_PATH"] = base_prefix
            env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = os.path.expanduser("~/.steam/root")

            proton_name = game.get("proton")
            if proton_name and proton_name in self.proton_versions:
                proton_dir = self.proton_versions[proton_name]
                env["STEAM_COMPAT_TOOL_PATHS"] = proton_dir

            runner_cmd = [self.umu_path]
        elif custom_binary:
            if not os.path.exists(custom_binary):
                raise FileNotFoundError(f"Custom binary not found:\n{custom_binary}")
            env["WINEPREFIX"] = pfx_dir
            if os.path.basename(custom_binary) == "proton":
                env["STEAM_COMPAT_DATA_PATH"] = base_prefix
                env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = os.path.expanduser("~/.steam/root")
                runner_cmd = [custom_binary, "run"]
            else:
                runner_cmd = [custom_binary]
        else:
            env["STEAM_COMPAT_DATA_PATH"] = base_prefix
            env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = os.path.expanduser("~/.steam/root")
            env["WINEPREFIX"] = pfx_dir

            proton_name = game.get("proton")
            proton_dir = self.proton_versions.get(proton_name)
            if not proton_dir:
                raise FileNotFoundError(f"Assigned Proton version ({proton_name}) is no longer installed.")
            proton_bin = os.path.join(proton_dir, "proton")
            runner_cmd = [proton_bin, "run"]

        custom_env = game.get("env", "")
        if custom_env:
            for pair in custom_env.replace(";", " ").split():
                if "=" in pair:
                    k, v = pair.split("=", 1)
                    env[k.strip()] = v.strip()

        if game.get("enable_dxvk_vkd3d", False):
            dx_overrides = "dxgi,d3d8,d3d9,d3d10core,d3d11,d3d12,d3d12core=n"
            existing_overrides = env.get("WINEDLLOVERRIDES", "")
            if existing_overrides:
                env["WINEDLLOVERRIDES"] = f"{dx_overrides};{existing_overrides}".strip(";")
            else:
                env["WINEDLLOVERRIDES"] = dx_overrides

        return runner_cmd, env, base_prefix, pfx_dir

    def play_game(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game to play.")
            return

        index = int(selection[0])
        game = self.config["games"][index]

        if index in self.running_processes and self.running_processes[index].poll() is None:
            messagebox.showinfo("Info", f"'{game['name']}' is already running.")
            return

        exe_path = game["path"]
        if not os.path.exists(exe_path):
            messagebox.showerror("File Missing", f"Could not find the executable:\n{exe_path}")
            return

        try:
            runner_cmd, env, _, _ = self.get_game_runner_env(game)
        except Exception as e:
            messagebox.showerror("Error", str(e))
            return

        cmd = []
        gamescope_args = game.get("gamescope_args", "")
        if gamescope_args:
            cmd.append("gamescope")
            cmd.extend(gamescope_args.split())
            cmd.append("--")

        mangohud_args = game.get("mangohud_args", "")
        if mangohud_args:
            cmd.append("mangohud")

        cmd.extend(runner_cmd)
        cmd.append(exe_path)

        if mangohud_args and "=" not in mangohud_args:
            env["MANGOHUD_CONFIG"] = mangohud_args

        try:
            process = subprocess.Popen(cmd, env=env, cwd=os.path.dirname(exe_path))
            self.running_processes[index] = process
            self.process_start_times[index] = time.time()
            self.update_running_statuses()
            self.populate_game_list()
        except Exception as e:
            messagebox.showerror("Launch Error", f"Failed to launch game:\n{str(e)}")

    def stop_game(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game to stop.")
            return

        index = int(selection[0])
        game = self.config["games"][index]

        if index in self.running_processes:
            proc = self.running_processes[index]
            if proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=2)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass
            del self.running_processes[index]

        if index in self.process_start_times:
            elapsed = int((time.time() - self.process_start_times[index]) / 60)
            if elapsed > 0:
                game["playtime_minutes"] = game.get("playtime_minutes", 0) + elapsed
            del self.process_start_times[index]
            self.save_config()

        try:
            runner_cmd, env, _, _ = self.get_game_runner_env(game)
            stop_cmd = runner_cmd + ["wineboot", "-k"]
            subprocess.run(stop_cmd, env=env, check=False)
        except Exception:
            pass

        self.update_running_statuses()
        self.populate_game_list()
        messagebox.showinfo("Stopped", f"'{game['name']}' has been stopped.")

    def run_prefix_tool(self, tool_type):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game first.")
            return

        index = int(selection[0])
        game = self.config["games"][index]

        try:
            runner_cmd, env, _, _ = self.get_game_runner_env(game)
        except Exception as e:
            messagebox.showerror("Error", str(e))
            return

        if tool_type == "winecfg":
            tool_cmd = runner_cmd + ["winecfg"]
        elif tool_type == "wineboot_k":
            tool_cmd = runner_cmd + ["wineboot", "-k"]
        elif tool_type == "explorer":
            tool_cmd = runner_cmd + ["explorer"]
        elif tool_type == "cmd":
            tool_cmd = runner_cmd + ["wineconsole"]
        else:
            return

        try:
            subprocess.Popen(tool_cmd, env=env)
        except Exception as e:
            messagebox.showerror("Execution Error", f"Failed to run tool:\n{str(e)}")

    def browse_game_exe_location(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game first.")
            return

        index = int(selection[0])
        game = self.config["games"][index]
        exe_path = game.get("path", "")

        if exe_path and os.path.exists(exe_path):
            folder_dir = os.path.dirname(exe_path)
            try:
                subprocess.Popen(["xdg-open", folder_dir])
            except Exception as e:
                messagebox.showerror("Error", f"Could not open folder:\n{str(e)}")
        else:
            messagebox.showerror("Error", f"Executable path does not exist:\n{exe_path}")

    def browse_prefix_folder(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game first.")
            return

        index = int(selection[0])
        game = self.config["games"][index]

        try:
            _, _, base_prefix, pfx_dir = self.get_game_runner_env(game)
            target_dir = pfx_dir if os.path.exists(pfx_dir) else base_prefix
            subprocess.Popen(["xdg-open", target_dir])
        except Exception as e:
            messagebox.showerror("Error", f"Could not open prefix folder:\n{str(e)}")

    def run_exe_in_prefix(self):
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a game first.")
            return

        index = int(selection[0])
        game = self.config["games"][index]

        exe_path = filedialog.askopenfilename(
            title="Select Executable to Run in Prefix",
            filetypes=[("Windows Executables", "*.exe"), ("All Files", "*.*")]
        )

        if exe_path:
            try:
                runner_cmd, env, _, _ = self.get_game_runner_env(game)
                cmd = runner_cmd + [exe_path]
                subprocess.Popen(cmd, env=env, cwd=os.path.dirname(exe_path))
            except Exception as e:
                messagebox.showerror("Execution Error", f"Failed to execute file:\n{str(e)}")

if __name__ == "__main__":
    app = SimpleGameLauncher()
    app.mainloop()
END_PYTHON
