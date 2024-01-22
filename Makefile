run-local:
	docker build -t bikebuspdx:latest --progress=plain .
	docker run --rm \
      -p 22030:22030 \
      -v ${PWD}:/app \
      bikebuspdx:latest
