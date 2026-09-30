#!/usr/bin/env python3
"""Create a D64 disk image with the demo"""

# D64 format: 35 tracks, 683 blocks (174848 bytes)
# Track 18 is directory and BAM

import sys

# usage: make_d64.py [in.prg] [out.d64] [FILENAME]
PRG = sys.argv[1] if len(sys.argv) > 1 else 'demo.prg'
D64 = sys.argv[2] if len(sys.argv) > 2 else 'demo.d64'
NAME = sys.argv[3] if len(sys.argv) > 3 else 'DEMO'

D64_SIZE = 174848
TRACK_SECTORS = [
    0,  # track 0 doesn't exist
    21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,  # 1-17
    19,  # 18 (directory track)
    19, 19, 19, 19, 19, 19,  # 19-24
    18, 18, 18, 18, 18, 18,  # 25-30
    17, 17, 17, 17, 17       # 31-35
]

def track_offset(track):
    """Get byte offset for start of track"""
    offset = 0
    for t in range(1, track):
        offset += TRACK_SECTORS[t] * 256
    return offset

def sector_offset(track, sector):
    """Get byte offset for a specific sector"""
    return track_offset(track) + sector * 256

# Create empty disk
disk = bytearray(D64_SIZE)

# Initialize BAM (Block Availability Map) at track 18, sector 0
bam_offset = sector_offset(18, 0)
disk[bam_offset + 0] = 18  # Directory track
disk[bam_offset + 1] = 1   # Directory sector
disk[bam_offset + 2] = 0x41  # DOS version (A)

# BAM entries - mark all sectors free initially
for track in range(1, 36):
    sectors = TRACK_SECTORS[track]
    bam_idx = bam_offset + 4 + (track - 1) * 4
    disk[bam_idx] = sectors  # Number of free sectors
    # Bitmap of free sectors
    if sectors >= 8:
        disk[bam_idx + 1] = 0xFF
    else:
        disk[bam_idx + 1] = (1 << sectors) - 1
    if sectors >= 16:
        disk[bam_idx + 2] = 0xFF
    else:
        disk[bam_idx + 2] = max(0, (1 << (sectors - 8)) - 1) if sectors > 8 else 0
    if sectors >= 24:
        disk[bam_idx + 3] = 0xFF
    else:
        disk[bam_idx + 3] = max(0, (1 << (sectors - 16)) - 1) if sectors > 16 else 0

# Disk name at BAM + $90 (padded with $A0)
disk_name = (NAME + " DISK").encode("ascii")[:16]
for i in range(16):
    disk[bam_offset + 0x90 + i] = disk_name[i] if i < len(disk_name) else 0xA0

# Disk ID at BAM + $A2
disk[bam_offset + 0xA2] = ord('0')
disk[bam_offset + 0xA3] = ord('1')
disk[bam_offset + 0xA4] = 0xA0
disk[bam_offset + 0xA5] = ord('2')
disk[bam_offset + 0xA6] = ord('A')

# Mark track 18 sector 0 and 1 as used in BAM
bam_track18 = bam_offset + 4 + 17 * 4
disk[bam_track18] = TRACK_SECTORS[18] - 2  # 2 sectors used
disk[bam_track18 + 1] = 0xFF ^ 0x03  # Sectors 0,1 used

# Directory at track 18, sector 1
dir_offset = sector_offset(18, 1)
disk[dir_offset + 0] = 0   # Next track (0 = none)
disk[dir_offset + 1] = 0xFF  # Next sector

# First directory entry
entry = dir_offset + 2
disk[entry + 0] = 0x82  # PRG file type
disk[entry + 1] = 1     # File start track
disk[entry + 2] = 0     # File start sector

# Filename "DEMO" (padded with $A0)
filename = NAME.encode("ascii")[:16]
for i in range(16):
    disk[entry + 3 + i] = filename[i] if i < len(filename) else 0xA0

# Read our PRG file
with open(PRG, 'rb') as f:
    prg_data = f.read()

# Calculate blocks needed
prg_size = len(prg_data)
blocks = (prg_size + 253) // 254  # 254 bytes per sector (2 for chain)

disk[entry + 0x1C] = blocks & 0xFF  # File size low
disk[entry + 0x1D] = (blocks >> 8) & 0xFF  # File size high

# Write file data starting at track 1, sector 0
current_track = 1
current_sector = 0
data_pos = 0

for block in range(blocks):
    offset = sector_offset(current_track, current_sector)

    # Mark sector as used in BAM
    bam_track = bam_offset + 4 + (current_track - 1) * 4
    disk[bam_track] -= 1
    byte_idx = current_sector // 8
    bit_idx = current_sector % 8
    disk[bam_track + 1 + byte_idx] &= ~(1 << bit_idx)

    # Calculate next sector
    next_sector = current_sector + 1
    next_track = current_track
    if next_sector >= TRACK_SECTORS[current_track]:
        next_sector = 0
        next_track += 1
        if next_track == 18:  # Skip directory track
            next_track = 19

    if block < blocks - 1:
        disk[offset + 0] = next_track
        disk[offset + 1] = next_sector
        chunk = prg_data[data_pos:data_pos + 254]
        disk[offset + 2:offset + 2 + len(chunk)] = chunk
        data_pos += 254
    else:
        # Last block
        remaining = prg_size - data_pos
        disk[offset + 0] = 0
        disk[offset + 1] = remaining + 1  # Pointer to last byte
        chunk = prg_data[data_pos:]
        disk[offset + 2:offset + 2 + len(chunk)] = chunk

    current_track = next_track
    current_sector = next_sector

with open(D64, 'wb') as f:
    f.write(disk)

print(f"Created {D64} (D64 disk image)")
print(f"Contains: {NAME} ({blocks} blocks)")
print("\nIn VirtualC64:")
print(f'1. Drag {D64} onto window')
print('2. Type: LOAD"*",8,1 and press Enter')
print('3. Type: RUN and press Enter')
