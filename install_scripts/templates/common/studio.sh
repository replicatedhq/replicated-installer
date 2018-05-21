
#######################################
#
# studio.sh
#
#######################################

STUDIO_URL=
promptForStudioUrl() {
    printf "Enter Replicated Studio URL: "
    prompt
    STUDIO_URL="$PROMPT_RESULT"
    if ! validateStudioUrl "$STUDIO_URL"; then
        printf "${RED}Failed to validate Studio URL.${NC}\n" 1>&2
        printf "${RED}Is Replicated Studio running at '%s'?${NC}\n" "$STUDIO_URL" 1>&2
        exit 1
    fi
    printf "The installer will use Replicated Studio at '%s'\n" "$STUDIO_URL"
}

validateStudioUrl() {
    if [ -z "$1" ]; then
        return 1
    fi
    if [ "$(curl -kqs -o /dev/null -w "%{http_code}" "${1}/v1/echo/ip" 2> /dev/null)" != "200" ]; then
        # TODO: validate that result is ip address
        return 1
    fi
    return 0
}

runStudio() {
    {% if replicated_env == 'staging' %}
    docker run --name studio -d \
         --restart always \
         -v {{ studio_base_path }}/replicated:/replicated \
         -p 8006:8006 \
         -e STUDIO_UPSTREAM_BASE_URL="https://api.staging.replicated.com/market" \
         replicated/studio:latest
    {% else %}
    docker run --name studio -d \
         --restart always \
         -v {{ studio_base_path }}/replicated:/replicated \
         -p 8006:8006 \
         replicated/studio:latest
    {%- endif %}
}
