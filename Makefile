build-image:
	docker build -t bikebuspdx:latest --progress=plain .

serve: build-image
	docker run --rm \
      -p 22030:22030 \
      -v ${PWD}:/app \
      --env-file .env \
      bikebuspdx:latest

build: build-image
	@docker run --rm \
	  -v ${PWD}:/app \
	  --env-file .env \
	  bikebuspdx:latest \
	  build
shell:
	@docker run --rm \
	  -it \
      -v ${PWD}:/app \
      --env-file .env \
	  --entrypoint bash \
      bikebuspdx:latest

prepare-for-jotform-trim:
	@docker run --rm \
	  -v ${PWD}:/app \
	  --env-file .env \
	  -e PREPARE_FOR_JOTFORM_TRIM=1 \
	  -e USE_LOCAL_IMAGES=false \
	  bikebuspdx:latest \
	  build

optimize-images:
	@docker run --rm \
	  -v ${PWD}:/app \
      --env-file .env \
	  --entrypoint ruby \
	  bikebuspdx:latest \
	  bin/optimize-images
