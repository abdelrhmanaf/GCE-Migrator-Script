#!/usr/bin/env bash
# Set up some functions, initialize vars
COUNT=0
ERROR=0
ERRORMSG="OK"
IMAGE_ONLY=0 # Variable to indicate if the script should stop after creating the machine image

# Error out function to call if needed
ERROR_OUT() {
    if [ $ERROR -ne 0 ]; then
        echo $ERRORMSG
        echo "See help:"
        SHOW_HELP
        exit 1
    fi
}

# Arguments and switches input
if [[ ${#} -eq 0 ]]; then
    ERROR_OUT
else
    while getopts ":s:d:n:m:S:z:u:t:i" OPTION; do  # Added 'i' for image only
        case $OPTION in
            s) SOURCEPROJECT_ID=${OPTARG};;
            d) DESTPROJECT_ID=${OPTARG};;
            n) NETWORK=${OPTARG};;
            m) METHOD=${OPTARG};;
            S) SHIELDED_VM="1";;
            z) DESTINATION_ZONE=${OPTARG};; # New option for destination zone
            u) DESTINATION_SUBNETWORK=${OPTARG};; # New option for destination subnetwork
            t) MACHINE_TYPE=${OPTARG};; # New option for machine type
            i) IMAGE_ONLY=1;; # New option to stop after creating the image
            \?) ERRORMSG="Unknown option: -$OPTARG";ERROR_OUT;;
            :) ERRORMSG="Missing option argument for -$OPTARG.";ERROR_OUT;;
            *) ERRORMSG="Unimplemented option: -$OPTARG";ERROR_OUT;;
        esac
    done
fi

# Shows help function and instructions if errors are found
SHOW_HELP() {
    echo "GCE MIGRATOR HELP"
    echo "  Use format ./gce-migrate.sh -s <sourceproject ID> -d <destproject ID> -n <network> -m <migration-type> -z <destination zone> -u <destination subnetwork> -t <machine type> -i"
    echo "      <sourceproject ID>: The project ID (not the name) where VM currently lives"
    echo "      <destproject ID>: The project ID (also, not the name) where VM will reside after migration"
    echo "      <network>: The desired network for the new VM to be connected to (Must be accessible by the destination project)"
    echo "                  alternatively, you may set to 'static' to retain the source VM IP address, but the VPC must be accessible from the destination project"
    echo "      <migration-type>: Must be 'bulk', or a comma-separated list of VM names - Bulk migrates all VMs in a project, and VM names will migrate those VMs"
    echo "      <destination zone>: The zone in the destination project where you want to create the new VM"
    echo "      <destination subnetwork>: The subnetwork in the destination project where you want to create the new VM"
    echo "      <machine type>: The desired machine type for the new VM (Optional)"
    echo "      -i: Stop after creating the machine image without creating the VM"
    echo " "
    echo "  Examples:"
    echo "      ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m myvm1,myvm2,myvm3 -z us-central1-b -u subnetwork-name -t n1-standard-1"    
    echo "      ./gce-migrate.sh -s sourceproject1 -d destproject1 -n static -m myvm1,myvm2 -S -z us-central1-c -u subnetwork-name -t n1-standard-1"
    echo "      ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m bulk -z us-central1-a -u subnetwork-name -t n1-standard-1"
    echo "      ./gce-migrate.sh -s sourceproject1 -d destproject1 -n default -m bulk -z us-central1-a -u subnetwork-name -t n1-standard-1 -i"
}

# Make sure the user entered the correct # of args.  Merge into one function to do all validation in one function
COUNT_ARGS() {
    if [ -z "$SOURCEPROJECT_ID" ] || [ -z "$NETWORK" ] || [ -z "$DESTPROJECT_ID" ] || [ -z "$METHOD" ] || [ -z "$DESTINATION_ZONE" ] || [ -z "$DESTINATION_SUBNETWORK" ]; then
        ERROR=1
        ERRORMSG="ERRORS FOUND IN ARGUMENTS - One or more required arguments not found"
        ERROR_OUT
    fi
}

# Check the project(s) to make sure it exists
CHECK_PROJECT() {
    gcloud projects describe $1 > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        ERROR=1
        ERRORMSG="ERRORS FOUND IN ARGUMENTS - One or more projects not found"
        ERROR_OUT
    fi
    echo "Project $1 verified"   
}

# Check destination network to make sure it exists
CHECK_NETWORK() {
    case $NETWORK in
        static) # If shared, we create the VM in the dest project, but simply have to map the subnet found in the host project shared network
            echo "Static network option, will keep $VM private IP address"
            CREATE_COMMAND() {
                read -p "Now, delete the source VM $VM in project $SOURCEPROJECT_ID - When done, press Enter to continue" </dev/tty
                gcloud beta compute instances create $VM \
                --source-machine-image projects/$DESTPROJECT_ID/global/machineImages/$VM-gcemigr \
                --service-account=$DESTPROJECT_SVCACCT --zone $DESTINATION_ZONE --project $DESTPROJECT_ID --subnet $SUBNETPATH \
                --private-network-ip=$IP --no-address ${MACHINE_TYPE:+--machine-type $MACHINE_TYPE}
            }
        ;;
        *)
            echo "Checking destination network $NETWORK"
            gcloud compute networks list --project $DESTPROJECT_ID | grep -w $NETWORK > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                ERROR=1 
                ERRORMSG="ERRORS FOUND IN ARGUMENTS - Network '$NETWORK' not found for destination project"
                ERROR_OUT
            fi
            CREATE_COMMAND() { 
                gcloud beta compute instances create $VM \
                --source-machine-image projects/$DESTPROJECT_ID/global/machineImages/$VM-gcemigr \
                --service-account=$DESTPROJECT_SVCACCT --zone $DESTINATION_ZONE --project $DESTPROJECT_ID --network $NETWORK --subnet $DESTINATION_SUBNETWORK --no-address ${MACHINE_TYPE:+--machine-type $MACHINE_TYPE}
            }
        ;;
    esac
    echo "Network verified successfully"
}

# Make sure the user has picked a valid migration method - bulk, list, or single
CHECK_METHOD() {
    # Make sure that we are in the source project.  If not, go into it
    echo "Checking if we are already in this project..."
    CURRENTPROJECT=$(gcloud config list project | grep project | awk ' { print $3 } ')
    if [ "$CURRENTPROJECT" != "$SOURCEPROJECT_ID" ]; then
        gcloud config set project $SOURCEPROJECT_ID
        if [ $? -ne 0 ]; then
            echo "Could not set project to $SOURCEPROJECT_ID, exiting"
            ERROR_OUT
            exit 1
        fi
    else
        echo "Already in $SOURCEPROJECT_ID, continuing!"
    fi
    case $METHOD in
        bulk) # If bulk, we set our "COMMAND" to list all VMs in the project to loop through
            COMMAND() {
                gcloud compute instances list --project $SOURCEPROJECT_ID | grep -w -v NAME | awk ' { print $1 } '
            }
        ;;
        *)  # If not bulk, we assume it is  a comma-separated list of VM names and proceed accordingly
            VMS=$(echo $METHOD | tr ',' '\n')
            for VM in $VMS; do
                VMCHECK=$(gcloud compute instances list --filter="name=( '$VM' )" | grep -w "$VM" | awk '{ print $1 }')
                if [[ -z "$VMCHECK" ]]; then
                    ERROR=1
                    ERRORMSG="Unable to find VM $VM" 
                    ERROR_OUT
                fi 
                echo "Using single VM mode.  VM $VM will be migrated..."
            done
            COMMAND() { # Set our command to echo the single VM name 
                echo $VMS
            }
        ;;
    esac     
}

# Verify all the things before proceeding!
COUNT_ARGS
CHECK_PROJECT "$SOURCEPROJECT_ID" 
CHECK_PROJECT "$DESTPROJECT_ID" 
CHECK_NETWORK  
CHECK_METHOD

# Now we can start!
echo "Validated command arguments... Beginning using method $METHOD"
# Make sure default CE Service account exists, add its perms to machine image use
echo "Looking for GCE service account in destination project..."
DESTPROJECT_SVCACCT=$(gcloud iam service-accounts list --filter="displayName=( 'Compute Engine default service account' )" | awk '/EMAIL:/ {print $2}') 
if [[ "$DESTPROJECT_SVCACCT" == *"gserviceaccount.com"* ]]; then
    echo "Found service account!"
    echo "Service account value is $DESTPROJECT_SVCACCT"
else 
    echo "cannot find service account, exiting"
    exit 1
fi
echo "Granting access to use compute images for destination project service Account..."
gcloud projects add-iam-policy-binding $SOURCEPROJECT_ID --member serviceAccount:$DESTPROJECT_SVCACCT --role roles/compute.imageUser
if [ $? -ne 0 ]; then
    echo "Could not set permissions for $DESTPROJECT_SVCACCT, exiting"
    exit 1
fi

# Checks are complete, now starting the migration process
echo "Reading list of VMs to migrate"
for VM in $VMS; do
    echo "Currently working on $VM"
    echo "Getting Zone for $VM..."
    ZONE=$(gcloud compute instances list --filter="NAME=('$VM')" | grep ZONE: | awk '{ print $2 }')
    echo "$VM Zone is in $ZONE" 
    REGION=${ZONE::-2}
    echo "$VM region is $REGION"

    # Get IP information to reuse later 
    echo "Getting current IP address information for $VM"
    IP=$(gcloud compute instances describe $VM --zone $ZONE | grep "networkIP" | awk '{ print $2 }')
    SUBNET=$(gcloud compute instances describe $VM --zone $ZONE | grep -o "subnetworks/.*" | awk 'BEGIN { FS = "/" } ; { print $2 }')
    SUBNETPATH=$(gcloud compute instances describe $VM --zone $ZONE | grep subnet | grep -o "projects/.*")
    echo "IP address info is $IP, subnet is $SUBNET"

    # Uncomment if you want to stop the instance before creating the image
    # echo "Stopping instance $VM for quiesced image..."
    # gcloud compute instances stop $VM --zone $ZONE
    # if [ $? -ne 0 ]; then
    #     echo "failed to cleanly stop VM instance $VM, exiting"
    #     exit 1
    # fi
    if [ "$SHIELDED_VM" == "1" ]; then
        echo "-S detected, enabling VM Shielding options for $VM..."
        gcloud compute instances update $VM --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --zone $ZONE
    fi

    echo "Creating machine image of source VM $VM..."
    # Check if the machine image already exists
    gcloud beta compute machine-images describe "$VM-gcemigr" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Machine image '$VM-gcemigr' already exists. Skipping image creation."
    else
        SOURCE_VM=$(gcloud compute instances describe $VM --format=yaml --zone=$ZONE | grep selfLink: | awk '{print $2}' | cut -d '/' -f 6-)
        gcloud beta compute machine-images create "$VM-gcemigr" \
            --source-instance "$SOURCE_VM" \
            --source-instance-zone="$ZONE" \
            --project="$DESTPROJECT_ID"

        if [ $? -ne 0 ]; then
            ERROR_MSG=$(gcloud beta compute machine-images create "$VM-gcemigr" --source-instance "$SOURCE_VM" --source-instance-zone="$ZONE" --project="$DESTPROJECT_ID" 2>&1)
            if echo "$ERROR_MSG" | grep -q "already exists"; then
                echo "ERROR: Machine image already exists. Please delete the existing machine image before proceeding."
            else
                echo "ERROR: Could not save machine image of $VM. Error details: $ERROR_MSG"
            fi
            exit 1
        fi
    fi

    # Stop after creating the machine image if the -i option is specified
    if [ "$IMAGE_ONLY" -eq 1 ]; then
        echo "Image creation complete. Skipping VM creation as per the -i option."
        continue
    fi

    echo "Now creating VM based on new image..."
    CREATE_COMMAND
    if [ $? -ne 0 ]; then
        if [[ "$ERRORMSG" =~ "Machine type with name" ]]; then
            read -p "The machine type is not available in the destination zone. Please enter the desired machine type: " MACHINE_TYPE
            CREATE_COMMAND=$(echo "$CREATE_COMMAND" | sed "s/--no-address/--machine-type $MACHINE_TYPE --no-address/")
            echo "Using machine type: $MACHINE_TYPE"
            CREATE_COMMAND
            if [ $? -ne 0 ]; then
                echo "ERROR: Could not create new instance of $VM in $DESTPROJECT_ID"
                ERROR=1
                ERRORMSG="Could not create 1 or more VMs, please review output for errors!"
            fi
        elif [[ "$ERRORMSG" =~ "Machine image" ]]; then
            echo "ERROR: Machine image already exists. Please delete the existing machine image before proceeding."
            ERROR=1
            ERRORMSG="Could not create 1 or more VMs, please review output for errors!"
        else
            echo "ERROR: Could not create new instance of $VM in $DESTPROJECT_ID"
            ERROR=1
            ERRORMSG="Could not create 1 or more VMs, please review output for errors!"
        fi
    fi
    echo "Completed migration of $VM"
done

# Done, so check error level and error out if so
ERROR_OUT
echo "Done! Please remember to delete GCE instances from source project after validation!"
