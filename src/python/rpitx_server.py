#!/usr/bin/env python3
import socket
import subprocess
import json
import os

class RpitxServer:
    def __init__(self, host='0.0.0.0', port=5252):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.rpitx_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    def start(self):
        self.sock.bind((self.host, self.port))
        self.sock.listen(1)
        print(f"Server listening on {self.host}:{self.port}")
        
        while True:
            conn, addr = self.sock.accept()
            print(f"Connected by {addr}")
            
            try:
                while True:
                    data = conn.recv(1024)
                    if not data:
                        break
                    
                    command = json.loads(data.decode())
                    result = self.handle_command(command)
                    conn.send(json.dumps(result).encode())
            
            except Exception as e:
                print(f"Error: {e}")
            finally:
                conn.close()

    def handle_command(self, command):
        cmd_type = command.get('type')
        params = command.get('params', {})
        
        # Get common parameters
        freq = params.get('frequency', '100.0')
        
        # Build command based on type
        if cmd_type == 'fm':
            audio = params.get('audio_file', '')
            cmd = f"sudo {self.rpitx_path}/sendiq -i {audio} -s 48000 -f {freq} -t 2"
            
        elif cmd_type == 'nfm':
            audio = params.get('audio_file', '')
            cmd = f"sudo {self.rpitx_path}/sendiq -i {audio} -s 48000 -f {freq} -t 0"
            
        elif cmd_type == 'am':
            audio = params.get('audio_file', '')
            cmd = f"sudo {self.rpitx_path}/sendiq -i {audio} -s 48000 -f {freq} -t 1"
            
        elif cmd_type == 'ssb':
            audio = params.get('audio_file', '')
            cmd = f'(while true; do cat {audio}; done) | csdr convert_i16_f | csdr fir_interpolate_cc 2 | csdr dsb_fc | csdr bandpass_fir_fft_cc 0.002 0.06 0.01 | csdr fastagc_ff | sudo {self.rpitx_path}/sendiq -i /dev/stdin -s 96000 -f {freq} -t float'
            shell = True
            
        elif cmd_type == 'carrier':
            cmd = f"sudo {self.rpitx_path}/tune -f {freq}"
            
        elif cmd_type == 'chirp':
            duration = params.get('duration', '5')
            bandwidth = params.get('bandwidth', '100000')
            cmd = f"sudo {self.rpitx_path}/pichirp {freq} {bandwidth} {duration}"
            
        elif cmd_type == 'record':
            duration = params.get('duration', '10')
            output = params.get('output_file', 'recording.iq')
            cmd = f"sudo {self.rpitx_path}/sendiq -s 48000 -f {freq} -t 2 -r -l {duration} > {output}"
            
        elif cmd_type == 'play':
            input_file = params.get('input_file', '')
            cmd = f"sudo {self.rpitx_path}/sendiq -s 48000 -f {freq} -t 2 -i {input_file}"
            
        elif cmd_type == 'transponder':
            freq_in = params.get('freq_in', '')
            gain = params.get('gain', '45')
            cmd = f'rtl_sdr -s 250000 -g {gain} -f {freq_in} - | buffer | sudo {self.rpitx_path}/sendiq -s 250000 -f {freq} -t u8 -i -'
            shell = True
            
        elif cmd_type == 'sstv':
            image = params.get('image_file', '')
            mode = params.get('mode', 'martin1')  # Default SSTV mode
            cmd = f"sudo {self.rpitx_path}/pisstv -f {freq} -m {mode} {image}"
            
        elif cmd_type == 'freedv':
            audio = params.get('audio_file', '')
            cmd = f"sudo {self.rpitx_path}/pifreedv -f {freq} {audio}"
            
        elif cmd_type == 'pocsag':
            message = params.get('message', '')
            cmd = f"sudo {self.rpitx_path}/pocsag -f {freq} -m {message}"
            
        elif cmd_type == 'morse':
            message = params.get('message', '')
            wpm = params.get('wpm', '20')
            cmd = f"sudo {self.rpitx_path}/morse -f {freq} -m '{message}' -w {wpm}"
            
        elif cmd_type == 'rtty':
            message = params.get('message', '')
            baud = params.get('baud', '45')
            cmd = f"sudo {self.rpitx_path}/pirtty -f {freq} -m '{message}' -b {baud}"
            
        elif cmd_type == 'opera':
            message = params.get('message', '')
            cmd = f"sudo {self.rpitx_path}/piopera -f {freq} -m '{message}'"
            
        elif cmd_type == 'ft8':
            message = params.get('message', '')
            cmd = f"sudo {self.rpitx_path}/pift8 -f {freq} -m '{message}'"
            
        elif cmd_type == 'fsq':
            message = params.get('message', '')
            cmd = f"sudo {self.rpitx_path}/pifsq -f {freq} -m '{message}'"
            
        elif cmd_type == 'spectrum':
            image = params.get('image_file', '')
            cmd = f"sudo {self.rpitx_path}/spectrumpaint -f {freq} {image}"
            
        elif cmd_type == 'foxhunt':
            cmd = f"sudo {self.rpitx_path}/foxhunt -f {freq}"
            
        elif cmd_type == 'tune':
            cmd = f"sudo {self.rpitx_path}/tune -f {freq}"
            
        else:
            return {"status": "error", "message": "Unknown command type"}

        try:
            if 'shell' in locals():
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
            else:
                process = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = process.communicate()
            
            if process.returncode == 0:
                return {"status": "success", "output": stdout.decode()}
            else:
                return {"status": "error", "message": stderr.decode()}
                
        except Exception as e:
            return {"status": "error", "message": str(e)}

if __name__ == "__main__":
    server = RpitxServer()
    server.start()
