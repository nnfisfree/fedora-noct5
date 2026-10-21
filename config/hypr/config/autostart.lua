hl.on("hyprland.start", function()
    -- Finalize activation environment before starting the shell and its services.
    hl.exec_cmd("uwsm finalize && systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service && noctalia")
end)
