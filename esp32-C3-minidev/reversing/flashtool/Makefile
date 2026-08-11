# --- Configuratie ---
TARGET = flashtool
SRC = $(TARGET).s
OBJ = $(TARGET).o

AS = as
LD = ld

# --- Doelen ---
all: $(TARGET)

# 1. Assembleer x86_64 assembly naar objectbestand
$(OBJ): $(SRC)
	$(AS) --64 $< -o $@

# 2. Link het objectbestand naar een uitvoerbaar binary
$(TARGET): $(OBJ)
	$(LD) $< -o $@

# 3. Schoongemaakt
clean:
	rm -f $(OBJ) $(TARGET)

