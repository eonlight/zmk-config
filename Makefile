# Makefile for building rergo ZMK firmware.
#
# Requires Docker. The image is pinned deliberately: west.yml tracks ZMK main,
# which pulls Zephyr 4.1 and needs Zephyr SDK 0.16/0.17. The 4.4-branch image
# ships SDK 1.0.1, which refuses any request below 1.0 and cannot build this repo.

IMAGE   ?= zmkfirmware/zmk-build-arm:4.1-branch
BOARD   ?= nice_nano//zmk
WORKDIR := /tmp/zmk-config
OUT     := firmware

# The shield is discovered through this repo's zephyr/module.yml (board_root: .).
# The module is staged in a separate dir inside the container: pointing
# ZMK_EXTRA_MODULES at the repo root makes Zephyr source its own west-fetched
# zephyr/ checkout and die with "recursive 'source' of 'Kconfig.zephyr'".
MODULE  := /tmp/usercfg

DOCKER   = docker run --rm -v"$(CURDIR)":$(WORKDIR) -w $(WORKDIR) $(IMAGE) bash -c
STAGE    = west zephyr-export >/dev/null 2>&1; \
           rm -rf $(MODULE); mkdir -p $(MODULE)/zephyr; \
           cp -r $(WORKDIR)/boards $(WORKDIR)/config $(MODULE)/; \
           cp $(WORKDIR)/zephyr/module.yml $(MODULE)/zephyr/module.yml;
COMMON   = -DZMK_CONFIG=$(MODULE)/config -DZMK_EXTRA_MODULES=$(MODULE)

.PHONY: all left right reset deps clean distclean check-docker help

all: left right reset ## Build all three targets

## Build the left (central) half: USB HID + ZMK Studio
left: check-docker | $(OUT)
	$(DOCKER) '$(STAGE) west build -s zmk/app -d build/left -b "$(BOARD)" -S studio-rpc-usb-uart -- -DSHIELD=rergo_left $(COMMON) -DCONFIG_ZMK_STUDIO=y'
	cp build/left/zephyr/zmk.uf2 $(OUT)/rergo_left.uf2

## Build the right (BLE peripheral) half
right: check-docker | $(OUT)
	$(DOCKER) '$(STAGE) west build -s zmk/app -d build/right -b "$(BOARD)" -- -DSHIELD=rergo_right $(COMMON)'
	cp build/right/zephyr/zmk.uf2 $(OUT)/rergo_right.uf2

## Build settings_reset (clears stored BLE bonds; flash to both halves)
reset: check-docker | $(OUT)
	$(DOCKER) '$(STAGE) west build -s zmk/app -d build/reset -b "$(BOARD)" -- -DSHIELD=settings_reset $(COMMON)'
	cp build/reset/zephyr/zmk.uf2 $(OUT)/settings_reset.uf2

## Fetch Zephyr/ZMK dependencies (~2GB, first-time setup)
deps: check-docker
	$(DOCKER) 'west update && west zephyr-export'

$(OUT):
	mkdir -p $(OUT)

## Remove build output and firmware artifacts
clean:
	rm -rf build $(OUT)

## Also remove west-fetched dependencies (requires `make deps` again)
distclean: clean
	rm -rf zmk modules optional .west
	@# keep the tracked zephyr/module.yml that registers this repo as a module
	find zephyr -mindepth 1 -maxdepth 1 ! -name module.yml -exec rm -rf {} +

check-docker:
	@docker info >/dev/null 2>&1 || { \
	  echo "error: cannot reach the Docker daemon."; \
	  echo "Start Docker (or check 'docker context ls') and retry."; \
	  exit 1; }

help:
	@echo "Targets:"
	@echo "  all        build left, right and settings_reset"
	@echo "  left       left half: central, USB HID + ZMK Studio"
	@echo "  right      right half: BLE peripheral"
	@echo "  reset      settings_reset, clears BLE bonds"
	@echo "  deps       fetch Zephyr/ZMK dependencies (~2GB, run once)"
	@echo "  clean      remove build/ and $(OUT)/"
	@echo "  distclean  also remove west-fetched deps"
	@echo ""
	@echo "Output: $(OUT)/{rergo_left,rergo_right,settings_reset}.uf2"
	@echo "Flash:  double-tap reset, copy the .uf2 to the NICENANO drive"
