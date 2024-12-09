# Spark Cluster Setup: Master-Worker Configuration

## Overview

This project automates the setup of a Spark cluster with one master node and multiple worker nodes on a shared network using Bash scripts. The setup ensures all nodes are properly configured for distributed computing using Apache Spark.

## Files in the Project

1. `master.sh`: Run this script on the master Linux machine.
2. `worker.sh`: Run this script on the worker Linux machines.

## Prerequisites

### 1. System Requirements

* **Operating System**: All nodes must run Linux.
* **Java 8**: Apache Spark requires Java 8 to function.

### 2. Networking

* All devices (master and workers) must be on the **same network** (e.g., same Wi-Fi hotspot or subnet) to enable communication and discovery using `nmap`.

### 3. Privileges

* Both `master.sh` and `worker.sh` must be run with `sudo` privileges.

## Java 8 Installation Guide

Run the following commands on all nodes to ensure Java 8 is installed:

```bash
# Update package index
sudo apt-get update -y

# Install Java 8
sudo apt-get install -y openjdk-8-jdk

# Verify Java version
java -version
```

The output of `java -version` should confirm Java 8 installation:

```
openjdk version "1.8.x"
```

## Setup Instructions

### 1. Network Configuration

Ensure all Linux devices (master and workers) are connected to the **same network**:
* Use a **mobile hotspot**, Wi-Fi router, or any other LAN network.
* The master node will scan the network to detect worker nodes using `nmap`.

### 2. Run the Master Script

1. On the device intended to act as the **master**, download the `master.sh` script.
2. Grant execute permissions to the script:

```bash
chmod +x master.sh
```

3. Run the script with `sudo` privileges:

```bash
sudo ./master.sh
```

### 3. Run the Worker Script

1. On the devices intended to act as **workers**, download the `worker.sh` script.
2. Grant execute permissions to the script:

```bash
chmod +x worker.sh
```

3. Run the script with `sudo` privileges:

```bash
sudo ./worker.sh
```

### 4. Verify the Setup

* The `master.sh` script will automatically detect worker nodes using `nmap`, set up NFS for shared directories, and configure Spark for distributed computing.
* Workers will mount the shared directory from the master.

## Using the Spark Cluster

Once the setup is complete, you can submit jobs to the Spark cluster from the master node using `spark-submit`. Example command to submit a job:

```bash
/home/constantuser21/master_shared/spark/bin/spark-submit \
--master spark://<MASTER_IP>:7077 \
--class <MAIN_CLASS_NAME> \
<PATH_TO_YOUR_JAR_OR_PYTHON_FILE> \
<JOB_ARGUMENTS>
```

Replace:
* `<MASTER_IP>`: The IP address of the master node.
* `<MAIN_CLASS_NAME>`: The main class for Java/Scala jobs.
* `<PATH_TO_YOUR_JAR_OR_PYTHON_FILE>`: The location of your Spark job file.
* `<JOB_ARGUMENTS>`: Any arguments for your job.

## Important Notes

1. **Sudo Privileges**: Always run the scripts as `sudo`.
2. **Shared Network**: Ensure all nodes are on the same subnet for `nmap` to detect them.
3. **Java 8**: Ensure Java 8 is installed on all machines before running the scripts.
4. **Script Logging**: Check the output of `master.sh` and `worker.sh` for potential errors during setup.

## Troubleshooting

### 1. Java Not Installed

If Java 8 is missing, the scripts will fail. Reinstall Java 8 as per the guide above.

### 2. Worker Node Not Detected

* Ensure all devices are on the same network.
* Verify that `nmap` is installed on the master machine using:

```bash
sudo apt-get install -y nmap
```

### 3. Mount Issues on Workers

* Check that the NFS server is running on the master node:

```bash
sudo systemctl status nfs-kernel-server
```

* Verify that the shared directory is mounted on the worker node:

```bash
mount | grep master_shared
```

## FAQs

### Q1. Can I run the scripts on different networks?

No, all devices must be on the same network for the master to detect the workers using `nmap`.

### Q2. Do I need to install Spark manually?

No, the scripts handle the configuration for Spark, provided it is pre-installed in the `master_shared` directory.
