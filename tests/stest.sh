#!/bin/bash
# S3QL filesystem test script
# This script tests the core functionality of an S3QL filesystem

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# No color setup - using plain text output

echo "Starting S3QL filesystem test"

# Directory setup
TEST_DIR=$(mktemp -d)
MOUNT_POINT="${TEST_DIR}/s3ql_mount"
STORAGE_URL="local:///$TEST_DIR/fs"
CACHE_DIR="${TEST_DIR}/s3ql_cache"
AUTHFILE="${TEST_DIR}/authinfo2"
EXIT_CODE=0
MOUNTED=0

# Cleanup function to ensure resources are released
cleanup() {
    echo "Running cleanup..."
    
    # Check if filesystem is mounted and unmount if needed
    if [ $MOUNTED -eq 1 ]; then
        echo "Unmounting filesystem during cleanup..."
        umount.s3ql "$MOUNT_POINT" 2>/dev/null || true
    fi
    
    # Remove temporary files and directories
    rm -rf "$TEST_DIR" "$MOUNT_POINT" "$CACHE_DIR" "/tmp/checksums.md5" "$AUTHFILE"
    echo "Cleanup completed"
}

# Set trap to ensure cleanup runs on exit
trap cleanup EXIT INT TERM

# Create necessary directories
mkdir -p "$TEST_DIR" "$MOUNT_POINT" "$CACHE_DIR" "${STORAGE_URL#local:///}"

# Create test files function
create_test_files() {
    local mount_point=$1
    local num_files=${2:-100}
    local file_size=${3:-1M}
    
    echo "Creating $num_files test files (${file_size} each)..."
    
    # Create files with random content
    for i in $(seq 1 $num_files); do
        # Create file with random content
        dd if=/dev/urandom of="${mount_point}/file_${i}.bin" bs=${file_size} count=1 2>/dev/null
        
        # Create text file with known content
        echo "This is test file $i with known content" > "${mount_point}/text_${i}.txt"
        
        # Create file with special attributes
        echo "File with attributes $i" > "${mount_point}/attr_${i}.txt"
        setfattr -n user.test_attr -v "test_value_$i" "${mount_point}/attr_${i}.txt"
        
        # Create symlink
        if [ $i -eq 1 ]; then
            ln -sf "file_1.bin" "${mount_point}/symlink_to_file_1"
        fi
        
        # Create directory with files
        if [ $i -eq 1 ]; then
            mkdir -p "${mount_point}/test_dir_$i"
            echo "Nested file $i" > "${mount_point}/test_dir_$i/nested_file.txt"
        fi
    done
    
    # Create a hardlink
    ln "${mount_point}/file_1.bin" "${mount_point}/hardlink_to_file_1.bin"
    
    # Generate checksums for verification
    find "${mount_point}" -type f -name "*.bin" | sort | xargs md5sum > "/tmp/checksums.md5"
    echo "Test files created successfully"
}

# Check test files function
check_test_files() {
    local mount_point=$1
    local num_files=${2:-100}
    
    echo "Checking test files..."
    
    # Check file count
    local file_count=$(find "${mount_point}" -type f | wc -l)
    echo "Found $file_count files"
    
    # Verify binary files with checksums
    cd /
    if md5sum -c "/tmp/checksums.md5"; then
        echo "Binary file checksums verified"
    else
        echo "Binary file verification failed"
        return 1
    fi
    
    # Check text files content
    for i in $(seq 1 $num_files); do
        if ! grep -q "This is test file $i with known content" "${mount_point}/text_${i}.txt"; then
            echo "Content verification failed for text_${i}.txt"
            return 1
        fi
    done
    echo "Text file contents verified"
    
    # Check file attributes
    for i in $(seq 1 $num_files); do
        local attr_value=$(getfattr -n user.test_attr --only-values "${mount_point}/attr_${i}.txt" 2>/dev/null)
        if [ "$attr_value" != "test_value_$i" ]; then
            echo "Attribute verification failed for attr_${i}.txt"
            echo "Expected: test_value_$i, Got: $attr_value"
            return 1
        fi
    done
    echo "File attributes verified"
    
    # Check symlinks
    if [ ! -L "${mount_point}/symlink_to_file_1" ]; then
        echo "Symlink verification failed"
        return 1
    fi
    echo "Symlinks verified"
    
    # Check hardlinks
    local inode1=$(stat -c %i "${mount_point}/file_1.bin")
    local inode2=$(stat -c %i "${mount_point}/hardlink_to_file_1.bin")
    if [ "$inode1" != "$inode2" ]; then
        echo "Hardlink verification failed"
        return 1
    fi
    echo "Hardlinks verified"
    
    # Check nested directories and files
    if [ ! -f "${mount_point}/test_dir_1/nested_file.txt" ]; then
        echo "Nested file verification failed"
        return 1
    fi
    echo "Nested files verified"
    
    echo "All test files verified successfully"
    return 0
}

# Create authinfo file if it doesn't exist
if [ ! -f "$AUTHFILE" ]; then
    echo "[local]" > "$AUTHFILE"
    echo "storage-url: $STORAGE_URL" >> "$AUTHFILE"
    echo "fs-passphrase: test-passphrase" >> "$AUTHFILE"
    chmod 600 "$AUTHFILE"
fi

# Create the filesystem
echo "Creating S3QL filesystem..."
mkfs.s3ql --authfile "$AUTHFILE" --plain "$STORAGE_URL"

# Mount the filesystem
echo "Mounting S3QL filesystem..."
if mount.s3ql --authfile "$AUTHFILE" --cachedir "$CACHE_DIR" "$STORAGE_URL" "$MOUNT_POINT"; then
    MOUNTED=1
else
    echo "Failed to mount filesystem"
    exit 1
fi

# Create test files
NUM_FILES=50  # Adjust number of test files as needed
FILE_SIZE="512K"  # Adjust file size as needed
create_test_files "$MOUNT_POINT" $NUM_FILES $FILE_SIZE

# List the filesystem to verify
echo "Listing created files:"
find "$MOUNT_POINT" -type f | wc -l

# Display some filesystem statistics
echo "S3QL filesystem statistics:"
s3qlstat "$MOUNT_POINT"

# Unmount the filesystem
echo "Unmounting S3QL filesystem..."
if umount.s3ql "$MOUNT_POINT"; then
    MOUNTED=0
else
    echo "Failed to unmount filesystem"
    EXIT_CODE=1
fi

# Run fsck on the filesystem
echo "Running filesystem check (fsck.s3ql)..."
if ! fsck.s3ql --force --authfile "$AUTHFILE" "$STORAGE_URL"; then
    echo "Filesystem check failed"
    EXIT_CODE=1
fi

# Remount the filesystem
echo "Remounting S3QL filesystem..."
if mount.s3ql --authfile "$AUTHFILE" --cachedir "$CACHE_DIR" "$STORAGE_URL" "$MOUNT_POINT"; then
    MOUNTED=1
else
    echo "Failed to remount filesystem"
    EXIT_CODE=1
fi

# Check test files
if ! check_test_files "$MOUNT_POINT" $NUM_FILES; then
    echo "File verification failed"
    EXIT_CODE=1
fi

# Final unmount
echo "Final unmount of S3QL filesystem..."
if umount.s3ql "$MOUNT_POINT"; then
    MOUNTED=0
else
    echo "Failed to perform final unmount"
    EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "S3QL filesystem test completed successfully!"
else
    echo "S3QL filesystem test completed with errors"
fi

# The cleanup function will be called automatically due to the trap
exit $EXIT_CODE
