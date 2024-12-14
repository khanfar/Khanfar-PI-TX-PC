#!/usr/bin/env python3
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
import socket
import json
import os

class RpitxClient:
    def __init__(self, root):
        self.root = root
        self.root.title("RPiTX Control Panel")
        
        # Create main notebook for tabs
        self.notebook = ttk.Notebook(root)
        self.notebook.grid(row=0, column=0, padx=5, pady=5, sticky="nsew")
        
        # Connection settings
        self.frame_conn = ttk.LabelFrame(root, text="Connection Settings", padding="5 5 5 5")
        self.frame_conn.grid(row=1, column=0, padx=5, pady=5, sticky="ew")
        
        ttk.Label(self.frame_conn, text="RPi IP:").grid(row=0, column=0, padx=5)
        self.ip_entry = ttk.Entry(self.frame_conn)
        self.ip_entry.grid(row=0, column=1, padx=5)
        self.ip_entry.insert(0, "192.168.1.100")
        
        ttk.Label(self.frame_conn, text="Port:").grid(row=0, column=2, padx=5)
        self.port_entry = ttk.Entry(self.frame_conn, width=10)
        self.port_entry.grid(row=0, column=3, padx=5)
        self.port_entry.insert(0, "5252")
        
        # Create tabs for different transmission modes
        self.create_audio_tab("FM", "fm")
        self.create_audio_tab("NFM", "nfm")
        self.create_audio_tab("AM", "am")
        self.create_audio_tab("SSB", "ssb")
        self.create_audio_tab("FreeDV", "freedv")
        self.create_sstv_tab()
        self.create_message_tab("Morse", "morse", with_wpm=True)
        self.create_message_tab("RTTY", "rtty", with_baud=True)
        self.create_message_tab("POCSAG", "pocsag")
        self.create_message_tab("Opera", "opera")
        self.create_message_tab("FT8", "ft8")
        self.create_message_tab("FSQ", "fsq")
        self.create_spectrum_tab()
        self.create_simple_tab("Carrier", "carrier")
        self.create_chirp_tab()
        self.create_record_play_tab()
        self.create_transponder_tab()
        self.create_simple_tab("Foxhunt", "foxhunt")
        self.create_simple_tab("Tune", "tune")
        
        # Status bar
        self.status_var = tk.StringVar()
        self.status_var.set("Ready")
        self.status_bar = ttk.Label(root, textvariable=self.status_var, relief="sunken")
        self.status_bar.grid(row=2, column=0, sticky="ew", padx=5, pady=5)
        
        # Configure grid
        root.grid_rowconfigure(0, weight=1)
        root.grid_columnconfigure(0, weight=1)

    def create_audio_tab(self, name, mode):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text=name)
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Audio File:").grid(row=1, column=0, padx=5, pady=5)
        file_entry = ttk.Entry(frame)
        file_entry.grid(row=1, column=1, padx=5, pady=5)
        
        ttk.Button(frame, text="Browse", 
                  command=lambda: self.browse_file(file_entry)).grid(row=1, column=2)
        
        ttk.Button(frame, text=f"Transmit {name}", 
                  command=lambda: self.transmit(mode, {"frequency": freq_entry.get(), 
                                                     "audio_file": file_entry.get()})).grid(row=2, column=1)

    def create_sstv_tab(self):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text="SSTV")
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Mode:").grid(row=1, column=0, padx=5, pady=5)
        mode_combo = ttk.Combobox(frame, values=["martin1", "martin2", "scottie1", "scottie2", "robot36"])
        mode_combo.grid(row=1, column=1, padx=5, pady=5)
        mode_combo.set("martin1")
        
        ttk.Label(frame, text="Image File:").grid(row=2, column=0, padx=5, pady=5)
        file_entry = ttk.Entry(frame)
        file_entry.grid(row=2, column=1, padx=5, pady=5)
        
        ttk.Button(frame, text="Browse", 
                  command=lambda: self.browse_file(file_entry, [("Image files", "*.jpg *.png")])).grid(row=2, column=2)
        
        ttk.Button(frame, text="Transmit SSTV", 
                  command=lambda: self.transmit("sstv", {"frequency": freq_entry.get(),
                                                       "image_file": file_entry.get(),
                                                       "mode": mode_combo.get()})).grid(row=3, column=1)

    def create_message_tab(self, name, mode, with_wpm=False, with_baud=False):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text=name)
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Message:").grid(row=1, column=0, padx=5, pady=5)
        message_text = scrolledtext.ScrolledText(frame, width=40, height=5)
        message_text.grid(row=1, column=1, padx=5, pady=5)
        
        row = 2
        wpm_entry = None
        baud_entry = None
        
        if with_wpm:
            ttk.Label(frame, text="WPM:").grid(row=row, column=0, padx=5, pady=5)
            wpm_entry = ttk.Entry(frame)
            wpm_entry.grid(row=row, column=1, padx=5, pady=5)
            wpm_entry.insert(0, "20")
            row += 1
            
        if with_baud:
            ttk.Label(frame, text="Baud:").grid(row=row, column=0, padx=5, pady=5)
            baud_entry = ttk.Entry(frame)
            baud_entry.grid(row=row, column=1, padx=5, pady=5)
            baud_entry.insert(0, "45")
            row += 1
        
        def transmit_message():
            params = {
                "frequency": freq_entry.get(),
                "message": message_text.get("1.0", tk.END).strip()
            }
            if with_wpm:
                params["wpm"] = wpm_entry.get()
            if with_baud:
                params["baud"] = baud_entry.get()
            self.transmit(mode, params)
            
        ttk.Button(frame, text=f"Transmit {name}", 
                  command=transmit_message).grid(row=row, column=1)

    def create_spectrum_tab(self):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text="Spectrum")
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Image File:").grid(row=1, column=0, padx=5, pady=5)
        file_entry = ttk.Entry(frame)
        file_entry.grid(row=1, column=1, padx=5, pady=5)
        
        ttk.Button(frame, text="Browse", 
                  command=lambda: self.browse_file(file_entry, [("Image files", "*.jpg *.png")])).grid(row=1, column=2)
        
        ttk.Button(frame, text="Transmit Spectrum", 
                  command=lambda: self.transmit("spectrum", {"frequency": freq_entry.get(),
                                                           "image_file": file_entry.get()})).grid(row=2, column=1)

    def create_simple_tab(self, name, mode):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text=name)
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Button(frame, text=f"Start {name}", 
                  command=lambda: self.transmit(mode, {"frequency": freq_entry.get()})).grid(row=1, column=1)

    def create_chirp_tab(self):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text="Chirp")
        
        ttk.Label(frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_entry = ttk.Entry(frame)
        freq_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Bandwidth (Hz):").grid(row=1, column=0, padx=5, pady=5)
        bw_entry = ttk.Entry(frame)
        bw_entry.grid(row=1, column=1, padx=5, pady=5)
        bw_entry.insert(0, "100000")
        
        ttk.Label(frame, text="Duration (s):").grid(row=2, column=0, padx=5, pady=5)
        dur_entry = ttk.Entry(frame)
        dur_entry.grid(row=2, column=1, padx=5, pady=5)
        dur_entry.insert(0, "5")
        
        ttk.Button(frame, text="Start Chirp", 
                  command=lambda: self.transmit("chirp", {
                      "frequency": freq_entry.get(),
                      "bandwidth": bw_entry.get(),
                      "duration": dur_entry.get()
                  })).grid(row=3, column=1)

    def create_record_play_tab(self):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text="Record/Play")
        
        # Record section
        record_frame = ttk.LabelFrame(frame, text="Record", padding="5 5 5 5")
        record_frame.grid(row=0, column=0, padx=5, pady=5, sticky="nsew")
        
        ttk.Label(record_frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        rec_freq_entry = ttk.Entry(record_frame)
        rec_freq_entry.grid(row=0, column=1, padx=5, pady=5)
        rec_freq_entry.insert(0, "100.0")
        
        ttk.Label(record_frame, text="Duration (s):").grid(row=1, column=0, padx=5, pady=5)
        dur_entry = ttk.Entry(record_frame)
        dur_entry.grid(row=1, column=1, padx=5, pady=5)
        dur_entry.insert(0, "10")
        
        ttk.Label(record_frame, text="Output File:").grid(row=2, column=0, padx=5, pady=5)
        rec_file_entry = ttk.Entry(record_frame)
        rec_file_entry.grid(row=2, column=1, padx=5, pady=5)
        rec_file_entry.insert(0, "recording.iq")
        
        ttk.Button(record_frame, text="Start Recording", 
                  command=lambda: self.transmit("record", {
                      "frequency": rec_freq_entry.get(),
                      "duration": dur_entry.get(),
                      "output_file": rec_file_entry.get()
                  })).grid(row=3, column=1)
        
        # Play section
        play_frame = ttk.LabelFrame(frame, text="Play", padding="5 5 5 5")
        play_frame.grid(row=1, column=0, padx=5, pady=5, sticky="nsew")
        
        ttk.Label(play_frame, text="Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        play_freq_entry = ttk.Entry(play_frame)
        play_freq_entry.grid(row=0, column=1, padx=5, pady=5)
        play_freq_entry.insert(0, "100.0")
        
        ttk.Label(play_frame, text="Input File:").grid(row=1, column=0, padx=5, pady=5)
        play_file_entry = ttk.Entry(play_frame)
        play_file_entry.grid(row=1, column=1, padx=5, pady=5)
        
        ttk.Button(play_frame, text="Browse", 
                  command=lambda: self.browse_file(play_file_entry, [("IQ files", "*.iq")])).grid(row=1, column=2)
        
        ttk.Button(play_frame, text="Start Playback", 
                  command=lambda: self.transmit("play", {
                      "frequency": play_freq_entry.get(),
                      "input_file": play_file_entry.get()
                  })).grid(row=2, column=1)

    def create_transponder_tab(self):
        frame = ttk.Frame(self.notebook, padding="10")
        self.notebook.add(frame, text="Transponder")
        
        ttk.Label(frame, text="Input Frequency (MHz):").grid(row=0, column=0, padx=5, pady=5)
        freq_in_entry = ttk.Entry(frame)
        freq_in_entry.grid(row=0, column=1, padx=5, pady=5)
        freq_in_entry.insert(0, "100.0")
        
        ttk.Label(frame, text="Output Frequency (MHz):").grid(row=1, column=0, padx=5, pady=5)
        freq_out_entry = ttk.Entry(frame)
        freq_out_entry.grid(row=1, column=1, padx=5, pady=5)
        freq_out_entry.insert(0, "200.0")
        
        ttk.Label(frame, text="Gain (0-45):").grid(row=2, column=0, padx=5, pady=5)
        gain_entry = ttk.Entry(frame)
        gain_entry.grid(row=2, column=1, padx=5, pady=5)
        gain_entry.insert(0, "45")
        
        ttk.Button(frame, text="Start Transponder", 
                  command=lambda: self.transmit("transponder", {
                      "frequency": freq_out_entry.get(),
                      "freq_in": freq_in_entry.get(),
                      "gain": gain_entry.get()
                  })).grid(row=3, column=1)

    def browse_file(self, entry, filetypes=None):
        if filetypes is None:
            filetypes = [("All files", "*.*")]
        filename = filedialog.askopenfilename(filetypes=filetypes)
        if filename:
            entry.delete(0, tk.END)
            entry.insert(0, filename)

    def transmit(self, mode, params):
        command = {
            "type": mode,
            "params": params
        }
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.connect((self.ip_entry.get(), int(self.port_entry.get())))
                sock.send(json.dumps(command).encode())
                response = json.loads(sock.recv(1024).decode())
                
                if response["status"] == "success":
                    self.status_var.set("Success: " + response.get("output", "Command completed"))
                else:
                    self.status_var.set("Error: " + response.get("message", "Unknown error"))
                    messagebox.showerror("Error", response.get("message", "Unknown error"))
                    
        except Exception as e:
            self.status_var.set(f"Error: {str(e)}")
            messagebox.showerror("Error", str(e))

if __name__ == "__main__":
    root = tk.Tk()
    app = RpitxClient(root)
    root.mainloop()
