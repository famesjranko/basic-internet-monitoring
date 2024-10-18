import asyncio
import tapo
import json  # Importing json for pretty printing the output
import logging
from datetime import datetime

# Set up logging configuration
logging.basicConfig(
    filename="logs/p100-smart-plug-logfile.log",  # Update to the correct path where you want the log file to be saved
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

# Your Tapo credentials and IP address
email = "<tapo username/email>"
password = "<tapo password>"
device_ip = "<device ip>"
device_name = "<device name>"

# Cooldown settings
COOLDOWN_FILE = "logs/cooldown.txt"
COOLDOWN_PERIOD = 600  # 10 minutes cooldown in seconds (600 seconds = 10 minutes)

# The time to wait between turning off and on the device (in seconds)
wait_time = 30  # You can change this to any number of seconds
retry_attempts = 3  # Number of retries if a connection fails

# Function to check if cooldown period is active
def is_in_cooldown():
    if os.path.exists(COOLDOWN_FILE):
        with open(COOLDOWN_FILE, "r") as f:
            last_cycle = int(f.read().strip())
        current_time = int(datetime.now().timestamp())
        time_diff = current_time - last_cycle
        if time_diff < COOLDOWN_PERIOD:
            logging.info(f"Cooldown period is still active, skipping power cycle. Time left: {COOLDOWN_PERIOD - time_diff} seconds.")
            return True
    return False

# Function to update cooldown file
def update_cooldown_file():
    with open(COOLDOWN_FILE, "w") as f:
        f.write(str(int(datetime.now().timestamp())))
    logging.info("Cooldown file updated with the current timestamp.")

async def control_tapo():
    try:
        # Check if we are within cooldown period
        if is_in_cooldown():
            return

        # Initialize API client
        client = tapo.ApiClient(email, password)

        # Get the P100 device (requires `await`)
        device = await client.p100(device_ip)

        # Refresh the session (useful if connection becomes inactive)
        await device.refresh_session()
        logging.info(f"Session refreshed for {device_name}.")

        # Turn off the device
        await device.off()
        logging.info(f"{device_name} has been turned off.")

        # Wait for the specified period
        await asyncio.sleep(wait_time)
        logging.info(f"Waited for {wait_time} seconds.")

        # Turn the device back on
        await device.on()
        logging.info(f"{device_name} has been turned back on.")

        # Update cooldown file
        update_cooldown_file()

        # Print device info after successful operation
        await print_device_info(device)

    except asyncio.TimeoutError:
        logging.error("The request timed out. Please check your network connection or the device.")
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")
        await handle_exception(device)

async def handle_exception(device):
    # Retry logic on exception
    for attempt in range(1, retry_attempts + 1):
        try:
            logging.warning(f"Attempting to refresh session and retry... (Attempt {attempt}/{retry_attempts})")
            await device.refresh_session()

            # Try to turn the device on after failure
            await device.on()
            logging.info(f"{device_name} has been turned back on after retry attempt {attempt}.")

            # Print device info after successful retry
            await print_device_info(device)
            return  # Exit the loop if successful
        except Exception as retry_error:
            logging.error(f"Retry attempt {attempt} failed: {retry_error}")
            if attempt == retry_attempts:
                logging.critical(f"All retry attempts failed. Please check your connection.")
                return

async def print_device_info(device):
    try:
        # Get additional device information in JSON format
        device_info_json = await device.get_device_info_json()

        # Pretty print the JSON response
        pretty_device_info = json.dumps(device_info_json, indent=4)
        logging.info(f"Device info: {device_info_json}")
    except Exception as e:
        logging.error(f"Failed to retrieve device info: {e}")

# Run the async function
asyncio.run(control_tapo())