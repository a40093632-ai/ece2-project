#!/usr/bin/env python3
"""Sync actual PC time to STM32; show CSV. Re-sync after MCU reset, not every loop.
Usage: py pc_time_sync.py COM5 (py -m pip install pyserial)
Close other serial monitors on the same COM port first.
"""
import sys,time
from datetime import datetime
def make_command(now):
    return (f"TIME,{now.year:04d},{now.month:02d},{now.day:02d},"
            f"{now.hour:02d},{now.minute:02d},{now.second:02d}\n").encode("ascii")
def main():
    if len(sys.argv)!=2:
        print("Usage: py pc_time_sync.py COM5");return 2
    try:
        import serial
    except ImportError:
        print("Install: py -m pip install pyserial");return 2
    try:
        with serial.Serial(sys.argv[1],9600,timeout=0.2,write_timeout=1) as ser:
            synced=False;last_send=-10.0;line=bytearray();dropping=False
            while True:
                now=time.monotonic()
                if not synced and now-last_send>=2:
                    ser.write(make_command(datetime.now().astimezone()));ser.flush();last_send=now
                    print("PC time sent; waiting ACK,TIME_SET",flush=True)
                chunk=ser.read(ser.in_waiting or 1)
                for b in chunk:
                    if b==10:
                        if not dropping:
                            text=line.decode("utf-8",errors="replace").rstrip("\r")
                            if text:print(text,flush=True)
                            if text.startswith("ACK,STM32_READY"):
                                synced=False;last_send=-10.0
                            elif text=="ACK,TIME_SET":synced=True
                        line.clear();dropping=False
                    elif not dropping:
                        line.append(b)
                        if len(line)>1024:line.clear();dropping=True
    except KeyboardInterrupt:return 0
    except (OSError,serial.SerialException) as error:
        print(f"Serial error: {error}",file=sys.stderr);return 1
if __name__=="__main__":raise SystemExit(main())
