
#######################################
#
# studio.sh
#
#######################################

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
