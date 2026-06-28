#!/bin/bash
# PORTMASTER: sshock.zip, SystemShock.sh

# Below we assign the source of the control folder (which is the PortMaster folder) based on the distro:

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_LOG="${SCRIPT_DIR}/sshock/log.txt"
mkdir -p "$(dirname "$BOOT_LOG")"
: > "$BOOT_LOG"
exec >> "$BOOT_LOG" 2>&1

echo "Starting System Shock launcher: $(date)"

echo "Script directory: $SCRIPT_DIR"


XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

echo "Using PortMaster control folder: $controlfolder"
source "$controlfolder/control.txt" # We source the control.txt file contents here
# The $ESUDO, $directory, $param_device and necessary sdl configuration controller configurations will be sourced from the control.txt file shown [here]

# If a Port is built for armhf architecture only (Need for Speed 2 for example) we set this flag so that some environment condition variables are set in the CFWs mod files.
# Example "https://github.com/PortsMaster/PortMaster-GUI/blob/main/PortMaster/mod_JELOS.txt"
# export PORT_32BIT="Y" # If using a 32 bit port, else comment it out.

# We source custom mod files from the portmaster folder example mod_jelos.txt which containts pipewire fixes
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# We pull the controller configs like the correct SDL2 Gamecontrollerdb GUID from the get_controls function from the control.txt file here
get_controls

# We switch to the port's directory location below & set the variable for the gamedir and a configuration dir  easier handling below
GAMEDIR=/$directory/ports/sshock/
CONFDIR="$GAMEDIR/conf/"

echo "Detected rom directory: $directory"
echo "Game directory: $GAMEDIR"
restore_system_audio() {
  echo "Restoring system audio after System Shock exit"

  # Shockolate owns the ALSA device while running. If PortMaster kills the
  # process, dArkOSRE can occasionally keep the system audio stack muted/stale.
  sleep 1

  if command -v systemctl >/dev/null 2>&1; then
    for svc in pulseaudio.service reset-alsa.service alsa-restore.service; do
      if systemctl list-unit-files "$svc" >/dev/null 2>&1 || systemctl status "$svc" >/dev/null 2>&1; then
        echo "Restarting $svc"
        $ESUDO systemctl restart "$svc" >/dev/null 2>&1 || true
      fi
    done
  fi

  if command -v pulseaudio >/dev/null 2>&1; then
    ARK_UID="$(id -u ark 2>/dev/null || echo 1000)"
    mkdir -p "/run/user/${ARK_UID}" 2>/dev/null || true
    $ESUDO chown ark:ark "/run/user/${ARK_UID}" 2>/dev/null || true
    $ESUDO chmod 700 "/run/user/${ARK_UID}" 2>/dev/null || true
    if command -v sudo >/dev/null 2>&1; then
      sudo -u ark env XDG_RUNTIME_DIR="/run/user/${ARK_UID}" pulseaudio --start >/dev/null 2>&1 || true
    else
      XDG_RUNTIME_DIR="/run/user/${ARK_UID}" pulseaudio --start >/dev/null 2>&1 || true
    fi
  fi

  $ESUDO systemctl restart oga_events >/dev/null 2>&1 || true
}

CPU_GOVERNOR_STATE="$CONFDIR/cpu-governors.before"

enable_performance_mode() {
  : > "$CPU_GOVERNOR_STATE"

  for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -r "$governor" ] || continue

    current="$(cat "$governor" 2>/dev/null)"
    [ -n "$current" ] || continue
    printf '%s\t%s\n' "$governor" "$current" >> "$CPU_GOVERNOR_STATE"

    available="$(cat "$(dirname "$governor")/scaling_available_governors" 2>/dev/null)"
    case " $available " in
      *" performance "*)
        printf '%s' performance | $ESUDO tee "$governor" >/dev/null 2>&1 || true
        ;;
    esac
  done
}

restore_cpu_governors() {
  [ -f "$CPU_GOVERNOR_STATE" ] || return

  while IFS="$(printf '\t')" read -r governor previous; do
    case "$governor" in
      /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
        [ -n "$previous" ] && printf '%s' "$previous" | $ESUDO tee "$governor" >/dev/null 2>&1 || true
        ;;
    esac
  done < "$CPU_GOVERNOR_STATE"

  rm -f "$CPU_GOVERNOR_STATE"
}

# Ensure the conf directory exists
mkdir -p "$GAMEDIR/conf"

# Switch to the game directory
cd "$GAMEDIR" || exit 1

# Some ports like to create save files or settings files in the user's home folder or other locations. We map these config folders so we can either preconfigure games and or have the savefiles in one place. I
# You can either use XDG variables to redirect the Ports to our gamefolder if the port supports it:

# Set the XDG environment variables for config & savefiles
export XDG_DATA_HOME="$CONFDIR"

# OR  

# Use bind_directories to reroute that to a location within the ports folder.
#bind_directories ~/.portfolder $GAMEDIR/conf/.portfolder 

# Provide appropriate controller configuration if it recognizes SDL controller input
#export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

if [ -f "$CONFDIR/Interrupt/SystemShock/prefs.txt" ]; then
  sed -i 's/^use-opengl = .*/use-opengl = no/' "$CONFDIR/Interrupt/SystemShock/prefs.txt"
  sed -i 's/^music-volume = .*/music-volume = 100/' "$CONFDIR/Interrupt/SystemShock/prefs.txt"
  sed -i 's/^midi-backend = .*/midi-backend = 2/' "$CONFDIR/Interrupt/SystemShock/prefs.txt"
  sed -i 's/^midi-output = .*/midi-output = 0/' "$CONFDIR/Interrupt/SystemShock/prefs.txt"
fi

enable_performance_mode

# We launch gptokeyb using this $GPTOKEYB variable as it will take care of sourcing the executable from the central location,
# assign the appropriate exit hotkey dependent on the device (ex. select + start for most devices and minus + start for the 
# rgb10) and assign the appropriate method for killing an executable dependent on the OS the port is run from.
# With -c we assign a custom mapping file else gptokeyb will only run as a tool to kill the process.
# For $ANALOGSTICKS we have the ability to supply multiple gptk files to support 1 and 2 analogue stick devices in different ways.
# For a proper documentation how gptokeyb works: [Link](https://github.com/PortsMaster/gptokeyb)
# Ensure HOTKEY is unset, it should default to select
export HOTKEY="select"
$GPTOKEYB2 "sshock.${DEVICE_ARCH}" -c "./sshock.ini" >/dev/null 2>&1 &

# dArkOSRE/RK3326 creates KMSDRM windows only when SDL is pointed at the
# system GLES/EGL libraries and Shockolate's desktop GL profile is forced to ES.
export SDL_VIDEODRIVER=kmsdrm
export SDL_RENDER_DRIVER=opengles2
export SDL_VIDEO_GL_DRIVER=libGLESv2.so
export SDL_VIDEO_EGL_DRIVER=libEGL.so
unset SDL_AUDIO_ALSA_SET_BUFFER_SIZE
export SDL_AUDIO_FREQUENCY=44100
export SHOCK_AUDIO_RATE=44100
# FluidSynth can keep up without the 128 ms mixer block previously needed by
# ADLMIDI. A short block prevents Mix_PlayChannel from stalling the game when
# an SFX starts.
export SHOCK_AUDIO_CHUNK=512
export SHOCK_SDL_FORCE_GLES=1
export SHOCK_SDL_FORCE_RENDERER=opengles2
SHOCK_LD_PRELOAD="$GAMEDIR/libshock-sdlshim.${DEVICE_ARCH}.so"

pm_platform_helper "$GAMEDIR/sshock.${DEVICE_ARCH}"

# Apply the Shockolate-only shim immediately before launch.
export LD_PRELOAD="$SHOCK_LD_PRELOAD"

echo "Final SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
echo "Final SDL_RENDER_DRIVER=$SDL_RENDER_DRIVER"
echo "Final SDL_VIDEO_GL_DRIVER=$SDL_VIDEO_GL_DRIVER"
echo "Final SDL_VIDEO_EGL_DRIVER=$SDL_VIDEO_EGL_DRIVER"
echo "Final SDL_AUDIODRIVER=$SDL_AUDIODRIVER"
echo "Final SDL_AUDIO_ALSA_SET_BUFFER_SIZE=$SDL_AUDIO_ALSA_SET_BUFFER_SIZE"
echo "Final SDL_AUDIO_FREQUENCY=$SDL_AUDIO_FREQUENCY"
echo "Final SHOCK_AUDIO_RATE=$SHOCK_AUDIO_RATE"
echo "Final SHOCK_AUDIO_CHUNK=$SHOCK_AUDIO_CHUNK"
echo "Final LD_PRELOAD=$LD_PRELOAD"

# Now we launch the port's executable with multiarch support. Make sure to rename your file according to the architecture you built for. E.g. portexecutable.aarch64
if command -v nice >/dev/null 2>&1; then
  echo "Launching System Shock with nice -n -5"
  nice -n -5 ./sshock.${DEVICE_ARCH} -f >/dev/null 2>&1 # Launch the executable
else
  echo "Launching System Shock without nice"
  ./sshock.${DEVICE_ARCH} -f >/dev/null 2>&1 # Launch the executable
fi
GAME_STATUS=$?
echo "System Shock exited with code $GAME_STATUS"

restore_cpu_governors

# Keep Shockolate-only runtime hooks away from system cleanup commands.
unset LD_PRELOAD
unset SDL_VIDEODRIVER SDL_RENDER_DRIVER SDL_VIDEO_GL_DRIVER SDL_VIDEO_EGL_DRIVER
unset SHOCK_SDL_FORCE_GLES SHOCK_SDL_FORCE_RENDERER

# Restore audio before the generic PortMaster cleanup.
restore_system_audio

# Cleanup any running gptokeyb instances, and any platform specific stuff.
pm_finish
echo "Launcher cleanup complete"
