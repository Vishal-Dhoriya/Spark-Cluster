#!/bin/bash


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
	sudo systemctl enable nfs-kernel-server  >/dev/null 2>&1

fi

# Set variables
username="constantuser21"
password="user"
shared_name="master_shared"


# Save the original user
originaluser=$SUDO_USER
echo "The original user is $originaluser."


# Array for storing ips of Linux Devices
declare -a linux_ips=()

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


# Function to configure and set up NFS on the master node
nfs_mount()
{
	sudo apt update >/dev/null 2>&1
	if dpkg -s nfs-kernel-server >/dev/null 2>&1; then
		echo "nfs server is installed"
	else
		echo "nfs server is not installed so installing"
		sudo apt install nfs-kernel-server -y >/dev/null 2>&1
	fi
	pathd="/home/$username/$shared_name"
	
	if [[ -d "$pathd" ]];then
		echo "There is already shared folder created"
	else 
		echo "Creating shared folder: master_shared"
		sudo mkdir -p "$pathd"
		echo "Created shared folder: master_shared"
		sudo chown nobody:nogroup "$pathd"
		sudo chmod -R 777 "$pathd"
		echo "Changed permissions"
		echo "$pathd *(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
		sudo exportfs -a
		sudo systemctl restart nfs-kernel-server
	fi
}


# Function to configure NFS on worker nodes
nfs_mount_worker() 
{
	master_ip=$1
	pathd="/home/"$username"/master_shared"
	if [[ -d "$pathd" ]];then
	echo "There is already shared folder created"
	else 
		echo "Creating shared folder: master_shared"
		sudo mkdir -p "$pathd"

	fi
	sudo mount "$master_ip":"$pathd" "$pathd"
	  
	echo "mounted successfully "
	
	
	
	
}

# Run the NFS mount setup for the master node
nfs_mount

# Check if a user exists on a remote host
check_user_exists() {
    host=$1
    sudo -u "$username" sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$host" "true" &> /dev/null
    return $?
}

# Function to strip parentheses from IP strings
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

# Run nmap to scan for Linux hosts in the subnet
run_nmap() {
    current_ip=""
    string1="Aggressive OS guesses: Linux"
    string2="OS details: Linux"
    string3="Nmap scan report"
    subnet=$1
    while IFS= read -r line; do
        if [[ "$line" == *"$string3"* ]]; then
            sixth_element=$(echo "$line" | awk '{print $6}')
            fifth_element=$(echo "$line" | awk '{print $5}')

            if [ -n "$sixth_element" ]; then
            	
                current_ip="$sixth_element"
                modify_ip current_ip
            else
                current_ip="$fifth_element"
            fi
            
        fi

        if [[ "$line" == *"$string1"* ]] || [[ "$line" == *"$string2"* ]]; then
        	
            if [[ "$current_ip" != "$myip" ]];then
            linux_ips+=("$current_ip")
            fi
        fi
    done < <(sudo nmap  -p 22  -O --open --osscan-guess "$subnet"/24 2>/dev/null)


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
	#sudo -u "$username" ssh "$username@$host" "echo '$myip' > ~/ip.txt"
	echo "SSH key copied successfully to $host"
	echo "Mounting the $host..."
sudo -u "$username" ssh "$username@$host" "bash -s" <<EOF
# Commands to be executed on the remote server
if dpkg -l | grep -q "^ii  nfs-common " >/dev/null 2>&1; then
	echo "nfs-common is installed"
else
	echo "nfs-common is not installed so installing"
	sudo apt install -y nfs-common >/dev/null 2>&1
fi
pathd="/home/$username/master_shared"
if [[ -d "\$pathd" ]]; then
    echo "There is already a shared folder created"
else 
    echo "Creating shared folder: master_shared"
    sudo mkdir -p "\$pathd"
fi
sudo mount "$myip:\$pathd" "\$pathd"
echo "mounted successfully on $host"
EOF

done


# Spark setup

URL_SPARK="https://archive.apache.org/dist/spark/spark-3.5.2/spark-3.5.2-bin-hadoop3.tgz"
path_spark="/home/$username/spark.tgz"
extract_dir="/home/$username/$shared_name"
final_path_spark="$extract_dir/spark-3.5.2-bin-hadoop3"
if [[ ! -d "$final_path_spark" ]];then
	echo "Spark does'nt exist"
	if [[ -f "$path_spark" ]];then
		echo "Spark.tgz already exists"
	else
	
		echo "Downloading spark.tgz at $path_spark"
		sudo -u "$username" curl  -o "$path_spark" "$URL_SPARK"

	fi
	echo "spark has not been extracted so extracting"
	sudo -u "$username" mkdir -p "$extract_dir"
	sudo -u "$username" tar -xzf "$path_spark" -C "$extract_dir"
	if [[ $? -eq 0 ]];then
		echo "Extracted succesfully at $extract_dir"
	else
		echo "Not able to extract"
		exit 1
	fi
	sudo chmod 777 -R "$final_path_spark"
fi
	
# Configure Spark workers
workers_path="$final_path_spark/conf/workers"
echo "workers_path: $workers_path"

> "$workers_path"
for ip in "${linux_ips[@]}";
do
	echo "$ip" >> "$workers_path"	
done

spark_env_conf="$final_path_spark/conf/spark-env.sh"
spark_local_dir_master="/home/$username/spark-temp/master"

echo "All workers added in workers file"
sudo -u "$username" cat "$workers_path"

echo "spark_env_conf: $spark_env_conf"
echo "spark_local_dir_master: $spark_local_dir_master"

if [[ ! -d "$spark_local_dir_master" ]]; then
    echo "spark master local directory doesn't exist so creating it"
    mkdir -p "$spark_local_dir_master"
else
    echo "spark master local directory already exists"
fi

echo "Configuring master... $myip"

# Configuring the master
sudo -u "$username" bash -c "cat <<'EOL' > $spark_env_conf
export SPARK_MASTER_HOST=\"$myip\"
export SPARK_LOCAL_DIRS=\"$spark_local_dir_master\"
EOL"

echo "Starting master..."
sudo -u "$username" "$final_path_spark/sbin/start-master.sh"

sudo chmod 777 -R "$final_path_spark"
# Loop through each worker
for i in "${!linux_ips[@]}"; do
	worker_ip="${linux_ips[$i]}"
	worker_id="$i"
	echo "Configuring the worker with IP: $worker_ip and ID: $worker_id"
	echo "Checking if local and worker directories exist on $worker_ip..."

	# Check if the directories exist on the worker
	if sudo -u "$username" ssh "$username@$worker_ip" "[ -d /home/$username/spark-logs/worker${worker_id} ] && [ -d /home/$username/spark-temp/worker${worker_id} ]"; then
		echo "Directories exist on $worker_ip."
	else
		echo "Directories do not exist on $worker_ip. Creating them..."
		sudo -u "$username" ssh "$username@$worker_ip" "mkdir -p /home/$username/spark-logs/worker${worker_id} /home/$username/spark-temp/worker${worker_id}"
	fi

	# Configuring the worker
	echo "Configuring worker environment for $worker_ip..."
sudo -u "$username" bash -c "cat <<'EOL' > $spark_env_conf
export SPARK_MASTER_HOST=\"$myip\"
export SPARK_WORKER_DIR=\"/home/$username/spark-logs/worker${worker_id}\"
export SPARK_LOCAL_DIRS=\"/home/$username/spark-temp/worker${worker_id}\"
export SPARK_WORKER_PORT=\"$((7078 + worker_id))\"
EOL"
	sudo -u "$username" cat "$spark_env_conf"
	echo "Starting the worker with IP: $worker_ip and ID: $worker_id"
	sudo -u "$username" ssh "$username@$worker_ip" "$final_path_spark/sbin/start-worker.sh spark://$myip:7077"

done



