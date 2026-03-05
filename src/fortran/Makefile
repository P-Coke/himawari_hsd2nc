.SUFFIXES:

ROOT_DIR := $(CURDIR)
SRC_DIR := $(ROOT_DIR)/src
BUILD_DIR := $(ROOT_DIR)/build
BIN_DIR := $(ROOT_DIR)/bin

LIBDIR ?=
NETCDF_FFLAGS ?= $(shell nf-config --fflags 2>/dev/null)
NETCDF_FLIBS ?= $(shell nf-config --flibs 2>/dev/null)
HDF5_CFLAGS ?= $(shell pkg-config --cflags hdf5 2>/dev/null)
HDF5_LIBS ?= $(shell pkg-config --libs hdf5 2>/dev/null)

ifeq ($(strip $(NETCDF_FFLAGS)),)
ifneq ($(strip $(LIBDIR)),)
NETCDF_FFLAGS := -I$(LIBDIR)/include
endif
endif

ifeq ($(strip $(NETCDF_FLIBS)),)
ifneq ($(strip $(LIBDIR)),)
NETCDF_FLIBS := -L$(LIBDIR)/lib -lnetcdff -lnetcdf
else
NETCDF_FLIBS := -lnetcdff -lnetcdf
endif
endif

ifeq ($(strip $(HDF5_LIBS)),)
ifneq ($(strip $(LIBDIR)),)
HDF5_LIBS := -L$(LIBDIR)/lib -lhdf5 -lhdf5_fortran -lhdf5_hl_fortran
else
HDF5_LIBS := -lhdf5 -lhdf5_fortran -lhdf5_hl_fortran
endif
endif

INCDIRS := $(NETCDF_FFLAGS) $(HDF5_CFLAGS) -I$(BUILD_DIR)
LINKS := $(NETCDF_FLIBS) $(HDF5_LIBS) -lm -fopenmp

CC := gcc
F90 := gfortran
CFLAGS := -g -O3 -fopenmp
F90FLAGS := -g -O3 -ffree-line-length-0 -cpp -fopenmp -fcheck=bounds
F90MOD := -J$(BUILD_DIR)

OBJ_COMMON := \
	$(BUILD_DIR)/himawari.o \
	$(BUILD_DIR)/himawari_headerinfo.o \
	$(BUILD_DIR)/himawari_readheader.o \
	$(BUILD_DIR)/himawari_utils.o \
	$(BUILD_DIR)/himawari_nav.o \
	$(BUILD_DIR)/himawari_readwrite.o

OBJ_SOLPOS := $(BUILD_DIR)/solpos.o
LIB_HIM := $(BUILD_DIR)/libhimawari_util.a
LIB_SOL := $(BUILD_DIR)/solar_util.a

.PHONY: all dirs clean AHI AHI_FAST AHI_FAST_ROI

all: dirs $(BIN_DIR)/AHI $(BIN_DIR)/AHI_FAST $(BIN_DIR)/AHI_FAST_ROI

AHI: $(BIN_DIR)/AHI
AHI_FAST: $(BIN_DIR)/AHI_FAST
AHI_FAST_ROI: $(BIN_DIR)/AHI_FAST_ROI

dirs:
	@mkdir -p "$(BUILD_DIR)" "$(BIN_DIR)"

$(LIB_HIM): $(OBJ_COMMON) $(OBJ_SOLPOS)
	ar -rs $@ $^

$(LIB_SOL): $(OBJ_SOLPOS)
	ar -rs $@ $^

$(BIN_DIR)/AHI: $(OBJ_COMMON) $(BUILD_DIR)/AHI_Example.o $(LIB_HIM) $(LIB_SOL)
	$(F90) -o $@ $(OBJ_COMMON) $(BUILD_DIR)/AHI_Example.o $(LIB_HIM) $(LIB_SOL) $(F90FLAGS) $(INCDIRS) $(LINKS)

$(BIN_DIR)/AHI_FAST: $(OBJ_COMMON) $(BUILD_DIR)/AHI_FAST_Example.o $(LIB_HIM) $(LIB_SOL)
	$(F90) -o $@ $(OBJ_COMMON) $(BUILD_DIR)/AHI_FAST_Example.o $(LIB_HIM) $(LIB_SOL) $(F90FLAGS) $(INCDIRS) $(LINKS)

$(BIN_DIR)/AHI_FAST_ROI: $(OBJ_COMMON) $(BUILD_DIR)/AHI_FAST_Example.o $(LIB_HIM) $(LIB_SOL)
	$(F90) -o $@ $(OBJ_COMMON) $(BUILD_DIR)/AHI_FAST_Example.o $(LIB_HIM) $(LIB_SOL) $(F90FLAGS) $(INCDIRS) $(LINKS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.f90 | dirs
	$(F90) -c -o $@ $(F90FLAGS) $(F90MOD) $(INCDIRS) $<

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | dirs
	$(CC) -c -o $@ $(CFLAGS) $(INCDIRS) $<

clean:
	rm -rf "$(BUILD_DIR)" "$(BIN_DIR)"
