# Docker Setup and Usage

This application is containerized using Docker with a multi-stage build for optimal size and security.

## Building the Docker Image

```bash
docker build -t freight-forwarder:latest .
```

## Running the Application

### Interactive Mode

Run the container and input data manually:

```bash
docker run -i freight-forwarder:latest
```

Then type your input line by line:

```bash
CNSHA
NLRTM
cheapest-direct
```

### With Input File

Use any of the provided test input files:

```bash
# Test cheapest direct route
cat test_input_cheapest_direct.txt | docker run -i freight-forwarder:latest

# Test cheapest route (including indirect)
cat test_input_cheapest.txt | docker run -i freight-forwarder:latest

# Test fastest route
cat test_input_fastest.txt | docker run -i freight-forwarder:latest
```

### With Echo Input

Provide input directly via echo command:

```bash
# Cheapest direct route
echo -e "CNSHA\nNLRTM\ncheapest-direct" | docker run -i freight-forwarder:latest

# Cheapest route (any)
echo -e "CNSHA\nNLRTM\ncheapest" | docker run -i freight-forwarder:latest

# Fastest route
echo -e "CNSHA\nNLRTM\nfastest" | docker run -i freight-forwarder:latest
```
