# pfSense WAN IP Alias Updater

Automatically updates a pfSense firewall alias with all IP addresses from your WAN interfaces.

## Overview

This script scans your specified WAN interfaces, collects all IPv4 and IPv6 addresses, and updates a pfSense alias with those addresses. This is useful for:

- Maintaining a dynamic list of your public IPs for firewall rules
- Creating outbound NAT rules that depend on which WAN interface is being used
- Monitoring changes to your WAN IP addresses over time
- Supporting multi-WAN setups with a mix of static and dynamic IPs

## Requirements

- pfSense 2.8.x
- Shell access to your pfSense installation
- Appropriate permissions to run scripts and modify firewall configuration

## Installation

1. SSH into your pfSense router as root
2. Create a directory for the script:

```bash
mkdir -p /root/scripts
```

3. Copy the script to your pfSense installation:

```bash
vi /root/scripts/update_wan_alias.sh
# Paste the script content here and save
```

4. Make the script executable:

```bash
chmod +x /root/scripts/update_wan_alias.sh
```

## Configuration

Edit the following variables at the top of the script:

```bash
# Configuration
WAN_INTERFACES="wan wan2 ovpnc1"  # Your WAN interfaces
ALIAS_NAME="WAN_IPS"              # Name of the pfSense alias
ALIAS_DESC="WAN IP Addresses"     # Description for the alias
```

Adjust the `WAN_INTERFACES` variable to list all your WAN interfaces. For example:
- `wan` - Main WAN interface
- `igb0` - Physical interface name
- `vlan.100` - VLAN interface
- `ovpnc1` - OpenVPN client interface

## How It Works

The script:

1. Scans all specified interfaces for IPv4 and IPv6 addresses
2. Creates a JSON structure with the collected IP addresses
3. Checks if the pfSense alias already exists
4. Updates the alias if the IP addresses have changed
5. Applies the firewall changes
6. Verifies the alias is properly loaded into the pf tables

Each IP address in the alias includes a description showing which interface it belongs to, making it easy to identify in the pfSense web interface.

## Usage

### Manual Execution

Run the script manually:

```bash
/root/scripts/update_wan_alias.sh
```

Example output:
```
Mon May 12 00:09:04 EDT 2025: Starting WAN IP alias update script
Checking interface wan...
  Found IPv4: 203.0.113.17
  No IPv6 address found for wan
Checking interface igb0...
  Found IPv4: 198.51.100.22
  Found IPv6: 2001:db8:1::5c3f
Checking interface vlan.100...
  Found IPv4: 192.0.2.45
  Found IPv6: 2001:db8:2:abc::1
  Found IPv6: 2001:db8:2:abc::2
Checking interface ovpnc1...
  Found IPv4: 10.8.0.6
  No IPv6 address found for ovpnc1
All discovered WAN IPs: 203.0.113.17 198.51.100.22 2001:db8:1::5c3f 192.0.2.45 2001:db8:2:abc::1 2001:db8:2:abc::2 10.8.0.6
Executing PHP update script...
Found 7 IP addresses to process.
Found existing alias 'WAN_IPS'.
Existing alias contains 5 IPs.
Existing IPs: 10.8.0.6, 192.0.2.45, 198.51.100.22, 203.0.113.17, 2001:db8:1::5c3f
New IPs: 10.8.0.6, 192.0.2.45, 198.51.100.22, 203.0.113.17, 2001:db8:1::5c3f, 2001:db8:2:abc::1, 2001:db8:2:abc::2
IP addresses have changed. Updating existing alias...
Added IPs: 2001:db8:2:abc::1, 2001:db8:2:abc::2
Saving configuration changes...
Applying firewall changes...
Alias 'WAN_IPS' updated successfully.
Verification: Alias now contains 7 IPs.
Current IPs in alias: 10.8.0.6, 192.0.2.45, 198.51.100.22, 203.0.113.17, 2001:db8:1::5c3f, 2001:db8:2:abc::1, 2001:db8:2:abc::2
Alias table file exists.
Verifying alias was loaded into pf tables...
pfctl reports alias WAN_IPS is loaded with these entries:
10.8.0.6
192.0.2.45
198.51.100.22
203.0.113.17
2001:db8:1::5c3f
2001:db8:2:abc::1
2001:db8:2:abc::2
Mon May 12 00:09:05 EDT 2025: Script completed
```

### Automatic Execution with Cron

Set up a cron job to run the script automatically:

1. Navigate to **System > Cron** in the pfSense web interface
2. Click **Add** to create a new cron job
3. Configure as follows:
   - **Minute**: 0 (or your preferred interval)
   - **Hour**: * (every hour)
   - **Day of the Month**: * (every day)
   - **Month**: * (every month)
   - **Day of the Week**: * (every day of the week)
   - **Command**: `/root/scripts/update_wan_alias.sh`
   - **Description**: Update WAN IP Alias

This will run the script every hour. Adjust the schedule according to your needs.

## Using the Alias

Once created, you can use the WAN_IPS alias in your firewall rules:

1. Navigate to **Firewall > Rules**
2. Create or edit a firewall rule
3. In the source or destination field, select "Single host or alias"
4. Enter "WAN_IPS" or select it from the alias dropdown

## Troubleshooting

### Script Not Running

Check if the script is executable:
```bash
chmod +x /root/scripts/update_wan_alias.sh
```

### Alias Not Updating

If the alias isn't updating correctly:

1. Run the script manually and check the output
2. Verify the interfaces in `WAN_INTERFACES` exist using `ifconfig`
3. Check if the script can detect IP addresses on the interfaces
4. Ensure the PHP script runs without errors

### Alias Not Applied to Firewall

If the alias exists but isn't applied to the firewall:

1. Run `/etc/rc.update_urltables now` to force update the alias tables
2. Check the pf tables with `pfctl -t WAN_IPS -T show`
3. Restart the firewall service: `pfctl -f /tmp/rules.debug`

## License

This script is released under the MIT License. See the LICENSE file for details.

## Acknowledgments

- pfSense community for documentation and support
- PHP alias management techniques based on pfSense's native alias handling code
