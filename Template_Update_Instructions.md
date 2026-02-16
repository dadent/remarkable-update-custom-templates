# Instructions to update my templates on the reMarkable Paper Pro

- Connect the reMarkable Paper Pro via USB to the host computer

## Key Information

- Get it from Settings->Help->Copyrights & Licenses
- **IP Address:** 10.11.99.1
- **Password:** *(see device Settings → Help → Copyrights & Licenses)*

## reMarkable Template Locations

- **Directory:** `/usr/share/remarkable/templates`
- **Key Files:**
  - `templates.json` - this contains the list of all the templates

## Key Commands

- `ssh root@[IP_ADDRESS]` – to log on
- `scp /path/to/source/file root@10.11.99.1:/home`

## Steps

Open 2 command windows:

- One to issue SCP Commands to the device while on the host machine — **This is the PC CMD Window**
- One to issue commands to the device while logged onto the device — **This is the RM CMD Window**

### 0 – Get to the right directories

- On both command windows, CD to the directory that has all of the working files
- `C:\Users\daden\OneDrive\Hobby\reMarkable\templates\Update_Attempt\`

### 1 – Log Into the Device

- On RM CMD Window, log on:
  - `ssh root@10.11.99.1`
  - provide password

### 2 – Go to the templates directory

- On the RM CMD Window:
  - `cd /usr/share/remarkable/templates`

### 3 – Copy the templates.json file to the PC

- On the PC CMD Window:
  - `mkdir Update_YYYY_MM_DD`
  - `cd Update_YYYY_MM_DD`
  - `scp root@10.11.99.1:/usr/share/remarkable/templates/templates.json source_templates.json`

### 4 – Edit the templates.json file to add my templates

- Copy `source_templates.json` to `updated_source_templates.json`
- Copy the added entries from the last `templates.json` to the end of the `updated_source_templates.json`

### 5 – Set the device to accept writes

- On the RM CMD Window:
  - `mount -o remount,rw /`

### 6 – Copy the additional template files

- On the PC CMD Window:
  - Change directory to where the template files are
  - For each added template enter:
    - `scp template_file_to_add.template root@10.11.99.1:/usr/share/remarkable/templates/`

### 7 – Copy over the source template main file

- On the PC CMD Window:
  - Change directory to where the `updated_source_templates.json` file is located
  - `scp updated_source_templates.json root@10.11.99.1:/usr/share/remarkable/templates/templates.json`

### 8 – Set the device back to read-only

- On the RM CMD Window:
  - `mount -o remount,ro /`

### 9 – Log off the device

- On the RM CMD Window:
  - `exit`

### 10 – Reboot the device

- Go to Settings page and select restart
