#!/bin/sh

#-------------------------------------------------------#
##WARNING: This was written before we had a file appimage: https://bin.pkgforge.dev/$(uname -m)/file
## Just use the AppImage instead
## This version was written a long time ago & is probably unreliable
## Replaces only basic file command functionality with support for common file types
## Minimal dependencies, maximum compatibility, but some grep/sed flags may not be compatible
#-------------------------------------------------------#

#-------------------------------------------------------#
#Read hex bytes from file
read_hex_bytes() {
    #Usage: read_hex_bytes <file> <offset> <count>
    [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return 1
    
    #Try dd first (most common)
    if command -v dd >/dev/null 2>&1; then
        if [ "$2" -eq 0 ]; then
            dd if="$1" bs=1 count="$3" 2>/dev/null | od -t x1 -A n 2>/dev/null | tr -d ' \n'
        else
            dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -t x1 -A n 2>/dev/null | tr -d ' \n'
        fi
    else
        #Fallback using od directly (less portable but sometimes available)
        if command -v od >/dev/null 2>&1; then
            od -t x1 -A n -N "$3" -j "$2" "$1" 2>/dev/null | tr -d ' \n'
        else
            #Last resort: hexdump if available
            if command -v hexdump >/dev/null 2>&1; then
                hexdump -s "$2" -n "$3" -v -e '/1 "%02x"' "$1" 2>/dev/null
            else
                return 1
            fi
        fi
    fi
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Check if file contains printable text
is_text_file() {
    [ -r "$1" ] || return 1
    
    #Use od to examine raw bytes, avoiding shell command substitution issues
    if command -v od >/dev/null 2>&1; then
        #Read first 512 bytes as hex values
        hex_data=$(od -t x1 -A n -N 512 "$1" 2>/dev/null | tr -d ' \n')
        
        #Count bytes
        total_bytes=$((${#hex_data} / 2))
        [ "$total_bytes" -eq 0 ] && return 0
        
        #Debug: ensure we have valid hex data
        case "$hex_data" in
            *[!0-9a-f]*) return 0 ;;  # Contains non-hex chars, assume text
        esac
        
        #Count null bytes and control characters
        null_count=0
        control_count=0
        printable_count=0
        
        #Process hex data in pairs
        i=1
        while [ "$i" -lt ${#hex_data} ]; do
            #Get hex pair using substr (POSIX compatible)
            end_pos=$((i + 1))
            if [ "$end_pos" -le ${#hex_data} ]; then
                hex_pair=$(printf '%s' "$hex_data" | cut -c$i-$end_pos)
                
                #Validate hex pair (should be exactly 2 hex characters)
                case "$hex_pair" in
                    [0-9a-f][0-9a-f]) ;;
                    *) i=$((i + 2)); continue ;;
                esac
            else
                break
            fi
            
            #Convert to decimal with better error handling
            byte_val=$(printf '%d' "0x$hex_pair" 2>/dev/null)
            if [ -n "$byte_val" ]; then
                #Check byte value
                if [ "$byte_val" -eq 0 ]; then
                    null_count=$((null_count + 1))
                elif [ "$byte_val" -lt 32 ] && [ "$byte_val" -ne 9 ] && [ "$byte_val" -ne 10 ] && [ "$byte_val" -ne 13 ]; then
                    #Control character (except tab, newline, carriage return)
                    control_count=$((control_count + 1))
                elif [ "$byte_val" -ge 32 ] && [ "$byte_val" -le 126 ]; then
                    #Printable ASCII
                    printable_count=$((printable_count + 1))
                elif [ "$byte_val" -eq 9 ] || [ "$byte_val" -eq 10 ] || [ "$byte_val" -eq 13 ]; then
                    #Whitespace characters
                    printable_count=$((printable_count + 1))
                fi
            fi
            
            i=$((i + 2))
        done
        
        #If more than 1% null bytes, likely binary (was 5%)
        if [ "$null_count" -gt 0 ] && [ $((null_count * 100 / total_bytes)) -gt 1 ]; then
            return 1
        fi
        
        #If more than 70% printable characters, consider it text (was 80%)
        [ "$printable_count" -gt 0 ] && [ $((printable_count * 100 / total_bytes)) -gt 70 ]
        
    else
        #Fallback method using hexdump if available
        if command -v hexdump >/dev/null 2>&1; then
            #Check for null bytes using hexdump
            null_check=$(hexdump -C -n 512 "$1" 2>/dev/null | grep -c "00" 2>/dev/null || echo "0")
            
            #If many null bytes found, likely binary
            [ "$null_check" -lt 5 ]
        else
            #Last resort: try to read with dd and check if it looks like text
            if command -v dd >/dev/null 2>&1; then
                #Use dd with different approach - read to file descriptor to avoid command substitution
                temp_file="/tmp/text_check_$$"
                dd if="$1" of="$temp_file" bs=1 count=100 2>/dev/null
                
                #Check if temp file has printable content
                if [ -f "$temp_file" ]; then
                    #Use grep to check for printable characters
                    if grep -qi '[[:print:]]' "$temp_file" 2>/dev/null; then
                        rm -f "$temp_file" 2>/dev/null
                        return 0
                    else
                        rm -f "$temp_file" 2>/dev/null
                        return 1
                    fi
                fi
                rm -f "$temp_file" 2>/dev/null
            fi
            
            #Ultimate fallback - assume it's text if we can't determine
            return 0
        fi
    fi
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Read basic elf properties
read_elf_value() {
    # Usage: read_elf_value <hex_string> <endianness> <size>
    # endianness: 1=little, 2=big
    # size: 2=16bit, 4=32bit, 8=64bit
    hex_str="$1"
    endian="$2"
    size="$3"
    
    case "$size" in
        2)
            if [ "$endian" = "1" ]; then
                #Little endian: reverse byte order
                printf '%s' "${hex_str#??}${hex_str%??}"
            else
                #Big endian: keep as is
                printf '%s' "$hex_str"
            fi
            ;;
        4)
            if [ "$endian" = "1" ]; then
                #Little endian: reverse byte order
                printf '%s' "${hex_str#??????}${hex_str%??????}" | cut -c5-8
                printf '%s' "${hex_str%????}" | cut -c5-8
                printf '%s' "${hex_str%??????}" | cut -c1-4
            else
                #Big endian: keep as is
                printf '%s' "$hex_str"
            fi
            ;;
        *)
            printf '%s' "$hex_str"
            ;;
    esac
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Read first line of file
read_first_line() {
    [ -r "$1" ] || return 1
    
    #Try different methods to read first line
    if command -v head >/dev/null 2>&1; then
        head -n1 "$1" 2>/dev/null
    elif command -v sed >/dev/null 2>&1; then
        sed -n '1p' "$1" 2>/dev/null
    else
        #Fallback using read
        exec 3< "$1"
        read -r line <&3
        exec 3<&-
        printf '%s\n' "$line"
    fi
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Search for patterns in file
search_pattern() {
    [ -r "$1" ] && [ -n "$2" ] || return 1
    
    if command -v grep >/dev/null 2>&1; then
        grep -qi "$2" "$1" 2>/dev/null
    else
        #Fallback using while loop
        while read -r line; do
            case "$line" in
                *"$2"*) return 0 ;;
            esac
        done < "$1"
        return 1
    fi
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Extract printable strings (fallback for strings command)
extract_strings() {
    [ -r "$1" ] || return 1
    
    if command -v strings >/dev/null 2>&1; then
        strings "$1" 2>/dev/null
    else
        #Fallback: extract sequences of printable characters
        if command -v tr >/dev/null 2>&1; then
            tr -cd '[:print:]\n' < "$1" 2>/dev/null | tr '\n' ' ' | 
            sed 's/[[:space:]]\+/\n/g' 2>/dev/null | 
            while read -r word; do
                [ ${#word} -ge 4 ] && printf '%s\n' "$word"
            done
        else
            #Very basic fallback
            cat "$1" 2>/dev/null | sed 's/[^[:print:]]/ /g' 2>/dev/null
        fi
    fi
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Convert hex string to decimal
hex_to_dec() {
    [ -n "$1" ] || return 1
    
    #Remove any leading 0x
    hex=$(printf '%s' "$1" | sed 's/^0x//')
    
    #Use printf if available (most portable)
    if printf '%d' "0x$hex" 2>/dev/null; then
        return 0
    fi
    
    #Fallback: manual conversion for small numbers
    case "$hex" in
        [0-9]) printf '%s' "$hex" ;;
        [aA]) printf '10' ;;
        [bB]) printf '11' ;;
        [cC]) printf '12' ;;
        [dD]) printf '13' ;;
        [eE]) printf '14' ;;
        [fF]) printf '15' ;;
        *) return 1 ;;
    esac
}
#hex_to_dec() {
#    local hex="$1"
#    local bytes="$2"
#    local endian="$3"
#    
#    if [ "$endian" = "01" ]; then
#        # Little endian: reverse byte order
#        local reversed=""
#        local i=$((${#hex} - 2))
#        while [ $i -ge 0 ]; do
#            reversed="${reversed}$(printf '%s' "$hex" | cut -c$((i+1))-$((i+2)))"
#            i=$((i - 2))
#        done
#        hex="$reversed"
#    fi
#    
#    printf '%d' "0x$hex" 2>/dev/null || echo "0"
#}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Check if ELF binary is stripped
is_elf_stripped() {
    file="$1"
    
    #Validate input
    if [ ! -f "$file" ]; then
        return 0  # assume stripped if file doesn't exist
    fi
    
    #Read ELF header (64 bytes)
    full_header=$(read_hex_bytes "$file" 0 64)
    if [ -z "$full_header" ] || [ ${#full_header} -lt 128 ]; then
        return 0  # assume stripped if we can't read header
    fi
    
    #Validate ELF magic number
    magic=$(printf '%s' "$full_header" | cut -c1-8)
    if [ "$magic" != "7f454c46" ]; then
        return 0  # not an ELF file
    fi
    
    class_byte=$(printf '%s' "$full_header" | cut -c9-10)
    endian_byte=$(printf '%s' "$full_header" | cut -c11-12)
    
    #Get section header information
    if [ "$class_byte" = "02" ]; then
        #64-bit ELF
        shoff_hex=$(printf '%s' "$full_header" | cut -c81-96)  # e_shoff at offset 40 (8 bytes)
        shentsize_hex=$(printf '%s' "$full_header" | cut -c119-122)  # e_shentsize at offset 58 (2 bytes)
        shnum_hex=$(printf '%s' "$full_header" | cut -c123-126)  # e_shnum at offset 60 (2 bytes)
        shstrndx_hex=$(printf '%s' "$full_header" | cut -c127-130)  # e_shstrndx at offset 62 (2 bytes)
    else
        #32-bit ELF
        shoff_hex=$(printf '%s' "$full_header" | cut -c65-72)   # e_shoff at offset 32 (4 bytes)
        shentsize_hex=$(printf '%s' "$full_header" | cut -c95-98)  # e_shentsize at offset 46 (2 bytes)
        shnum_hex=$(printf '%s' "$full_header" | cut -c99-102)  # e_shnum at offset 48 (2 bytes)
        shstrndx_hex=$(printf '%s' "$full_header" | cut -c103-106)  # e_shstrndx at offset 50 (2 bytes)
    fi
    
    #Convert to decimal with proper endianness handling
    shoff=$(hex_to_dec "$shoff_hex" 4 "$endian_byte")
    shentsize=$(hex_to_dec "$shentsize_hex" 2 "$endian_byte")
    shnum=$(hex_to_dec "$shnum_hex" 2 "$endian_byte")
    shstrndx=$(hex_to_dec "$shstrndx_hex" 2 "$endian_byte")
    
    #If no section headers, definitely stripped
    if [ "$shnum" -eq 0 ]; then
        return 0  # stripped
    fi
    
    #Validate section header parameters
    if [ "$shoff" -eq 0 ] || [ "$shentsize" -eq 0 ]; then
        return 0  # invalid section headers
    fi
    
    #Expected section header entry size
    expected_shentsize=40
    [ "$class_byte" = "02" ] && expected_shentsize=64
    
    if [ "$shentsize" -ne "$expected_shentsize" ]; then
        return 0  # unexpected section header size
    fi
    
    #Method 1: Look for symbol table sections by examining section headers
    has_symtab=0
    has_debug_sections=0
    i=0
    
    while [ "$i" -lt "$shnum" ] && [ "$i" -lt 100 ]; do
        section_offset=$((shoff + i * shentsize))
        section_header=$(read_hex_bytes "$file" "$section_offset" "$shentsize")
        
        if [ -n "$section_header" ] && [ ${#section_header} -ge $((shentsize * 2)) ]; then
            #Get section type (sh_type) - 4 bytes at offset 4
            sh_type_hex=$(printf '%s' "$section_header" | cut -c9-16)
            sh_type=$(hex_to_dec "$sh_type_hex" 4 "$endian_byte")
            
            #Check section types
            case "$sh_type" in
                2)  # SHT_SYMTAB - symbol table
                    has_symtab=1
                    ;;
                17) # SHT_GNU_verdef - version definition
                    has_debug_sections=1
                    ;;
                18) # SHT_GNU_verneed - version needs
                    has_debug_sections=1
                    ;;
            esac
            
            #Check
            if [ "$has_debug_sections" -eq 1 ]; then
                break
            fi

            #Also check for debug section names if we have string table access
            if [ "$has_symtab" -eq 1 ]; then
                break  # Found symbol table, definitely not stripped
            fi
        fi
        
        i=$((i + 1))
    done
    
    #If we found a symbol table, it's not stripped
    if [ "$has_symtab" -eq 1 ]; then
        return 1  # not stripped
    fi
    
    #Method 2: Check section names for debug sections
    #This requires reading the section header string table
    if [ "$shstrndx" -gt 0 ] && [ "$shstrndx" -lt "$shnum" ]; then
        strtab_offset=$((shoff + shstrndx * shentsize))
        strtab_header=$(read_hex_bytes "$file" "$strtab_offset" "$shentsize")
        
        if [ -n "$strtab_header" ] && [ ${#strtab_header} -ge $((shentsize * 2)) ]; then
            #Get string table section offset and size
            if [ "$class_byte" = "02" ]; then
                # 64-bit: sh_offset at offset 24, sh_size at offset 32
                strtab_sh_offset_hex=$(printf '%s' "$strtab_header" | cut -c49-64)
                strtab_sh_size_hex=$(printf '%s' "$strtab_header" | cut -c65-80)
            else
                # 32-bit: sh_offset at offset 16, sh_size at offset 20
                strtab_sh_offset_hex=$(printf '%s' "$strtab_header" | cut -c33-40)
                strtab_sh_size_hex=$(printf '%s' "$strtab_header" | cut -c41-48)
            fi
            
            strtab_sh_offset=$(hex_to_dec "$strtab_sh_offset_hex" 4 "$endian_byte")
            strtab_sh_size=$(hex_to_dec "$strtab_sh_size_hex" 4 "$endian_byte")
            
            #Read section names and look for debug sections
            if [ "$strtab_sh_offset" -gt 0 ] && [ "$strtab_sh_size" -gt 0 ] && [ "$strtab_sh_size" -lt 100000 ]; then
                # Read section name strings (limit size for safety)
                max_strtab_size=10000
                [ "$strtab_sh_size" -lt "$max_strtab_size" ] && max_strtab_size="$strtab_sh_size"
                
                strtab_data=$(read_hex_bytes "$file" "$strtab_sh_offset" "$max_strtab_size")
                
                if [ -n "$strtab_data" ]; then
                    #Convert hex to ASCII and look for debug section names
                    strtab_ascii=""
                    j=0
                    while [ $j -lt ${#strtab_data} ]; do
                        hex_char=$(printf '%s' "$strtab_data" | cut -c$((j+1))-$((j+2)))
                        octal_value=$(printf '%o' "0x$hex_char" 2>/dev/null)
                        ascii_char=$(printf "\\%s" "$octal_value" 2>/dev/null || echo "")
                        strtab_ascii="${strtab_ascii}${ascii_char}"
                        j=$((j + 2))
                    done
                    
                    #Check for debug section names
                    if printf '%s' "$strtab_ascii" | grep -q "\.debug_\|\.symtab\|\.strtab"; then
                        return 1  # not stripped (has debug sections)
                    fi
                fi
            fi
        fi
    fi
    
    #Method 3: Heuristic based on section count
    #Stripped binaries typically have very few sections (usually < 10)
    #Non-stripped binaries usually have more sections
    if [ "$shnum" -gt 20 ]; then
        return 1  # likely not stripped (many sections)
    fi
    
    #Method 4: Look for debug information in strings
    #This is less reliable but can catch some cases
    if extract_strings "$file" | grep -q "\.debug_info\|\.debug_line\|\.debug_str\|\.debug_abbrev" 2>/dev/null; then
        return 1  # not stripped (has debug info references)
    fi
    
    #Method 5: Check for source file paths (indicates debug info)
    if extract_strings "$file" | grep -E "\.(c|cpp|cc|cxx|rs|go|java):|/[^/]*\.(c|cpp|cc|cxx|rs|go|java)$" >/dev/null 2>&1; then
        return 1  # not stripped (has source file debug info)
    fi
    
    #Default: assume stripped if we couldn't definitively determine otherwise
    return 0
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Main
file() {
    [ -n "$1" ] || { printf 'Usage: file <filename>...\n' >&2; return 1; }
    
    #Check if file exists and is readable
    if [ ! -e "$1" ]; then
        printf '%s: cannot open (No such file or directory)\n' "$1" >&2
        return 1
    fi
    
    if [ ! -r "$1" ]; then
        printf '%s: cannot open (Permission denied)\n' "$1" >&2
        return 1
    fi
    
    #Check if it's a directory
    if [ -d "$1" ]; then
        printf '%s: directory\n' "$1"
        return 0
    fi
    
    #Check if it's a regular file
    if [ ! -f "$1" ]; then
        printf '%s: special file\n' "$1"
        return 0
    fi
    
    #Check if file is empty
    if [ ! -s "$1" ]; then
        printf '%s: empty\n' "$1"
        return 0
    fi
    
    #Read first 32 bytes to analyze file header
    header=$(read_hex_bytes "$1" 0 32)
    #If we couldn't read header, fall back to basic checks
    if [ -z "$header" ]; then
        if is_text_file "$1"; then
            printf '%s: ASCII text\n' "$1"
        else
            printf '%s: data\n' "$1"
        fi
        return 0
    fi
    
    #Check file signatures
    case "$header" in
        #PNG: 89 50 4E 47 0D 0A 1A 0A
        89504e470d0a1a0a*)
            printf '%s: PNG image data' "$1"
            #Try to extract dimensions from IHDR chunk
            if [ ${#header} -ge 48 ]; then
                width_hex=$(printf '%s' "$header" | cut -c33-40)
                height_hex=$(printf '%s' "$header" | cut -c41-48)
                if [ -n "$width_hex" ] && [ -n "$height_hex" ]; then
                    width=$(hex_to_dec "$width_hex")
                    height=$(hex_to_dec "$height_hex")
                    [ -n "$width" ] && [ -n "$height" ] && printf ', %dx%d' "$width" "$height"
                fi
            fi
            printf '\n'
            ;;
        
        #JPEG: FF D8 FF
        ffd8ff*)
            printf '%s: JPEG image data' "$1"
            #Try to determine JPEG variant
            if [ ${#header} -ge 8 ]; then
                fourth_byte=$(printf '%s' "$header" | cut -c7-8)
                case "$fourth_byte" in
                    e0) printf ', JFIF standard' ;;
                    e1) printf ', EXIF standard' ;;
                    e2) printf ', EXIF extended' ;;
                    e8) printf ', SPIFF' ;;
                    db) printf ', Samsung' ;;
                    dd) printf ', Kodak' ;;
                esac
            fi
            printf '\n'
            ;;
        
        #GIF: 47 49 46 38 (GIF8)
        47494638*)
            printf '%s: GIF image data' "$1"
            if [ ${#header} -ge 12 ]; then
                version=$(printf '%s' "$header" | cut -c9-12)
                case "$version" in
                    3761) printf ', version 87a' ;;
                    3961) printf ', version 89a' ;;
                esac
            fi
            printf '\n'
            ;;
        
        #ELF: 7F 45 4C 46
        7f454c46*)
            printf '%s: ELF' "$1"
            
            #Extract ELF class (32/64-bit) from 5th byte
            class_byte=""
            endian_val=""
            if [ ${#header} -ge 10 ]; then
                class_byte=$(printf '%s' "$header" | cut -c9-10)
                case "$class_byte" in
                    01) printf ' 32-bit' ;;
                    02) printf ' 64-bit' ;;
                esac
            fi
            
            #Extract endianness from 6th byte
            if [ ${#header} -ge 12 ]; then
                endian_byte=$(printf '%s' "$header" | cut -c11-12)
                case "$endian_byte" in
                    01) 
                        endian="LSB"
                        endian_val="1"
                        ;;
                    02) 
                        endian="MSB"
                        endian_val="2"
                        ;;
                    *) 
                        endian="unknown"
                        endian_val="1"
                        ;;
                esac
                printf ' %s' "$endian"
            fi
            
            #Extract version from 7th byte
            if [ ${#header} -ge 14 ]; then
                version_byte=$(printf '%s' "$header" | cut -c13-14)
                case "$version_byte" in
                    01) version="1" ;;
                    *) version="unknown" ;;
                esac
            fi
            
            #Extract OS/ABI from 8th byte
            if [ ${#header} -ge 16 ]; then
                osabi_byte=$(printf '%s' "$header" | cut -c15-16)
                case "$osabi_byte" in
                    00) osabi="SYSV" ;;
                    01) osabi="HP-UX" ;;
                    02) osabi="NetBSD" ;;
                    03) osabi="Linux" ;;
                    06) osabi="Solaris" ;;
                    07) osabi="AIX" ;;
                    08) osabi="IRIX" ;;
                    09) osabi="FreeBSD" ;;
                    0a) osabi="OpenBSD" ;;
                    *) osabi="unknown" ;;
                esac
            fi
            
            #Read e_type field (bytes 16-17 for 32-bit, same for 64-bit)
            if [ ${#header} -ge 36 ]; then
                type_bytes=$(printf '%s' "$header" | cut -c33-36)
                #Handle endianness for 16-bit value
                if [ "$endian_val" = "1" ]; then
                    #Little endian: swap bytes
                    type_hex="${type_bytes#??}${type_bytes%??}"
                else
                    #Big endian: keep as is
                    type_hex="$type_bytes"
                fi
                
                case "$type_hex" in
                    0001) elf_type="relocatable" ;;
                    0002) elf_type="executable" ;;
                    0003) 
                        #Need to distinguish between shared library and PIE executable
                        #Check if it has an interpreter section
                        if extract_strings "$1" | grep -qi "^/lib.*ld\|^ld-linux\|^ld\.so" 2>/dev/null; then
                            elf_type="pie executable"
                        else
                            elf_type="shared object"
                        fi
                        ;;
                    0004) elf_type="core" ;;
                    *) elf_type="executable" ;;
                esac

                if [ "$elf_type" = "shared object" ]; then
                   #Check for entry point (PIE executables have entry points, shared libs typically don't)
                   if extract_strings "$1" 2>/dev/null | grep -q "_start\|main" || 
                      dd if="$1" bs=1 skip=24 count=8 2>/dev/null | od -t x1 -A n | grep -q -v "00 00 00 00 00 00 00 00"; then
                       elf_type="pie executable"
                   fi
                fi
                printf ' %s' "$elf_type"
            fi
            
            #Extract machine type from e_machine field (bytes 18-19)
            if [ ${#header} -ge 40 ]; then
                machine_bytes=$(printf '%s' "$header" | cut -c37-40)
                #Handle endianness for 16-bit value
                if [ "$endian_val" = "1" ]; then
                    #Little endian: swap bytes
                    machine_hex="${machine_bytes#??}${machine_bytes%??}"
                else
                    #Big endian: keep as is
                    machine_hex="$machine_bytes"
                fi
                
                case "$machine_hex" in
                     0002) printf ', SPARC' ;;
                     0003) printf ', Intel i386' ;;
                     0006) printf ', Intel i486' ;;
                     0007) printf ', Intel i860' ;;
                     0008) printf ', MIPS' ;;
                     000a) printf ', MIPS-I' ;;
                     000b) printf ', IBM RS6000' ;;
                     0014) printf ', PowerPC or cisco 4500' ;;
                     0015) printf ', 64-bit PowerPC or cisco 7500' ;;
                     0016) printf ', IBM S/390' ;;
                     0028) printf ', ARM' ;;
                     002a) printf ', SuperH' ;;
                     002b) printf ', IA-64' ;;
                     003e) printf ', x86-64' ;;
                     0040) printf ', ARM' ;;
                     0042) printf ', SuperH' ;;
                     0047) printf ', Motorola 68000' ;;
                     004c) printf ', Motorola m68k' ;;
                     0050) printf ', IA-64' ;;
                     005c) printf ', OpenRISC' ;;
                     0083) printf ', AVR' ;;
                     008c) printf ', TI TMS320C6000' ;;
                     00aa) printf ', ARM' ;;
                     00b7) printf ', ARM aarch64' ;;
                     00bd) printf ', Xilinx MicroBlaze 32-bit RISC' ;;
                     00f3) printf ', UCB RISC-V' ;;
                     00f7) printf ', Berkeley Packet Filter' ;;
                     0101) printf ', WDC 65C816' ;;
                     0243) printf ', UCB RISC-V' ;;
                     5441) printf ', Fujitsu FR-V' ;;
                     9026) printf ', Alpha' ;;
                     9080) printf ', Motorola m68k' ;;
                     a390) printf ', IBM S/390' ;;
                     baab) printf ', Xilinx MicroBlaze 32-bit RISC' ;;
                     beef) printf ', Matsushita MN10300' ;;
                     dead) printf ', Matsushita MN10200' ;;
                     *)    printf ', unknown arch' ;;
                esac
            fi
            
            #Add version info if available
            if [ -n "$version" ] && [ -n "$osabi" ]; then
                printf ', version %s (%s)' "$version" "$osabi"
            fi
            
            #Check for dynamic linking and interpreter (This is not always 100% Accurate)
            interpreter=""
            if extract_strings "$1" | grep -qi "^/lib.*ld\|^ld-linux\|^ld\.so" 2>/dev/null; then
                printf ', dynamically linked'
                #Try to find the interpreter
                interpreter=$(extract_strings "$1" | grep "^/lib.*ld\|^ld-linux\|^ld\.so" | head -1 2>/dev/null)
                if [ -n "$interpreter" ]; then
                    printf ', interpreter %s' "$interpreter"
                fi
            else
                if [ "$elf_type" = "pie executable" ]; then
                    printf ', static-pie linked'
                else
                    printf ', statically linked'
                fi
            fi
            
            #Check if binary is stripped
            if is_elf_stripped "$1"; then
                printf ', stripped'
            else
                printf ', not stripped'
            fi
            
            #Try to extract BuildID if strings command is available
            if command -v strings >/dev/null 2>&1; then
                #Look for GNU Build ID in strings output
                buildid=$(strings "$1" 2>/dev/null | grep -o "BuildID\[sha1\]=[a-f0-9]\{40\}" | head -1 2>/dev/null)
                if [ -n "$buildid" ]; then
                    printf ', %s' "$buildid"
                fi
            fi
            
            #Check for GNU/Linux specific info
            if [ "$osabi" = "SYSV" ] && [ -n "$interpreter" ]; then
                case "$interpreter" in
                    */ld-linux*) printf ', for GNU/Linux' ;;
                esac
            fi
            
            printf '\n'
            ;;
        
        #ZIP/JAR/APK: 50 4B 03 04 or 50 4B 05 06 or 50 4B 07 08
        504b0304*|504b0506*|504b0708*)
            printf '%s: Zip archive data' "$1"
            #Check for specific ZIP variants
            if extract_strings "$1" | grep -qi "META-INF/MANIFEST.MF" 2>/dev/null; then
                printf ', Java archive'
            elif extract_strings "$1" | grep -qi "AndroidManifest.xml" 2>/dev/null; then
                printf ', Android package'
            fi
            printf '\n'
            ;;
        
        #GZIP: 1F 8B
        1f8b*)
            printf '%s: gzip compressed data\n' "$1" ;;
        
        #BZIP2: 42 5A 68
        425a68*)
            printf '%s: bzip2 compressed data\n' "$1" ;;
        
        #XZ: FD 37 7A 58 5A 00
        fd377a58*)
            printf '%s: XZ compressed data\n' "$1" ;;
        
        #PDF: 25 50 44 46
        25504446*)
            printf '%s: PDF document\n' "$1" ;;
        
        #Mach-O: CA FE BA BE or FE ED FA CE or FE ED FA CF
        cafebabe*|feedface*|feedfacf*)
            printf '%s: Mach-O executable\n' "$1" ;;
        
        #MS-DOS/Windows executable: 4D 5A
        4d5a*)
            printf '%s: MS-DOS executable\n' "$1" ;;
        
        #RAR: 52 61 72 21
        52617221*)
            printf '%s: RAR archive data\n' "$1" ;;
        
        #7-Zip: 37 7A BC AF
        377abcaf*)
            printf '%s: 7-zip archive data\n' "$1" ;;
        
        #TAR files often start with filename, check for tar magic at offset 257
        *)
            #Check for TAR archive (magic at offset 257: "ustar")
            tar_magic=$(read_hex_bytes "$1" 257 6)
            if [ "$tar_magic" = "757374617200" ] || [ "$tar_magic" = "7573746172" ]; then
                printf '%s: POSIX tar archive\n' "$1"
                return 0
            fi
            
            #Check if it's a text file
            if is_text_file "$1"; then
                first_line=$(read_first_line "$1")
                
                case "$first_line" in
                    #XML Declaration
                    '<?xml '*)
                        printf '%s: XML document' "$1"
                        #Check for specific XML types
                        if search_pattern "$1" '<svg'; then
                            printf ', SVG Scalable Vector Graphics image'
                        elif search_pattern "$1" '<html\|<HTML'; then
                            printf ', HTML document'
                        elif search_pattern "$1" '<rss\|<feed'; then
                            printf ', RSS/Atom feed'
                        elif search_pattern "$1" '<plist'; then
                            printf ', Apple property list'
                        fi
                        printf ', ASCII text\n'
                        ;;
                    
                    #SVG without XML declaration
                    '<svg'*)
                        printf '%s: SVG Scalable Vector Graphics image, ASCII text\n' "$1"
                        ;;
                    
                    #HTML without XML declaration
                    '<!DOCTYPE html'*|'<!doctype html'*|'<html'*|'<HTML'*)
                        printf '%s: HTML document, ASCII text\n' "$1"
                        ;;
                    
                    #Script shebangs
                    '#!/bin/sh'*|'#!/usr/bin/sh'*|'#!/usr/bin/env sh'*|'#!/bin/dash'*|'#!/usr/bin/dash'*|'#!/usr/bin/env dash'*|'#!/bin/ash'*|'#!/usr/bin/ash'*|'#!/usr/bin/env ash'*)
                        printf '%s: POSIX shell script, ASCII text executable\n' "$1" ;;
                    '#!/bin/bash'*|'#!/usr/bin/bash'*|'#!/usr/bin/env bash'*|'#!/usr/local/bin/bash'*)
                        printf '%s: Bourne-Again shell script, ASCII text executable\n' "$1" ;;
                    '#!/bin/zsh'*|'#!/usr/bin/zsh'*|'#!/usr/bin/env zsh'*|'#!/usr/local/bin/zsh'*)
                        printf '%s: Paul Falstads zsh script, ASCII text executable\n' "$1" ;;
                    '#!/bin/csh'*|'#!/usr/bin/csh'*|'#!/usr/bin/env csh'*|'#!/bin/tcsh'*|'#!/usr/bin/tcsh'*|'#!/usr/bin/env tcsh'*)
                        printf '%s: C shell script, ASCII text executable\n' "$1" ;;
                    '#!/bin/ksh'*|'#!/usr/bin/ksh'*|'#!/usr/bin/env ksh'*)
                        printf '%s: Korn shell script, ASCII text executable\n' "$1" ;;
                    '#!/usr/bin/env python'*|'#!/usr/bin/python'*|'#!/usr/local/bin/python'*|'#!/opt/*/python'*)
                        printf '%s: Python script\n' "$1" ;;
                    '#!/usr/bin/env perl'*|'#!/usr/bin/perl'*|'#!/usr/local/bin/perl'*)
                        printf '%s: Perl script text executable\n' "$1" ;;
                    '#!/usr/bin/env ruby'*|'#!/usr/bin/ruby'*|'#!/usr/local/bin/ruby'*)
                        printf '%s: Ruby script\n' "$1" ;;
                    '#!/usr/bin/env node'*|'#!/usr/bin/node'*|'#!/usr/local/bin/node'*)
                        printf '%s: Node.js script\n' "$1" ;;
                    '#!/usr/bin/env php'*|'#!/usr/bin/php'*|'#!/usr/local/bin/php'*)
                        printf '%s: PHP script\n' "$1" ;;
                    '#!/usr/bin/env lua'*|'#!/usr/bin/lua'*|'#!/usr/local/bin/lua'*)
                        printf '%s: Lua script\n' "$1" ;;
                    '#!/usr/bin/env awk'*|'#!/usr/bin/awk'*|'#!/usr/bin/gawk'*|'#!/usr/bin/env gawk'*)
                        printf '%s: AWK script\n' "$1" ;;
                    '#!'*)
                        printf '%s: script\n' "$1" ;;
                    
                    *)
                        #Check for other text-based formats
                        if search_pattern "$1" '^<svg'; then
                            printf '%s: SVG Scalable Vector Graphics image, ASCII text\n' "$1"
                        elif search_pattern "$1" '^<!DOCTYPE html\|^<html\|^<HTML\|^<div\|^<span\|^<p\|^<h[1-6]\|^<body\|^<head\|^<title\|^<meta\|^<link\|^<script\|^<style'; then
                            printf '%s: HTML document, ASCII text\n' "$1"
                        elif search_pattern "$1" '^<\?xml\|^<[a-zA-Z]'; then
                            printf '%s: XML document, ASCII text\n' "$1"
                        elif search_pattern "$1" '^\s*{\s*$' && search_pattern "$1" '}\s*$'; then
                            printf '%s: JSON text data\n' "$1"
                        elif search_pattern "$1" '^---$\|^---\s'; then
                            printf '%s: YAML document\n' "$1"
                        elif search_pattern "$1" '^\[.*\]$'; then
                            printf '%s: configuration file\n' "$1"
                        else
                            printf '%s: ASCII text\n' "$1"
                        fi
                        ;;
                esac
            else
                printf '%s: data\n' "$1"
            fi
            ;;
    esac
}
#-------------------------------------------------------#

#-------------------------------------------------------#
#Call main func
if [ "$#" -gt 0 ]; then
    for f in "$@"; do
        file "$f"
    done
else
    printf 'Usage: file <filename>...\n' >&2
    exit 1
fi
#-------------------------------------------------------#