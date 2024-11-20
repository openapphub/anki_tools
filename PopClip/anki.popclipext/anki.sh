#!/usr/bin/env bash

# PopClip Environment Variables with fallback values
CONTENT=${POPCLIP_TEXT:-debug}
TARGET_DECK=${POPCLIP_OPTION_TARGET_DECK:-"测试::demo::001"}
NOTE_TYPE=${POPCLIP_OPTION_NOTE_TYPE:-"A-prettify-nord-basic"}
CONTENT_FIELD=${POPCLIP_OPTION_CONTENT_FIELD:-"Back"}
DEFAULT_TAGS=${POPCLIP_OPTION_DEFAULT_TAGS:-"popclip"}
HTML_CONTENT=${POPCLIP_HTML:-""}

# 日志配置
LOG_FILE="$HOME/popclip_anki_debug.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_FILE"
}

# JSON 转义函数
escape_for_json() {
    local string="$1"
    string="${string//\\/\\\\}"  # 反斜杠
    string="${string//\"/\\\"}"  # 双引号
    string="${string//$/\\$}"    # 美元符号
    string="${string//	/\\t}"   # 制表符
    string="${string//
/\\n}"    # 换行符
    string="${string///\\/}"    # 正斜杠
    echo "$string"
}

# 文本处理函数
format_text() {
    local text="$CONTENT"
    local result=""
    local in_code_block=false
    local current_block=""
    local lang=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^'```' ]]; then
            if [ "$in_code_block" = false ]; then
                in_code_block=true
                lang=$(echo "$line" | sed -E 's/^```([a-zA-Z]*).*/\1/')
                [ -z "$lang" ] && lang="plaintext"
                result+="<pre><code class=\"language-$lang\">"
                current_block=""
            else
                in_code_block=false
                result+="$current_block</code></pre><br>"
                current_block=""
            fi
        else
            if [ "$in_code_block" = true ]; then
                # 在代码块内，保持原始格式
                if [ -n "$current_block" ]; then
                    current_block+=$'\n'
                fi
                current_block+="$line"
            else
                # 在代码块外，仅在非空行添加换行符
                if [ -n "$line" ]; then
                    result+="$line<br>"
                fi
            fi
        fi
    done <<< "$text"
    
    # 如果代码块没有正确关闭，确保关闭它
    if [ "$in_code_block" = true ]; then
        result+="$current_block</code></pre><br>"
    fi
    
    echo "$result"
}

# 生成 AnkiConnect 请求数据
gen_post_data() {
    local formatted_content
    formatted_content=$(format_text)
    formatted_content=$(escape_for_json "$formatted_content")
    
    cat <<EOF
{
    "action": "guiAddCards",
    "version": 6,
    "params": {
        "note": {
            "deckName": "$TARGET_DECK",
            "modelName": "$NOTE_TYPE",
            "fields": {
                "$CONTENT_FIELD": "$formatted_content"
            },
            "tags": ["$DEFAULT_TAGS"]
        }
    }
}
EOF
}

# 发送请求到 AnkiConnect
send_to_anki() {
    local payload="$1"
    local response
    
    log "Sending request to AnkiConnect..."
    response=$(curl -s -X POST "localhost:8765" -H "Content-Type: application/json" -d "$payload")
    
    if [[ $response == "null" ]]; then
        log "Error: Failed to connect to AnkiConnect"
        return 1
    elif [[ $response != *'"error": null'* ]]; then
        log "Error: AnkiConnect returned an error"
        log "Response: $response"
        return 1
    fi
    
    log "Successfully sent to Anki"
    log "Response: $response"
}

main() {
    log "Script started"
    log "Processing content: $CONTENT"
    
    payload=$(gen_post_data)
    log "Generated payload: $payload"
    
    if ! send_to_anki "$payload"; then
        log "Failed to send to Anki"
        exit 1
    fi
    
    log "Script finished successfully"
}

main