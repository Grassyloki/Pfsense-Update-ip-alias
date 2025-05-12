#!/bin/sh
# Script to update pfSense alias with current WAN IP addresses
# Run this script via cron on the pfSense host

# Configuration
WAN_INTERFACES="igb0 igb1"  # Your WAN interfaces
ALIAS_NAME="WAN_IPS"                       # Name of the pfSense alias
ALIAS_DESC="WAN IP Addresses"              # Description for the alias
TEMP_JSON="/tmp/wan_ips.json"              # Temporary JSON file

# Main script execution
echo "$(date): Starting WAN IP alias update script"

# Create JSON array to store IPs and descriptions
echo "[" > $TEMP_JSON
comma=""

# Collect IP addresses from all interfaces
for interface in $WAN_INTERFACES; do
    echo "Checking interface $interface..."

    # Check if interface exists
    if ! ifconfig $interface >/dev/null 2>&1; then
        echo "  Warning: Interface $interface does not exist. Skipping."
        continue
    fi

    # Get IPv4 addresses
    for ipv4 in $(ifconfig $interface 2>/dev/null | grep 'inet ' | awk '{print $2}'); do
        echo "  Found IPv4: $ipv4"

        # Add to JSON structure
        echo "$comma" >> $TEMP_JSON
        echo "  {\"cidr\": \"$ipv4/32\", \"description\": \"WAN IP -- $interface IPv4\"}" >> $TEMP_JSON
        comma=","
    done

    # Get IPv6 addresses
    for ipv6 in $(ifconfig $interface 2>/dev/null | grep 'inet6' | grep -v 'fe80::' | grep -v 'temporary' | awk '{print $2}'); do
        echo "  Found IPv6: $ipv6"

        # Add to JSON structure
        echo "$comma" >> $TEMP_JSON
        echo "  {\"cidr\": \"$ipv6/128\", \"description\": \"WAN IP -- $interface IPv6\"}" >> $TEMP_JSON
        comma=","
    done
done

# Close JSON array
echo "]" >> $TEMP_JSON

# Create PHP script to update alias
cat > /tmp/update_alias.php << 'EOF'
<?php
require_once('globals.inc');
require_once('config.inc');
require_once('util.inc');

// Command line arguments
$json_file = $argv[1];
$alias_name = $argv[2];
$alias_desc = $argv[3];

// Function to load and decode JSON file
function load_json_file($file_path) {
    $json_data = file_get_contents($file_path);
    if ($json_data === false) {
        die("Error: Could not read JSON file '$file_path'.\n");
    }
    $decoded_data = json_decode($json_data, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        die("Error: JSON decoding failed for '$file_path' - " . json_last_error_msg() . "\n");
    }
    return $decoded_data;
}

// Load JSON file with IPs
$ip_entries = load_json_file($json_file);
echo "Found " . count($ip_entries) . " IP addresses to process.\n";

// Load pfSense config
$config = parse_config();
$found = false;
$updated = false;

// Prepare new addresses and descriptions
$new_addresses = [];
$new_descriptions = [];

foreach ($ip_entries as $entry) {
    $ip = explode("/", $entry['cidr'])[0]; // Remove /32 or /128 from IP
    $desc = $entry['description'];
    $new_addresses[] = $ip;
    $new_descriptions[] = $desc;
}

// Check if alias already exists
if (isset($config['aliases']['alias']) && is_array($config['aliases']['alias'])) {
    foreach ($config['aliases']['alias'] as &$alias) {
        if ($alias['name'] == $alias_name) {
            $found = true;
            echo "Found existing alias '$alias_name'.\n";

            // Get existing addresses
            $existing_addresses = [];
            if (isset($alias['address'])) {
                if (is_array($alias['address'])) {
                    $existing_addresses = $alias['address'];
                } else {
                    $existing_addresses = explode(" ", $alias['address']);
                }
                $existing_addresses = array_filter($existing_addresses);
            }

            echo "Existing alias contains " . count($existing_addresses) . " IPs.\n";
            echo "Existing IPs: " . implode(", ", $existing_addresses) . "\n";
            echo "New IPs: " . implode(", ", $new_addresses) . "\n";

            // Check if addresses have changed
            sort($existing_addresses);
            sort($new_addresses);

            $diff1 = array_diff($existing_addresses, $new_addresses);
            $diff2 = array_diff($new_addresses, $existing_addresses);

            if (count($diff1) === 0 && count($diff2) === 0) {
                echo "Alias IPs haven't changed. No update needed.\n";
            } else {
                echo "IP addresses have changed. Updating existing alias...\n";
                if (count($diff1) > 0) {
                    echo "Removed IPs: " . implode(", ", $diff1) . "\n";
                }
                if (count($diff2) > 0) {
                    echo "Added IPs: " . implode(", ", $diff2) . "\n";
                }

                // Update the alias
                $alias['address'] = implode(" ", $new_addresses);
                $alias['descr'] = $alias_desc;
                $alias['detail'] = implode("||", $new_descriptions);
                $alias['type'] = 'host';
                $updated = true;
            }
            break;
        }
    }
}

// If the alias doesn't exist, create it
if (!$found) {
    echo "Alias '$alias_name' not found. Creating a new alias.\n";

    if (!isset($config['aliases']['alias'])) {
        $config['aliases']['alias'] = array();
    }

    $new_alias = array(
        'name' => $alias_name,
        'type' => 'host',
        'address' => implode(" ", $new_addresses),
        'descr' => $alias_desc,
        'detail' => implode("||", $new_descriptions)
    );

    $config['aliases']['alias'][] = $new_alias;
    $updated = true;
}

// Save the updated configuration if needed
if ($updated) {
    echo "Saving configuration changes...\n";
    write_config("Updated WAN IP alias via script");

    echo "Applying firewall changes...\n";
    filter_configure();

    echo "Alias '$alias_name' updated successfully.\n";
}

// Additional verification check
$new_config = parse_config();
$verified = false;

foreach ($new_config['aliases']['alias'] as $alias) {
    if ($alias['name'] == $alias_name) {
        $verified = true;
        $addresses = is_array($alias['address']) ? $alias['address'] : explode(" ", $alias['address']);
        $addresses = array_filter($addresses);
        echo "Verification: Alias now contains " . count($addresses) . " IPs.\n";
        echo "Current IPs in alias: " . implode(", ", $addresses) . "\n";
        break;
    }
}

if (!$verified) {
    echo "WARNING: Could not verify alias after update.\n";
}

// Check if alias is loaded in pf tables
$alias_table_file = "/var/db/aliastables/{$alias_name}";
if (file_exists($alias_table_file)) {
    echo "Alias table file exists.\n";
} else {
    echo "Alias table file not found. Attempting to reload tables...\n";
    system("/etc/rc.update_urltables now");
}
?>
EOF

# Execute PHP script
echo "Executing PHP update script..."
php -f /tmp/update_alias.php "$TEMP_JSON" "$ALIAS_NAME" "$ALIAS_DESC"

# Additional check to ensure the alias is loaded into the firewall
echo "Verifying alias was loaded into pf tables..."
if pfctl -t $ALIAS_NAME -T show >/dev/null 2>&1; then
    echo "pfctl reports alias $ALIAS_NAME is loaded with these entries:"
    pfctl -t $ALIAS_NAME -T show
else
    echo "WARNING: pfctl does not report the alias as loaded!"
fi

# Cleanup temporary files
rm -f $TEMP_JSON
rm -f /tmp/update_alias.php

echo "$(date): Script completed"
exit 0
