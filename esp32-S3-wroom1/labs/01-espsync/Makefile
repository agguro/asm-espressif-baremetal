# Variabelen
AS = as
LD = ld
ASFLAGS = --64
LDFLAGS = -s # Stripped binary voor minimale voetafdruk

TARGET = espsync
SRC = $(TARGET).s
OBJ = $(TARGET).o

# Standaard target
all: $(TARGET)

# Assembleren
$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) -o $(OBJ) $(SRC)

# Linken
$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

# Uitvoeren met sudo (directe hardware toegang)
run: $(TARGET)
	sudo ./$(TARGET)

# Trace target om de syscalls live te inspecteren
trace: $(TARGET)
	sudo strace ./$(TARGET)

# Schoonmaken
clean:
	rm -f $(OBJ) $(TARGET)

.PHONY: all run trace clean
