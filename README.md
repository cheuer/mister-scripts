# copy-rom

Intended to be compatible with the romloader.yaml configuration file from [tcprescott/romloader](https://github.com/tcprescott/romloader), this script will copy a .sfc/.smc (SNES) or .nes (NES) file to the appropriate location on your MiSTer, and launch it in the corresponding core.

Copy romloader_example.yaml to romloader.yaml and edit the configuration to match your MiSTer setup and add entries for your MSU packs. Then run copy_rom.bat with the path to a .sfc, .smc, or .nes file as an argument, or set Windows to automatically open those file types with copy_rom.bat.
