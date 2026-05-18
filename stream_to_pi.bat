@echo off
REM Stream Windows audio to Pi via GStreamer RTP
REM Captures VB-Audio Virtual Cable Output (capture endpoint, no loopback)
REM Source applications must output to "CABLE Input (VB-Audio Virtual Cable)"
REM
REM Device-id reference (from gst-device-monitor-1.0 Audio/Source):
REM   {0.0.1.00000000}.{c78dc72e-bdf4-48cf-997a-276af77fbd97}
REM
REM Loop forever: gst-launch crash or normal exit -> 3s wait -> restart.

:loop
echo [stream_to_pi] Avvio GStreamer RTP -^> 192.168.68.68:5004
"C:\Program Files\gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe" -e ^
  wasapisrc device="{0.0.1.00000000}.{c78dc72e-bdf4-48cf-997a-276af77fbd97}" ^
  ! audioresample ^
  ! audioconvert ^
  ! audio/x-raw,format=S16BE,channels=2,rate=44100 ^
  ! rtpL16pay pt=96 ^
  ! udpsink host=192.168.68.68 port=5004
echo [stream_to_pi] GStreamer uscito, riavvio in 3s...
timeout /t 3 /nobreak >nul
goto loop
