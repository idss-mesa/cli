# MESA CLI images. The CPU image is built from bash/ (bash/Makefile); `make build`
# and `make push` here just call it. The NVIDIA GPU variant (gpu/) layers on
# the CPU image and is linux/amd64 only.
platform = linux/amd64
repo = harbor.cyverse.org/vice/mesa-cli

.PHONY: build push pull-base build-gpu test-gpu push-gpu run-gpu

build:            ## CPU image (:latest, amd64) via bash/Makefile
	$(MAKE) -C bash build

push:
	$(MAKE) -C bash push

# ---- NVIDIA GPU variant (gpu/) — layers on the CPU image above ----
gpu_repotag = $(repo):gpu
base_image = $(repo):latest

pull-base:        ## fetch the published CPU image the GPU layer builds FROM
	docker pull "$(base_image)"

build-gpu:        ## base_image defaults to the CPU :latest (`make build build-gpu` layers on a local CPU build; base_image=$(repo)@sha256:... pins one)
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(base_image)" -t "$(gpu_repotag)" --load gpu/
	@docker image inspect -f 'built on $(base_image): {{.Id}} {{.RepoDigests}}' "$(base_image)" 2>/dev/null || true

test-gpu:         ## GPU smoke test (needs an NVIDIA GPU + nvidia-container-toolkit); GPU=<index> picks the device
	gpu/test-gpu.sh "$(gpu_repotag)"

push-gpu:
	docker push "$(gpu_repotag)"

run-gpu:          ## loopback only: outside VICE (whose cas-proxy does the login) the terminal is unauthenticated and jovyan has sudo; remote: ssh -L 7681:127.0.0.1:7681 <gpu-host>
	docker run --rm --gpus all -p 127.0.0.1:7681:7681 -e IPLANT_USER=$$USER "$(gpu_repotag)"

# ---- AI Sandbox variants (sandbox/): the published images with sudo and every
# setuid/setgid/file-capability escalation path removed. :sandbox layers on the
# CPU :latest, :gpu-sandbox on :gpu. ----
sandbox_repotag = $(repo):sandbox
gpu_sandbox_repotag = $(repo):gpu-sandbox
sandbox_port = 7681
sandbox_path = /
sandbox_docker_args = 

build-sandbox:    ## :sandbox from the CPU image (base_image=... to pin a digest)
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(repo):latest" -t "$(sandbox_repotag)" --load sandbox/

build-gpu-sandbox: ## :gpu-sandbox from the GPU image
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(gpu_repotag)" -t "$(gpu_sandbox_repotag)" --load sandbox/

test-sandbox:     ## lockdown + startup checks as UID 1000 (no GPU needed)
	SANDBOX_PORT=$(sandbox_port) SANDBOX_PATH=$(sandbox_path) SANDBOX_DOCKER_ARGS="$(sandbox_docker_args)" sandbox/test-sandbox.sh "$(sandbox_repotag)"

test-gpu-sandbox:
	SANDBOX_PORT=$(sandbox_port) SANDBOX_PATH=$(sandbox_path) SANDBOX_DOCKER_ARGS="$(sandbox_docker_args)" sandbox/test-sandbox.sh "$(gpu_sandbox_repotag)"

push-sandbox:
	docker push "$(sandbox_repotag)"

push-gpu-sandbox:
	docker push "$(gpu_sandbox_repotag)"

.PHONY: build-sandbox build-gpu-sandbox test-sandbox test-gpu-sandbox push-sandbox push-gpu-sandbox
