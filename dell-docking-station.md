### The Cause

  Your system was checked, and here is what was found:
  1. Hardware Detected: Your docking station is a Dell Universal Dock D6000 (ID 17e9:6006).
  2. The Root Issue: Unlike standard USB-C docks that use native DisplayPort Alt-Mode, the Dell D6000 uses DisplayLink technology (Synaptics DL-6950 chip) to drive monitor outputs over
  USB.
  3. Missing Linux Driver: Linux distributions (including Ubuntu) do not bundle the proprietary DisplayLink driver and evdi (Extensible Virtual Display Interface) kernel module out of the
  box. As a result, Power Delivery (charging) and basic USB ports work, but the display outputs remain inactive.
  4. Wayland Session: Your system is running a Wayland session. DisplayLink drivers on Linux work most reliably under X11 (Xorg).
  ──────
  ### Step-by-Step Fix

  #### Step 1: Install the EVDI Module & Prerequisites

  Open your terminal and install the required dependencies and Ubuntu's signed EVDI module:

    sudo apt update
    sudo apt install -y dkms libdrm-dev linux-modules-evdi-generic

  #### Step 2: Install the Official Synaptics DisplayLink Driver

  Synaptics provides an official APT repository for Ubuntu:

    # 1. Download the Synaptics repository keyring
    wget https://www.synaptics.com/sites/default/files/Ubuntu/pool/stable/main/all/synaptics-repository-keyring.deb
    
    # 2. Install the keyring package
    sudo apt install -y ./synaptics-repository-keyring.deb

    # 3. Update package list and install DisplayLink
    sudo apt update
    sudo apt install -y displaylink-driver

  #### Step 3: Handle Secure Boot (If Prompted)

  Your laptop has Secure Boot enabled:

  • If the installer asks you to configure a password for MOK (Machine Owner Key), choose a simple temporary password.
  • When you reboot, a blue screen titled "Perform MOK Management" will appear:
      1. Select Enroll MOK → Continue.
      2. Select Yes to confirm enroll.
      3. Enter the password you set during the installation.
      4. Select Reboot.


  #### Step 4: Switch Session to Xorg (X11)

  Wayland frequently causes blank screens or failure to detect monitors on DisplayLink docks:

  1. Save your open work and Log Out of Ubuntu.
  2. At the login screen, click your username.
  3. Click the gear icon (⚙️) in the bottom right corner of the screen.
  4. Select "Ubuntu on Xorg" (instead of standard Ubuntu / Wayland).
  5. Enter your password to log in.

  #### Step 5: Verify the Driver & Detect Displays

  Once logged in, verify the service is running:

    systemctl status displaylink-driver

  If it shows active (running), unplug and plug back in the USB-C dock connector. Open Settings → Displays and both monitors should appear for arrangement.
  ──────
  │ Tip
  │ Cable Configuration: On the Dell D6000, make sure both monitors are plugged directly into the dock's ports (e.g., HDMI + DisplayPort 1, or DisplayPort 1 + DisplayPort 2). The D6000
  │ does not support DisplayPort daisy-chaining (MST).

