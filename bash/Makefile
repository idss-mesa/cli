platform = linux/amd64
repo = harbor.cyverse.org/vice/mesa-cli
tag = latest
repotag = $(repo):$(tag)

build:
	docker buildx build --rm --platform "$(platform)" -t "$(repotag)" .

push:
	docker push "$(repotag)"

rmi:
	docker rmi "$(repotag)"
