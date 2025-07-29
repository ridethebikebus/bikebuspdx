build:
	docker build -t bikebuspdx:latest --progress=plain .

run-local: build
	docker run --rm \
      -p 22030:22030 \
      -v ${PWD}:/app \
      --env-file .env \
      bikebuspdx:latest

shell:
	@docker run --rm \
	  -it \
      -v ${PWD}:/app \
      --env-file .env \
	  --entrypoint bashgs \
      bikebuspdx:latest


optimize-images:
	@docker run --rm \
	  -it \
	  -v ${PWD}:/app \
      --env-file .env \
	  --entrypoint ruby \
	  bikebuspdx:latest \
	  bin/optimize-images
