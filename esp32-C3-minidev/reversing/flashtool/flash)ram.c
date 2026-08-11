// Compileer met: gcc -nostdlib -ffreestanding -O2 -o esp_loadram esp_loadram.c

// --- Linux Syscall Nummers (x86_64) ---
#define SYS_read     0
#define SYS_write    1
#define SYS_open     2
#define SYS_close    3
#define SYS_ioctl   16
#define SYS_exit    60

// --- Bestandsflags en Termios constanten ---
#define O_RDONLY     0
#define O_RDWR       2
#define O_NOCTTY   256
#define TCGETS     0x5401
#define TCSETS     0x5402
#define B115200    0010007
#define TIOCM_DTR  0002
#define TIOCM_RTS  0004
#define TIOCMBIS   0x5416
#define TIOCMBIC   0x5417

struct termios {
    unsigned int c_iflag, c_oflag, c_cflag, c_lflag;
    unsigned char c_cc[19];
    unsigned int c_ispeed, c_ospeed;
};

// --- Inline Syscall Wrappers ---
static long sys_open(const char *filename, int flags, int mode) {
    long ret;
    __asm__ volatile("syscall" : "=a" (ret) : "0" (SYS_open), "di" ((unsigned long)filename), "si" (flags), "rdx" (mode) : "rcx", "r11", "memory");
    return ret;
}

static long sys_read(int fd, void *buf, unsigned long count) {
    long ret;
    __asm__ volatile("syscall" : "=a" (ret) : "0" (SYS_read), "di" (fd), "si" ((unsigned long)buf), "rdx" (count) : "rcx", "r11", "memory");
    return ret;
}

static long sys_write(int fd, const void *buf, unsigned long count) {
    long ret;
    __asm__ volatile("syscall" : "=a" (ret) : "0" (SYS_write), "di" (fd), "si" ((unsigned long)buf), "rdx" (count) : "rcx", "r11", "memory");
    return ret;
}

static long sys_close(int fd) {
    long ret;
    __asm__ volatile("syscall" : "=a" (ret) : "0" (SYS_close), "di" (fd) : "rcx", "r11", "memory");
    return ret;
}

static long sys_ioctl(int fd, unsigned long request, unsigned long arg) {
    long ret;
    __asm__ volatile("syscall" : "=a" (ret) : "0" (SYS_ioctl), "di" (fd), "si" (request), "rdx" (arg) : "rcx", "r11", "memory");
    return ret;
}

static void sys_exit(int error_code) {
    __asm__ volatile("syscall" : : "a" (SYS_exit), "di" (error_code));
    while(1);
}

static void print_str(const char *s) {
    int len = 0;
    while (s[len]) len++;
    sys_write(1, s, len);
}

// --- SLIP Framing & Packet Transmissie ---
static void send_slip_packet(int fd, const unsigned char *payload, int len) {
    unsigned char marker = 0xC0;
    sys_write(fd, &marker, 1);

    for (int i = 0; i < len; i++) {
        unsigned char b = payload[i];
        if (b == 0xC0) {
            unsigned char esc[2] = {0xDB, 0xDC};
            sys_write(fd, esc, 2);
        } else if (b == 0xDB) {
            unsigned char esc[2] = {0xDB, 0xDD};
            sys_write(fd, esc, 2);
        } else {
            sys_write(fd, &b, 1);
        }
    }
    sys_write(fd, &marker, 1);
}

// Leest één compleet SLIP-pakket van de seriële poort
static int read_slip_packet(int fd, unsigned char *buf, int max_len) {
    int idx = 0;
    unsigned char c;
    int started = 0;

    while (1) {
        long n = sys_read(fd, &c, 1);
        if (n <= 0) continue;

        if (c == 0xC0) {
            if (started && idx > 0) break; // Einde pakket
            started = 1; // Start pakket
            idx = 0;
            continue;
        }
        if (started && idx < max_len) {
            buf[idx++] = c;
        }
    }
    return idx;
}

// Eenvoudige checksum-berekening voor ESP32 bootloader (XOR-checksum)
static unsigned int calculate_checksum(const unsigned char *data, int len) {
    unsigned int cksum = 0xEF; // Init-waarde voor ESP bootloader
    for (int i = 0; i < len; i++) {
        cksum ^= data[i];
    }
    return cksum;
}

void _start(void) {
    // 1. Open minimal.bin om te flashen
    long bin_fd = sys_open("minimal.bin", O_RDONLY, 0);
    if (bin_fd < 0) {
        print_str("Fout: Kan minimal.bin niet openen.\n");
        sys_exit(1);
    }

    // Lees de binaire inhoud in een buffer (ervaring leert dat minimal.bin klein is, bijv. < 4096 bytes)
    unsigned char bin_buffer[4096];
    long bin_len = sys_read(bin_fd, bin_buffer, sizeof(bin_buffer));
    sys_close(bin_fd);

    if (bin_len <= 0) {
        print_str("Fout: minimal.bin is leeg of kon niet gelezen worden.\n");
        sys_exit(1);
    }

    // 2. Open /dev/ttyACM0
    long fd = sys_open("/dev/ttyACM0", O_RDWR | O_NOCTTY, 0);
    if (fd < 0) {
        print_str("Fout: Kan /dev/ttyACM0 niet openen.\n");
        sys_exit(1);
    }

    // 3. Configureer seriële poort (115200 baud, 8N1)
    struct termios tio;
    sys_ioctl(fd, TCGETS, (unsigned long)&tio);
    tio.c_cflag = B115200 | 0000060 /* CS8 */ | 0000200 /* CREAD */ | 0002000 /* CLOCAL */;
    tio.c_iflag = 0;
    tio.c_oflag = 0;
    tio.c_lflag = 0;
    sys_ioctl(fd, TCSETS, (unsigned long)&tio);

    // 4. Hardware Reset / Boot Mode Sequence (DTR & RTS pulsen)
    unsigned long dtr_rts = TIOCM_DTR | TIOCM_RTS;
    sys_ioctl(fd, TIOCMBIC, (unsigned long)&dtr_rts); // Laag
    for(volatile int i=0; i<5000000; i++);
    sys_ioctl(fd, TIOCMBIS, (unsigned long)&dtr_rts); // Hoog

    print_str("Verbonden met ESP32-C3. Start SLIP sync...\n");

    // 5. SYNC Commando sturen en respons controleren
    unsigned char sync_packet[44] = {
        0x00, 0x08, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x07, 0x07, 0x12, 0x20
    };
    for(int i=12; i<44; i++) sync_packet[i] = 0x55;

    unsigned char resp[64];
    int synced = 0;
    for (int attempt = 0; attempt < 10; attempt++) {
        send_slip_packet(fd, sync_packet, sizeof(sync_packet));
        // Probeer antwoord te vangen (in een echte loop wil je hier een timeout op bouwen, 
        // voor de eenvoud leest read_slip_packet tot een frame binnenkomt)
        int rlen = read_slip_packet(fd, resp, sizeof(resp));
        if (rlen > 2 && resp[1] == 0x08) { // Antwoord op SYNC (Opcode 8)
            synced = 1;
            break;
        }
    }

    if (!synced) {
        print_str("Fout: Kon niet synchroniseren met ESP32-C3.\n");
        sys_exit(1);
    }

    print_str("Sync succesvol! Laden naar RAM (0x3fc80000)...\n");

    // 6. MEM_BEGIN Commando (Opcode 0x05)
    // Vertel de bootloader: grootte van data, aantal blokken, blokgrootte en startadres (0x3fc80000)
    // Struct: [Dir, Op, Size(2), Checksum(4), DataSize(4), Blocks(4), BlockSize(4), TargetAddr(4)]
    unsigned char mem_begin[24] = {
        0x00, 0x05, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00,
        // Data size
        (unsigned char)(bin_len), (unsigned char)(bin_len >> 8), (unsigned char)(bin_len >> 16), (unsigned char)(bin_len >> 24),
        0x01, 0x00, 0x00, 0x00, // 1 blok
        (unsigned char)(bin_len), (unsigned char)(bin_len >> 8), (unsigned char)(bin_len >> 16), (unsigned char)(bin_len >> 24),
        0x00, 0x80, 0xC8, 0x3F  // Adres 0x3FC80000 (Little Endian)
    };
    send_slip_packet(fd, mem_begin, sizeof(mem_begin));
    read_slip_packet(fd, resp, sizeof(resp)); // Wacht op ACK

    // 7. MEM_DATA Commando (Opcode 0x07)
    // Verstuur de daadwerkelijke binary payload
    // Header (16 bytes) + bin_len bytes data
    int packet_len = 16 + bin_len;
    unsigned char *mem_data = (unsigned char *)__builtin_alloca(packet_len);
    
    mem_data[0] = 0x00; // Direction
    mem_data[1] = 0x07; // Opcode MEM_DATA
    mem_data[2] = (unsigned char)(bin_len);       // Size low
    mem_data[3] = (unsigned char)(bin_len >> 8);  // Size high
    
    // Checksum van de bin data
    unsigned int cksum = calculate_checksum(bin_buffer, bin_len);
    *(unsigned int*)&mem_data[4] = cksum;
    
    // Bloksequentie / parameters
    *(unsigned int*)&mem_data[8]  = 0; // Sequence number (blok 0)
    *(unsigned int*)&mem_data[12] = 0; // Dummy
    
    // Kopieer de binary data achter de header
    for (int i = 0; i < bin_len; i++) {
        mem_data[16 + i] = bin_buffer[i];
    }

    send_slip_packet(fd, mem_data, packet_len);
    read_slip_packet(fd, resp, sizeof(resp)); // Wacht op ACK

    // 8. MEM_END Commando (Opcode 0x06) - Start uitvoering op 0x3fc80000
    unsigned char mem_end[14] = {
        0x00, 0x06, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, // 0 = start direct met uitvoeren (execute=0, anders 1 om niet te starten)
        0x00, 0x00, 0x00, 0x00, 0x00
    };
    // Zet eventueel het entry-adres mee indien nodig in de bytes erna
    send_slip_packet(fd, mem_end, sizeof(mem_end));
    read_slip_packet(fd, resp, sizeof(resp)); // Wacht op ACK

    print_str("Programma succesvol geladen in RAM en uitgevoerd!\n");

    sys_close(fd);
    sys_exit(0);
}
