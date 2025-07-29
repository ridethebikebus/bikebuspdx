build:
	docker build -t bikebuspdx:latest --progress=plain .

run-local: build
	docker run --rm \
      -p 22030:22030 \
      -v ${PWD}:/app \
      bikebuspdx:latest

shell:
	@docker run --rm \
	  -it \
      -v ${PWD}:/app \
	  --entrypoint bashgs \
      bikebuspdx:latest


optimize-images:
	@docker run --rm \
	  -it \
	  -v ${PWD}:/app \
	  --entrypoint ruby \
	  bikebuspdx:latest \
	  bin/optimize-images
