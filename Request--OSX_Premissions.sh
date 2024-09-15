: '
.SYNOPSIS
    Request-OSX_Permissions.sh
.NOTES
    Written by Nathan LeDuc via contractor "Elencio Mukaj"
.VERSION
    1.0.3 2024-09-03
        * Added function to wait for user interaction and prevent popups while the Mac is on the lock screen. 
    1.0.2 2024-08-28
        * Added function to prevent  multiple popups and handle Apple Event timeouts. 
    1.0.1 2024-08-23
        * Added function to check if logged in user(s) have admin rights. 
    1.0.0 2024-08-22
        * Initial script creation

.DESCRIPTION
    This helper script checks for Ninja and Connectwise Control permissions on OSX. It requires that the user logged in have administrative 
    rights in order to manually grant access. Due to OSX security, this scripts purpose is to help user grant access easily. 
'



#!/bin/bash
# Function to check if any logged-in user has admin rights
Main() {
    # Get the list of logged-in users
    logged_in_users=$(users)
    
    # Check if there are any logged-in users
    if [ -z "$logged_in_users" ]; then
        echo "No users are currently logged in."
        exit 1
    fi
    
    # Iterate over each logged-in user
    for user in $logged_in_users; do
        # Check if the user is in the admin group
        if dscl . -read /Groups/admin GroupMembership | grep -q "\b$user\b"; then
            echo "User $user has admin rights. Continuing script..."
            Request_Permissions
            return 0
        fi
    done
    
    # If no admin user was found, exit the script
    echo "No logged-in users have admin rights."
    exit 1
}

Request_Permissions (){
    TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
    
    # Path to the app you want to check
    EXECUTABLE_PATH="/Applications/NinjaRMMAgent/programfiles/ninjarmm-macagent"
    APP_PATH_2="/Applications/connectwisecontrol-ea1f1eccebd72cab.app"
    
    # Retrieve the ninjarmm's bundle identifier
    REAL_PATH=$(realpath "$EXECUTABLE_PATH")
    
    BUNDLE_ID=$(codesign -d --entitlements :- "$REAL_PATH" 2>/dev/null | grep -A1 "<key>application-identifier</key>" | grep "<string>" | sed 's/<[^>]*>//g')
    
    # Retrieve the app's bundle identifier
    
    APP_BUNDLE_ID_2=$(defaults read "$APP_PATH_2/Contents/Info" CFBundleIdentifier)
    
    if [ -z "$APP_BUNDLE_ID_2" ]; then
        echo "Could not determine the bundle identifier for $APP_PATH_2."
        exit 1
    fi
    
    # Check for Full Disk Access for NinjaRMM
    while true; do
        HAS_FDA=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND (client='$BUNDLE_ID' OR client='$REAL_PATH');")
        
        if [ "$HAS_FDA" == "2" ]; then
            echo "NinjaRMM has Full Disk Access."
            break
        else
            # Recheck permissions before showing the dialog
            echo "Rechecking NinjaRMM Full Disk Access..."
            sleep 3
            HAS_FDA=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND (client='$BUNDLE_ID' OR client='$REAL_PATH');")
            if [ "$HAS_FDA" == "2" ]; then
                echo "NinjaRMM has Full Disk Access."
                break
            else
                show_dialog_with_timeout "Please grant Full Disk Access to NinjaRmm in the Security & Privacy settings." "AllFiles"
            fi
        fi
    done
    
    # Check for Accessibility permissions for ConnectWise
    while true; do
        has_accessibility=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='$APP_BUNDLE_ID_2';")
        
        if [ "$has_accessibility" == "2" ]; then
            echo "ConnectWise has Accessibility permissions."
            break
        else
            # Recheck permissions before showing the dialog
            echo "Rechecking ConnectWise Accessibility permissions..."
            sleep 3
            has_accessibility=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='$APP_BUNDLE_ID_2';")
            if [ "$has_accessibility" == "2" ]; then
                echo "ConnectWise has Accessibility permissions."
                break
            else
                show_dialog_with_timeout "Please grant Accessibility permissions to the application $APP_PATH_2 in the Security & Privacy settings." "Accessibility"
            fi
        fi
    done
    
    # Check for Screen Recording permissions for ConnectWise
    while true; do
        has_screen_recording=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='$APP_BUNDLE_ID_2';")
        
        if [ "$has_screen_recording" == "2" ]; then
            echo "The app with bundle identifier $APP_BUNDLE_ID_2 has Screen Recording permissions. All permissions are set correctly."
            break
        else
            # Recheck permissions before showing the dialog
            echo "Rechecking ConnectWise Screen Recording permissions..."
            sleep 3
            has_screen_recording=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='$APP_BUNDLE_ID_2';")
            if [ "$has_screen_recording" == "2" ]; then
                echo "The app with bundle identifier $APP_BUNDLE_ID_2 has Screen Recording permissions. All permissions are set correctly."
                break
            else
                show_dialog_with_timeout "Please grant Screen Recording permissions to the application $APP_PATH_2 in the Security & Privacy settings." "ScreenCapture"
            fi
        fi
    done
}

# Function to force close System Events using killall
force_quit_system_events() {
    echo "Forcefully quitting System Events to close all lingering dialogs..."
    killall "System Events" 2>/dev/null
    sleep 5  # Wait for the process to terminate
}

# Function to restart the script
restart_script() {
    echo "Restarting the script from the beginning..."
    exec "$0" "$@"  # Restart the script from the beginning
}

# Function to handle dialogs with timeout
show_dialog_with_timeout() {
    local message="$1"
    local preference="$2"
    local dialog_title="Message from Enstep Technology Solutions"

    echo "Showing dialog: $message"

    # Start a loop to print the waiting message
    (
        i=1
        while [ $i -le 120 ]; do
            echo "Waiting for user interaction..."
            sleep 1
            i=$((i + 1))
        done
    ) &

    # Capture the background process ID so we can kill it if needed
    wait_pid=$!

    # Display an AppleScript dialog to the user with timeout handling
    osascript_result=$(osascript -e 'try
        with timeout of 120 seconds
            tell application "System Events"
                activate
                display dialog "'"$message"'" buttons {"OK"} default button "OK" with title "'"$dialog_title"'"
            end tell
        end timeout
    on error errMsg number errNum
        if errNum is equal to -1712 then
            return "timeout"
        else
            return "error"
        end if
    end try')

    # Kill the waiting message loop
    kill $wait_pid 2>/dev/null

    if [ "$osascript_result" == "timeout" ]; then
        echo "AppleEvent timed out. Handling timeout..."

        # Force quit System Events to close any lingering dialogs
        force_quit_system_events

        # Restart the entire script after timeout
        restart_script
    elif [ "$osascript_result" == "error" ]; then
        echo "An unexpected error occurred: $osascript_result"
    else
        echo "User clicked OK. Redirecting to the corresponding System Preferences pane..."
        open_preference_pane "$preference"
        sleep 30  # Wait for the user to act before rechecking permission status

        echo "Rechecking if permissions are granted..."
        if eval "check_$preference"; then
            echo "Permissions granted."
        else
            echo "Permissions not granted. Showing the dialog again..."
            show_dialog_with_timeout "$message" "$preference"
        fi
    fi
}

# Function to open the correct preference pane
open_preference_pane() {
    local preference="$1"
    echo "Opening $preference pane..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_$preference"
    sleep 30  # Increased delay to allow the preference pane to open and recheck permissions
}

# Permission check functions
check_AllFiles() {
    sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND (client='$BUNDLE_ID' OR client='$REAL_PATH');" | grep -q "2"
}

check_Accessibility() {
    sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='$APP_BUNDLE_ID_2';" | grep -q "2"
}

check_ScreenCapture() {
    sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='$APP_BUNDLE_ID_2';" | grep -q "2"
}

# Call "Main" Function
Main
