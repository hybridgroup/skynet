# 🔺 Installing Skynet

Here is how to install Skynet.

First clone the repository:

```shell
git clone https://github.com/hybridgroup/skynet.git
cd skynet
```

Now make sure you have everything else you need.

## 🔺 Model Server

You use Skynet with an LLM model server and any model that supports tool instructions.

You can use any LLM server that provides an OpenAI-compatible API, such as [Docker Model Runner](https://www.docker.com/products/model-runner/), Ollama or llama-server.

See [MODELS.md](MODELS.md) for a list of models that are known to support multistep actions.

## 🔺 Dependencies

🔺 jq - A lightweight and flexible command-line JSON processor. You probably already have this installed.

🔺 awk - A domain-specific language designed for text processing. You probably already have this installed.

🔺 curl - A command-line tool for transferring data with URLs. You definitely already have this installed.

🔺 bash - A Unix shell and command language. You definitely already have this installed.

🔺 [gum](https://github.com/charmbracelet/gum) - A tool for creating interactive command-line applications.

Easiest way to install Gum is using Go. Run this command:

```shell
go install github.com/charmbracelet/gum@latest
```

🔺 [osprey](https://github.com/k33g/osprey) - A lightweight Bash library for interacting with the DMR (Docker Model Runner) API.

```shell
curl -fsSL https://github.com/k33g/osprey/releases/download/v0.1.1/osprey.sh -o ./osprey.sh
chmod +x ./osprey.sh
```
## 🔺 MCP Server

Next you need to install and run any MCP servers to connect to your robotic device. See [ROBOTS.md](./ROBOTS.md) for details on how to connect to some known devices.

## 🔺 Ready

Now you should be all ready to run Skynet!

See the [README](https://github.com/hybridgroup/skynet?tab=readme-ov-file#-running-skynet) here.
