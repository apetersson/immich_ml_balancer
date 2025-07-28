# Immich ML on Mac and Load Balancer Setup

This document provides instructions on how to run the Immich Machine Learning (ML) service natively on a Mac (leveraging Apple's Core ML for performance) and how to integrate such an instance into a load-balanced setup using the `immich_ml_balancer` Docker container.

## 1. How to Run Immich ML Natively on a Mac

Run the ML service **natively** so ONNX Runtime feeds Apple’s Core ML provider—no Docker needed. This is ideal for leveraging the Neural Engine on Apple Silicon Macs for faster ML inference.

1.  **System Preparation (once)**

    ```bash
    xcode-select --install                 # compilers & headers
    brew install git pyenv pipx uv         # uv = fast dep solver
    pyenv install 3.12.2 && pyenv global 3.12.2
    ```

2.  **Grab Immich’s ML Code**

    ```bash
    git clone --depth 1 https://github.com/immich-app/immich.git
    cd immich/machine-learning
    ```

3.  **(Optional) Force Core ML to be Tried First**
    Edit `app/models/constants.py` and move `"CoreMLExecutionProvider"` to the top of `SUPPORTED_PROVIDERS`.

4.  **Clean Virtual Environment with Only Runtime Dependencies**

    ```bash
    uv venv .venv --python $(pyenv which python)
    UV_HTTP_TIMEOUT=120 uv sync --extra cpu --no-dev
    source .venv/bin/activate
    ```

5.  **Verify the Provider List**

    ```bash
    python - <<'PY'
    import onnxruntime as ort
    print(ort.get_available_providers())   # ['CoreMLExecutionProvider', 'CPUExecutionProvider']
    PY
    ```

6.  **Launch the Service**

    ```bash
    export MACHINE_LEARNING_CACHE_FOLDER=$HOME/.immich-model-cache
    mkdir -p "$MACHINE_LEARNING_CACHE_FOLDER"
    python -m immich_ml            # listens on :3003
    ```

7.  **Smoke Test**

    ```bash
    curl -s http://192.168.0.<mac-ip>:3003/ping    # → pong
    ```

That’s it—your M2’s Neural Engine now handles all Immich ML tasks at full speed.

## 2. How to Enable this Instance as Part of a Load Balancer Setup

This section explains how to integrate your natively running Mac ML instance (or any other `immich_ml` instance) into a load-balanced setup using the `immich_ml_balancer` Docker container.

### Immich ML Balancer Overview

The `immich_ml_balancer` is a lightweight Nginx-based Docker image designed to distribute ML inference requests across multiple `immich_ml` service instances. It supports dynamic backend configuration and gracefully handles instances that might be sporadically available.

### Building the Balancer Docker Image

To build the Docker image for the balancer, navigate to the `immich_ml_balancer` directory (where this README is located) and run the following command:

```bash
cd /path/to/your/immich_ml_balancer # Replace with the actual path
docker build --platform linux/amd64 -t apetersson/immich_ml_balancer:latest .
```

Replace `apetersson` with your Docker Hub username if you plan to push it.

### Pushing to Docker Hub

After building, you can push the image to your Docker Hub repository to make it publicly available:

1.  **Log in to Docker Hub (if not already logged in):**
    ```bash
    docker login
    ```
2.  **Push the image:**
    ```bash
    docker push apetersson/immich_ml_balancer:latest
    ```

### Integrating with `docker-compose.yml`

To use the balancer, you'll update your main Immich `docker-compose.yml` file. This example assumes you have a local `immich-machine-learning` instance (e.g., on your NAS) and your Mac (`desktop.local`) as backends.

Then, add the `immich-ml-balancer` service and configure its backends using the `IMML_BACKENDS` environment variable. Also, ensure your local `immich-machine-learning` instance is defined as a service that the balancer can reach.

#### Example docker compose section to add:
```yaml

services:
  # ... your existing immich-server, redis, database, backup services ...

  immich-ml-balancer:
    container_name: immich_ml_balancer
    image: apetersson/immich_ml_balancer:latest # Your custom balancer image
    environment:
      # Comma-separated list of immich_ml instance hostnames/IPs.
      # Format: "hostname_or_ip[:port]"
      # If port is omitted, it defaults to 3003.
      IMML_BACKENDS: "immich-machine-learning,192.168.0.123:3003,desktop.local:3003" # Example with local and a
      # No ports mapping needed here, as it's accessed via the internal network by immich server on port 80
    depends_on:
      - immich-machine-learning # Depend on at least one ML instance for startup order
    restart: always
    
  #your existing immich-machine-learning docker container
  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:release-openvino
    volumes:
      - ${MODEL_CACHE_LOCATION}:/cache
    devices:
      - /dev/dri:/dev/dri
    device_cgroup_rules:
      - 'c 189:* rmw'
    env_file:
      - .env
    restart: always
    #optionally limit ram to keep the machine happy
    deploy:
      resources:
        limits:
          memory: 5G
    # No ports mapping needed here, as it's accessed via the internal network by the balancer
```


Then, ensure your `immich-server` service points to the balancer. You can do this in the yaml or via an .env file

```yaml
services:
  immich-server:
    # ... existing configuration ...
    environment:
      # Point the Immich server to the balancer
      IMMICH_MACHINE_LEARNING_URL: http://immich-ml-balancer:80
    # ... rest of immich-server config ...
```

### `IMML_BACKENDS` Environment Variable

This variable is a comma-separated string of your `immich_ml` backend instances. Each entry can be:

*   `hostname_or_ip`: If no port is specified, the balancer will assume the `immich_ml` instance is listening on port `3003`.
*   `hostname_or_ip:port`: To specify a custom port for a backend.

**Examples:**

*   `IMML_BACKENDS: "my-local-ml,192.168.1.100:8000,another-server.lan"`
    *   `my-local-ml` will be accessed on port `3003`.
    *   `192.168.1.100` will be accessed on port `8000`.
    *   `another-server.lan` will be accessed on port `3003`.

### Handling Sporadic Instances

The Nginx configuration includes `proxy_next_upstream` directives. This means if a backend instance listed in `IMML_BACKENDS` is temporarily unavailable (e.g., offline, unresponsive), the balancer will automatically try the next available instance in the list. When the sporadic instance comes back online, Nginx will eventually detect it and resume sending requests.
