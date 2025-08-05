#!/bin/bash
OSPREY_INSTALL=${OSPREY_INSTALL:-"${HOME}"}
. "${OSPREY_INSTALL}/osprey.sh"

skynet_version="0.0.1"

read -r -d '' DEFAULT_SYSTEM_INSTRUCTION <<- EOM
You are a robot.
You have tools that actually call devices in the physical world that you are connected to.
Use your tools to respond to human requests.
Keep your responses short and to the point.
EOM

SYSTEM_INSTRUCTION=${SYSTEM_INSTRUCTION:-"${DEFAULT_SYSTEM_INSTRUCTION}"}
model_server="http://localhost:12434/engines/llama.cpp/v1"
skynet_model="ai/qwen2.5:latest"
temperature="0.0"
pull_latest_model=true
robot_server="http://localhost:9090"
debug_mode=false
robot_tools="[]"
tool_server_map=()

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo " -h, --help           Display this help message"
  echo " -v, --version        Display version"
  echo " -d, --debug          Enable debug mode"
  echo " -m, --model          Model to use"
  echo " -p, --pull-model     Pull latest model"
  echo " -s, --model-server   Model server to use"
  echo " -i, --instructions   System instructions to use"
  echo " -t, --temperature    Temperature for model"
  echo " -r, --robot-server   Robot servers to use"
}

has_argument() {
  [[ ("$1" == *=* && -n ${1#*=}) || ( ! -z "$2" && "$2" != -*)  ]];
}

extract_argument() {
  echo "${2:-${1#*=}}"
}

handle_options() {
  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      -v | --version)
        show_version
        exit 0
        ;;
      -d | --debug)
        debug_mode=true
        ;;
      -m | --model*)
        if ! has_argument $@; then
          echo "Model not specified." >&2
          usage
          exit 1
        fi

        skynet_model=$(extract_argument $@)
        shift
        ;;
      -p | --pull-model*)
        if ! has_argument $@; then
          echo "Pull model not specified." >&2
          usage
          exit 1
        fi

        pull_latest_model=$(extract_argument $@)
        shift
        ;;
      -s | --model-server*)
        if ! has_argument $@; then
          echo "Model server not specified." >&2
          usage
          exit 1
        fi

        model_server=$(extract_argument $@)
        shift
        ;;
      -t | --temperature*)
        if ! has_argument $@; then
          echo "Temperature not specified." >&2
          usage
          exit 1
        fi

        temperature=$(extract_argument $@)
        shift
        ;;
      -i | --instructions*)
        if ! has_argument $@; then
          echo "System instructions not specified." >&2
          usage
          exit 1
        fi

        SYSTEM_INSTRUCTION=$(extract_argument $@)
        shift
        ;;
      -r | --robot-server*)
        if ! has_argument $@; then
          echo "Robot server not specified." >&2
          usage
          exit 1
        fi

        robot_server=$(extract_argument $@)
        shift
        ;;
      *)
        echo "Invalid option: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

show_banner() {
  echo "----------------------------------------------------";
  echo "███████╗██╗  ██╗██╗   ██╗███╗   ██╗███████╗████████╗";
  echo "██╔════╝██║ ██╔╝╚██╗ ██╔╝████╗  ██║██╔════╝╚══██╔══╝";
  echo "███████╗█████╔╝  ╚████╔╝ ██╔██╗ ██║█████╗     ██║   ";
  echo "╚════██║██╔═██╗   ╚██╔╝  ██║╚██╗██║██╔══╝     ██║   ";
  echo "███████║██║  ██╗   ██║   ██║ ╚████║███████╗   ██║   ";
  echo "╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝   ";
  echo "----------------------------------------------------";
}

show_version() {
  echo "🔺 Skynet version $skynet_version"
}

show_instructions() {
  echo "🔺 System instruction:"
  echo "${SYSTEM_INSTRUCTION}"
}

setup_robot_tools() {
  IFS=',' read -ra server_array <<< "$robot_server"

  for server in "${server_array[@]}"; do
    tools_json=$(get_mcp_http_tools "$server")
    if [[ -z "$tools_json" || "$tools_json" == "null" ]]; then
      continue
    fi

    function_nameS=$(echo "$tools_json" | jq -r '.[].name')
    for fname in $function_nameS; do
      tool_server_map["$fname"]="$server"
    done
    robot_tools=$(jq -s 'add' <(echo "$robot_tools") <(echo "$tools_json"))
  done
}

# main
handle_options "$@"

clear
show_banner
show_version
echo "🧠 loading model ${skynet_model}"

if [[ "$pull_latest_model" == "true" ]]; then
  docker model pull ${skynet_model}
fi

echo ""

setup_robot_tools

if [[ "$robot_tools" == "[]" ]]; then
    echo "🔴 no robot MCP servers. Exiting..."
    exit 1
fi

available_tools=$(transform_to_openai_format "$robot_tools")
if [[ -z "$available_tools" ]]; then
    echo "🔴 no robot MCP server tools found. Exiting..."
    exit 1
fi

if [[ "$debug_mode" == "true" ]]; then
  echo "---------------------------------------------------------"
  echo "Available tools:"
  echo "${available_tools}" 
  echo "---------------------------------------------------------"
  show_instructions
  echo ""
fi

conversation_history=()

while true; do
  stopped="false"
  tools_called="false"
  user_command=$(gum write --placeholder "🎤 Skynet ready. Enter command (/bye to exit).")
  
  if [[ "$user_command" == "/bye" ]]; then
    echo "Goodbye!"
    break
  fi

  echo "💬 ${user_command}"
  echo ""

  add_user_message conversation_history "${user_command}"

  while [ "$stopped" != "true" ]; do
    messages=$(build_messages_array conversation_history)

    read -r -d '' payload <<- EOM
{
  "model": "${skynet_model}",
  "options": {
    "temperature": ${temperature}
  },
  "messages": [${messages}],
  "tools": ${available_tools},
  "parallel_tool_calls": false,
  "tool_choice": "auto"
}
EOM

    result=$(osprey_tool_calls ${model_server} "${payload}")

    if [[ "$debug_mode" == "true" ]]; then
      echo "📝 model response:"
      print_raw_response "${result}"
    fi

    finish_reason=$(get_finish_reason "${result}")
    case $finish_reason in
      tool_calls)
        tools_called="true"
        tool_calls=$(get_tool_calls "${result}")

        if [[ -n "$tool_calls" ]]; then
            add_tool_calls_message conversation_history "${tool_calls}"

            for tool_call in $tool_calls; do
                function_name=$(get_function_name "$tool_call")
                function_args=$(get_function_args "$tool_call")
                tool_call_id=$(get_call_id "$tool_call")

                tool_server_for_call="${tool_server_map[$function_name]}"
                if [[ -z "$tool_server_for_call" ]]; then
                  tool_server_for_call="$robot_server" # fallback
                fi

                echo "🛠️ calling tool '$function_name' on $tool_server_for_call with $function_args"

                mcp_response=$(call_mcp_http_tool "$tool_server_for_call" "$function_name" "$function_args")
                result_content=$(get_tool_content_http "$mcp_response")

                echo "✅ result $result_content"

                tool_result=$(echo "${result_content}" | jq -e '.content' >/dev/null 2>&1 && echo "${result_content}" | jq -r '.content' || echo "${result_content}")
                add_tool_message conversation_history "${tool_call_id}" "${tool_result}"
            done
        else
          if [[ "$debug_mode" == "true" ]]; then
            echo "🔵 no tool calls found in response"
          fi
        fi
        ;;
      stop)
        stopped="true"
        assistant_message=$(echo "${result}" | jq -r '.choices[0].message.content')

        if [[ "$tools_called" == "true" ]]; then
          echo ""
        fi

        echo "🤖 ${assistant_message}"

        add_assistant_message conversation_history "${assistant_message}"
        ;;
      *)
        echo "🔴 unexpected model response: $finish_reason"
        ;;
    esac
  done
  echo ""
done
