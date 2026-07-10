ASM=nasm
LD=ld

SRC=src/main.asm
OBJ=build/main.o
BIN=asm-raycaster

all:
	$(ASM) -f elf64 $(SRC) -o $(OBJ)
	$(LD) $(OBJ) -o $(BIN)

run: all
	./$(BIN)

clean:
	rm -f build/*.o $(BIN)