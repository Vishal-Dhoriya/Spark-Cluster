#!/bin/bash

# Declare the array for storing ips
declare -a linux_ips=()

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "You need to run this script with sudo privileges."
    exit 1
fi

# Check if NFS server is already installed
if command -v nfsstat &> /dev/null; then
	echo "NFS server is already installed."

else
	echo "NFS server is not installed."
	sudo apt update  >/dev/null 2>&1

	echo "Installing NFS server..."
	sudo apt install -y nfs-kernel-server  >/dev/null 2>&1

	echo "Starting NFS server..."
	sudo systemctl start nfs-kernel-server  >/dev/null 2>&1
	sudo systemctl enable nfs-kernel-server  >/dev/null 2>&1

fi

# Set variables
username="constantuser21"
password="user"

# Save the original user
originaluser=$SUDO_USER
echo "The original user is $originaluser."


# Function to determine the subnet from the IP address
getsubnet()
{
	ip=$1
	IFS='.' read -r i1 i2 i3 i4 <<<"$ip"
	echo "$i1.$i2.$i3.0"
}

# Get the current machine's IP address and subnet
myip=$( hostname -I | awk '{print $1}')
echo "$myip is my ip adress"
mysubnet=$(getsubnet "$myip")
echo "$mysubnet is my subnet"

# Check if user already exists
if id "$username" &>/dev/null; then
    echo "User $username already exists."
else
    # Create the user and set password
    echo "Creating user $username..."
    useradd -m "$username"
    echo "$username:$password" | chpasswd
fi

# Grant passwordless sudo privileges to the user
sudoers_file="/etc/sudoers.d/$username"
if grep -q "^$username " "$sudoers_file" 2>/dev/null;then
	echo "User $username has already have passwordless priveleges"
else
	echo "$username ALL =(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" > /dev/null
	echo "Passwordless sudo privileges have been granted to $username (restricted to their own user)."
fi

# Check if a user exists on a remote host
check_user_exists() {
    host=$1
    sudo -u "$username" sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$host" "true" &> /dev/null
    return $?
}

# Function to strip parentheses from IP string
modify_ip()
{
	temp=""
	declare -n ref=$1
	length="${#ref}"
	
	for ((i=0; i<length; i++));do
	char="${ref:i:1}"
	
	if [[ "$char" != '(' ]] && [[ "$char" != ')' ]];then
	temp+="$char"
	fi
	done
	ref="$temp"

}
run_nmap() {
    current_ip=""
    string1="Aggressive OS guesses: Linux"
    string2="OS details: Linux"
    string3="Nmap scan report"
    subnet=$1
    # Run nmap and capture output line by line using process substitution
    while IFS= read -r line; do
        #echo "the line : $line"  # Debug output to check each line

        if [[ "$line" == *"$string3"* ]]; then
            #echo "This is nmap "
            sixth_element=$(echo "$line" | awk '{print $6}')
            fifth_element=$(echo "$line" | awk '{print $5}')

            if [ -n "$sixth_element" ]; then
            	
                current_ip="$sixth_element"
                modify_ip current_ip
            else
                current_ip="$fifth_element"
            fi
            #echo "$current_ip"
        fi

        if [[ "$line" == *"$string1"* ]] || [[ "$line" == *"$string2"* ]]; then
        	
            if [[ "$current_ip" != "$myip" ]];then
            linux_ips+=("$current_ip")
            fi
           # echo "${linux_ips[0]}"
           # echo "This is present that is $string1"
        fi
    done < <(sudo nmap -p 22 -O --open --osscan-guess "$subnet"/24 2>/dev/null)


}

# Run the nmap function
run_nmap "$mysubnet"

# Capture the status of the run_nmap function
nmap_status=$?

# Check if the nmap command was successful
if [ $nmap_status -eq 0 ]; then
    if [ ${#linux_ips[@]} -gt 0 ]; then
        echo "Linux hosts detected at the following IPs:"
        for ip in "${linux_ips[@]}"; do
            echo "$ip"
        done
    else
        echo "No Linux hosts detected."
        exit 1
    fi
else
    echo "Nmap didn't run successfully or no hosts detected."
    exit 1
fi

# Ensure sshpass is installed
if ! command -v sshpass &> /dev/null; then 
    echo "sshpass is not installed, installing it..."
    sudo apt-get install -y sshpass
fi

# Check if the SSH key already exists
if [ ! -f /home/"$username"/.ssh/id_rsa ]; then
    echo "Generating SSH key for user $username..."
    sudo -u "$username" ssh-keygen -t rsa -b 3072 -f /home/"$username"/.ssh/id_rsa -q -N ""
else
    echo "SSH key already exists for user $username."
fi


# Remote host details

for ip in "${linux_ips[@]}"; do
	host="$ip"
	while ! check_user_exists "$host"; do
	echo "User $username does not exist on $host yet, trying again in 5s..."
	sleep 5
	done
	
# Copy the SSH key to the remote host

	echo "Copying SSH key to $host..."
	sudo -u "$username" sshpass -p "$password" ssh-copy-id -o StrictHostKeyChecking=no "$username@$host"
	echo "SSH key copied successfully to $host"
    	
done









