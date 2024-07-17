# GCE Migrator Script

This script helps you migrate Google Cloud Engine (GCE) virtual machines from one project to another. It allows for bulk migration of all VMs in a project or migration of specified VMs. The script also includes options for specifying the destination zone, subnetwork, and machine type, and for stopping after creating the machine image.

## Features
- Migrate all VMs in a source project or specific VMs
- Retain the source VM's IP address (if using the 'static' network option)
- Optionally stop after creating the machine image without creating the VM
- Support for shielded VM options
- Specify destination zone, subnetwork, and machine type

## Usage

### Command Format
```bash
./gce-migrate.sh -s <sourceproject ID> -d <destproject ID> -n <network> -m <migration-type> -z <destination zone> -u <destination subnetwork> -t <machine type> -i
```

### Parameters
- `-s <sourceproject ID>`: The project ID (not the name) where the VM currently resides.
- `-d <destproject ID>`: The project ID (also, not the name) where the VM will be migrated.
- `-n <network>`: The desired network for the new VM to be connected to. Must be accessible by the destination project. Alternatively, set to 'static' to retain the source VM's IP address, but the VPC must be accessible from the destination project.
- `-m <migration-type>`: Must be 'bulk' to migrate all VMs in a project, or a comma-separated list of VM names to migrate specific VMs.
- `-z <destination zone>`: The zone in the destination project where you want to create the new VM.
- `-u <destination subnetwork>`: The subnetwork in the destination project where you want to create the new VM.
- `-t <machine type>`: The desired machine type for the new VM (Optional).
- `-i`: Stop after creating the machine image without creating the VM.

### Examples
1. Migrate specific VMs:
    ```bash
    ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m myvm1,myvm2,myvm3 -z us-central1-b -u subnetwork-name -t n1-standard-1
    ```
2. Migrate specific VMs and retain IP address:
    ```bash
    ./gce-migrate.sh -s sourceproject1 -d destproject1 -n static -m myvm1,myvm2 -S -z us-central1-c -u subnetwork-name -t n1-standard-1
    ```
3. Bulk migrate all VMs in the project:
    ```bash
    ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m bulk -z us-central1-a -u subnetwork-name -t n1-standard-1
    ```
4. Create machine images only (no VM creation):
    ```bash
    ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m bulk -z us-central1-a -u subnetwork-name -t n1-standard-1 -i
    ```

## Script Details
The script performs the following steps:

1. **Initialize Variables and Functions**:
    - Sets up variables and helper functions.
    - Parses command-line arguments and validates them.

2. **Project and Network Verification**:
    - Checks if the specified projects and networks exist.
    - Validates the migration method (bulk or list of VMs).

3. **Service Account Verification**:
    - Verifies the default Compute Engine service account in the destination project.
    - Grants the necessary IAM roles to the service account.

4. **Migration Process**:
    - Iterates through the list of VMs to migrate.
    - Gets zone, IP address, and subnet information for each VM.
    - Creates a machine image of each VM.
    - If the `-i` option is not specified, creates new VMs in the destination project using the machine image.

5. **Error Handling**:
    - Checks for errors throughout the process and exits if any are found.

## Error Handling
The script includes robust error handling. If any required arguments are missing or an error occurs during the process, the script will output an error message and display the help instructions.

## Help
To view the help instructions, run the script without any arguments:
```bash
./gce-migrate.sh
```

## Notes
- Ensure that you have the necessary permissions to perform operations on the specified projects and networks.
- Validate that the network and subnetwork specified in the destination project are correctly configured and accessible.

Feel free to customize the script according to your specific requirements.
