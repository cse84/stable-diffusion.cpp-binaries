#This version offers to reuse last prompt
#this version can evaluate the contents of /home/deck/stable-diffusion.cpp/Checkpoints and prompt the user to select a checkpoint from that dir. logic to differentiate SD vs SDXL to be added
#This version saves output files as . To change back to Output_#.png, set line 11 to base_filename="output" and 15 to while [[ -e "$output_dir/${base_filename}_${i}.png" ]]; do
#This version will query the user for which LORA, if any, they want to use and the strength of the LORA. The script assumes LORAS are at /home/deck/stable-diffusion.cpp/LORAs/
#This version has the capability to specify a neg prompt and will ask if you want to reuse the previous one
#This version will verify SD vs SDXL prompt/parameter compliance with the selected model. If noncompliant, will offer to attempt to automatically comply the prompt/parameters with the SDXL model
#!/bin/bash

#!/bin/bash

# Directory to save images
output_dir="output_images"
mkdir -p "$output_dir"

# Base filename
base_filename="output"

# Find the next available filename
i=1
while [[ -e "$output_dir/${base_filename}_${i}.png" ]]; do
    ((i++))
done

# Function to get a random seed
get_random_seed() {
    echo $((RANDOM * RANDOM))
}

# Function to list files in a directory and prompt the user to choose one
list_checkpoints() {
    local dir=$1
    local files=("$dir"/*)
    echo "Checkpoints found in $dir:"
    for idx in "${!files[@]}"; do
        echo "$((idx + 1))) ${files[$idx]##*/}"
    done
    read -p "Please input the number corresponding to the Checkpoint to be used in this generation: " choice
    if [[ $choice -gt 0 && $choice -le ${#files[@]} ]]; then
        selected_checkpoint="${files[$((choice - 1))]##*/}"
        echo "You've chosen: $choice) $selected_checkpoint"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# Function to list LoRAs in a directory and prompt the user to choose one
list_loras() {
    local dir=$1
    local files=("$dir"/*)
    echo "LoRAs found in $dir:"
    for idx in "${!files[@]}"; do
        echo "$((idx + 1))) ${files[$idx]##*/}"
    done
    read -p "Please input the number corresponding to the LORA to be used in this generation: " choice
    if [[ $choice -gt 0 && $choice -le ${#files[@]} ]]; then
        selected_lora="${files[$((choice - 1))]##*/}"
        echo "You've chosen: $choice) $selected_lora"

        # Prompt the user to indicate the strength of the LORA
        read -p "Enter the strength of the LORA (e.g., 1): " lora_strength

        # Amend the user's prompt to include the selected LORA and its strength
        prompt="$prompt <lora:${selected_lora%.safetensors}:$lora_strength>"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# List checkpoints and prompt the user to choose one
checkpoint_dir="/home/deck/stable-diffusion.cpp/Checkpoints"
list_checkpoints "$checkpoint_dir"

# Change directory to Checkpoints to look for the model
cd /home/deck/stable-diffusion.cpp/Checkpoints

# Check if the selected checkpoint exists in the Checkpoints directory
if [[ ! -f "$selected_checkpoint" ]]; then
    echo "Model $selected_checkpoint not found in /home/deck/stable-diffusion.cpp/Checkpoints"
    exit 1
fi

# Return to the base working directory
cd /home/deck/stable-diffusion.cpp/

# Prompt the user for a new prompt or reuse the previous one
if [[ -f "last_prompt.txt" ]]; then
    echo "Do you want to reuse the previous prompt? (y/n)"
    read reuse_prompt
    if [[ "$reuse_prompt" == "y" ]]; then
        prompt=$(cat last_prompt.txt)
    else
        echo "Enter your new prompt:"
        read prompt
        echo "$prompt" > last_prompt.txt
    fi
else
    echo "Enter your prompt:"
    read prompt
    echo "$prompt" > last_prompt.txt
fi

# Prompt the user for a negative prompt or reuse the previous one
if [[ -f "last_negative_prompt.txt" ]]; then
    echo "Do you want to reuse the previous negative prompt? (y/n)"
    read reuse_negative_prompt
    if [[ "$reuse_negative_prompt" == "y" ]]; then
        negative_prompt=$(cat last_negative_prompt.txt)
    else
        read -p "Enter a negative prompt (things you don't want to see in the output): " negative_prompt
        echo "$negative_prompt" > last_negative_prompt.txt
    fi
else
    read -p "Enter a negative prompt (things you don't want to see in the output): " negative_prompt
    echo "$negative_prompt" > last_negative_prompt.txt
fi

# Prompt the user if they want to use a LORA for generating this image
echo "Would you like to use a LORA for generating this image? (y/n)"
read use_lora

if [[ "$use_lora" == "y" ]]; then
    # List LoRAs and prompt the user to choose one
    lora_dir="/home/deck/stable-diffusion.cpp/LORAs"
    list_loras "$lora_dir"
fi

# Display height/width presets and prompt the user to choose one
echo "Choose a resolution preset:"
echo "1) Low (512x512)"
echo "2) Medium (1024x1024)"
echo "3) High (1536x1536)"
echo "4) Very High (2048x2048)"
echo "5) Ultra-HD (4096x4096)"
read -p "Enter the number corresponding to your choice: " resolution_choice

case $resolution_choice in
    1)
        height=512
        width=512
        ;;
    2)
        height=1024
        width=1024
        ;;
    3)
        height=1536
        width=1536
        ;;
    4)
        height=2048
        width=2048
        ;;
    5)
        height=4096
        width=4096
        ;;
    *)
        echo "Invalid choice, defaulting to Low (512x512)"
        height=512
        width=512
        ;;
esac

# Prompt the user to specify the number of steps (default to 8)
read -p "Enter the number of steps (default is 8): " steps
steps=${steps:-8}

# Prompt the user to enter the number of pictures to generate
read -p "Enter the number of pictures to generate: " num_pictures

# Check if model is SDXL and warn user if true, ask if they want automatic adjustment for SDXL compliance
if [[ "$selected_checkpoint" == *"SDXL"* ]]; then
    echo "WARNING: The model being used is SDXL."
    read -p "Would you like your prompt automatically adjusted for SDXL compliance? (y/n): " adjust_sdxl
    if [[ "$adjust_sdxl" == "y" ]]; then
        sdxl_compliance="--vae-on-cpu"
    else
        sdxl_compliance=""
    fi
else
    sdxl_compliance=""
fi

# Generate the specified number of pictures
for ((j=1; j<=num_pictures; j++)); do
    # Get a random seed
    seed=$(get_random_seed)

    # Generate a safe filename based on the prompt and checkpoint name, incrementing the number to avoid duplicates
    safe_prompt=$(echo "$prompt" | tr ' ' '_')
    safe_checkpoint=$(echo "$selected_checkpoint" | tr ' ' '_')
    output_filename="${safe_prompt}-${safe_checkpoint}_${i}.png"

    # Run the stable-diffusion command with the new filename and random seed, using the selected checkpoint from Checkpoints directory
    ./sd -m "/home/deck/stable-diffusion.cpp/Checkpoints/$selected_checkpoint" -H "$height" -W "$width"  --vae-on-cpu --sampling-method lcm --steps "$steps" --cfg-scale 1 --seed "$seed" --prompt "$prompt" --negative-prompt "$negative_prompt" $sdxl_compliance -o "$output_dir/$output_filename"

    # Check for memory allocation error
    if grep -q "ErrorOutOfDeviceMemory" <<< "$(tail -n 10 output.log)"; then
        echo "Memory allocation error encountered. Stopping the script."
        exit 1
    fi

    # Increment the filename counter
    ((i++))
done



# create dir with
#cd /home/deck/stable-diffusion.cpp/
#chmod +x imgen.sh

#run this script to generate multiple images in 1 command
#./imgen
