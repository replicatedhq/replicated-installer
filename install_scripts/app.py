from __future__ import print_function

from flask import Flask, Response, abort, render_template, request, jsonify
import semver
import subprocess
import urllib
import traceback

from . import db, helpers, param

app = Flask(__name__)

@app.teardown_appcontext
def teardown_db(exception):
    db.teardown()


@app.route('/healthz')
def get_healthz():
    return ''


@app.route('/metricz')
def get_metricz():
    return ''


@app.route('/docker-install.sh')
def get_docker():
    docker_version = helpers.get_arg('docker_version',
                                     helpers.get_default_docker_version())
    lsb_dist = helpers.get_arg('lsb_dist', '')
    dist_version = helpers.get_arg('dist_version', '')
    major, minor, _ = map(int, docker_version.split('.'))
    if major == 1:
        if minor <= 12:
            tmpl_file = 'docker-install/1-12.sh'
        else:
            tmpl_file = 'docker-install/1-13.sh'
    elif major == 17 and minor <= 5:
        tmpl_file = 'docker-install/17-03-ce.sh'
    elif major == 17 and minor <= 6:
        tmpl_file = 'docker-install/17-06-ce.sh'
    else:
        tmpl_file = 'docker-install/17-12-ce.sh'
    kwargs = {
        'deb_version':
        helpers.get_docker_deb_pkg_version(docker_version, lsb_dist,
                                           dist_version),
        'rpm_version':
        helpers.get_docker_rpm_pkg_version(docker_version, lsb_dist,
                                           dist_version),
    }
    response = render_template(tmpl_file, **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/version')
@app.route('/<replicated_channel>/version')
@app.route('/<replicated_channel>/version/<app_slug>/<app_channel>')
def get_replicated_version(replicated_channel=None,
                           app_slug=None,
                           app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    return replicated_version


@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    if path:
        kwargs = helpers.template_args(path=path)
        response = render_template('resolve-route.sh', **kwargs)
        return Response(response, mimetype='text/x-shellscript')
    else:
        kwargs = helpers.template_args(channel_name='stable')
        kwargs['pinned_docker_version'] = '1.12.3'
        response = render_template('replicated-1.2.sh', **kwargs)
        return Response(response, mimetype='text/x-shellscript')


@app.route('/unstable')
def get_replicated_one_point_two_unstable():
    kwargs = helpers.template_args(channel_name='unstable')
    kwargs['pinned_docker_version'] = '1.12.3'
    response = render_template('replicated-1.2.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/beta')
def get_replicated_one_point_two_beta():
    kwargs = helpers.template_args(channel_name='beta')
    kwargs['pinned_docker_version'] = '1.12.3'
    response = render_template('replicated-1.2.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/stable')
def get_replicated_one_point_two_stable():
    kwargs = helpers.template_args(channel_name='stable')
    kwargs['pinned_docker_version'] = '1.12.3'
    response = render_template('replicated-1.2.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/agent')
@app.route('/<replicated_channel>/agent')
def get_replicated_agent(replicated_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    kwargs = helpers.template_args(channel_name=replicated_channel)
    kwargs['pinned_docker_version'] = '1.12.3'
    response = render_template('replicated-agent.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/docker')
@app.route('/<replicated_channel>/docker')
@app.route('/docker/<app_slug>/<app_channel>')
@app.route('/<replicated_channel>/docker/<app_slug>/<app_channel>')
def get_replicated_two_point_zero(replicated_channel=None,
                                  app_slug=None,
                                  app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print("Looking up tags for:", replicated_channel, app_slug, app_channel)

    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'replicated')

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    # The operator tag is passed into a similar script, so it shouldn't have
    # the channel prefix.
    replicated_operator_tag = replicated_operator_version

    channel_css = ''
    if app_slug and app_channel:
        channel_css = helpers.get_channel_css(app_slug, app_channel)

    # Port mappings narrow after the release of replicated 2.0.1654 with
    # premkit
    port_range = helpers.get_port_range(replicated_version)
    # Only Replicated versions prior to 2.1.0 should mount the root file system
    root_volume = helpers.get_root_volume_mount(replicated_version)
    # Only Replicated versions prior to 2.5.0 should need these additional
    # mounted volumes
    additional_etc_mounts = helpers.get_additional_etc_mounts(
        replicated_version)
    # Replicated versions at or later than 2.5.0 should run as non root users
    username = helpers.get_replicated_username(replicated_version)
    # Replicated versions less than 2.14.0 mount premkit data dir as a volume
    premkit_data_dir = helpers.get_premkit_data_dir(replicated_version)

    operator_tags = helpers.get_arg('operator_tags', 'local')

    customer_base_url = helpers.get_arg('customer_base_url')

    fast_timeouts = helpers.get_arg('use_fast_timeouts')

    response = render_template(
        'replicated-2.0.sh',
        **helpers.template_args(
            channel_css=helpers.base64_encode(channel_css),
            channel_name=replicated_channel,
            pinned_docker_version=pinned_docker_version,
            replicated_tag=replicated_tag,
            replicated_port_range=port_range,
            replicated_ui_tag=replicated_ui_tag,
            replicated_operator_tag=replicated_operator_tag,
            replicated_root_volume_mount=root_volume,
            replicated_additional_etc_mounts=additional_etc_mounts,
            premkit_data_dir=premkit_data_dir,
            operator_tags=operator_tags,
            replicated_username=username,
            customer_base_url_override=customer_base_url,
            use_fast_timeouts=fast_timeouts))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/operator')
@app.route('/<replicated_channel>/operator')
@app.route('/operator/<app_slug>/<app_channel>')
@app.route('/<replicated_channel>/operator/<app_slug>/<app_channel>')
def get_replicated_operator(replicated_channel=None,
                            app_slug=None,
                            app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print("Looking up tags for:", replicated_channel, app_slug, app_channel)

    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel)
    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_operator_version, 'replicated')

    # Only Replicated versions prior to 2.1.0 should mount the root file system
    root_volume = helpers.get_root_volume_mount(replicated_operator_version)
    # Only Replicated versions prior to 2.5.0 should need these additional
    # mounted volumes
    additional_etc_mounts = helpers.get_operator_additional_etc_mounts(
        replicated_operator_version)
    # Replicated versions at or later than 2.5.0 should run as non root users
    username = helpers.get_replicated_username(replicated_operator_version)

    operator_tags = helpers.get_arg('operator_tags', '')

    fast_timeouts = helpers.get_arg('use_fast_timeouts')

    response = render_template(
        'replicated-operator.sh',
        **helpers.template_args(
            channel_name=replicated_channel,
            pinned_docker_version=pinned_docker_version,
            replicated_operator_tag=replicated_operator_tag,
            replicated_root_volume_mount=root_volume,
            replicated_operator_additional_etc_mounts=additional_etc_mounts,
            operator_tags=operator_tags,
            replicated_username=username,
            use_fast_timeouts=fast_timeouts))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/docker-compose-generate')
@app.route('/<replicated_channel>/docker-compose-generate')
@app.route('/<app_slug>/<app_channel>/docker-compose-generate')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/docker-compose-generate')
def get_replicated_compose_generate(replicated_channel=None,
                                    app_slug=None,
                                    app_channel=None):
    kwargs = get_replicated_compose_v3_template_args(replicated_channel,
                                                     app_slug, app_channel)

    response = render_template('docker-compose-generate.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/docker-compose.yml')
@app.route('/<replicated_channel>/docker-compose.yml')
@app.route('/<app_slug>/<app_channel>/docker-compose.yml')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/docker-compose.yml')
def get_replicated_compose_v3(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    kwargs = get_replicated_compose_v3_template_args(replicated_channel,
                                                     app_slug, app_channel)

    script = render_template(
        'docker-compose-generate.sh', suppress_runtime=1, **kwargs)
    p = subprocess.Popen(
        ['bash', '-'],
        shell=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE)
    p.stdin.write(script)
    p.stdin.close()
    p.wait()
    response = p.stdout.read()
    p.stdout.close()
    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')

@app.route('/kubernetes/compatibility')
@app.route('/<replicated_channel>/kubernetes/compatibility')
@app.route('/<app_slug>/<app_channel>/kubernetes/compatibility')
def get_kubernetes_compatibility(replicated_channel=None,
                                app_slug=None,
                                app_channel=None):
    current_replicated_version = helpers.get_arg('current_replicated_version', '')
    parsed = semver.parse(current_replicated_version, loose=False)
    if parsed is None:
        abort(400)
    current_kubernetes_version = helpers.get_pinned_kubernetes_version(
        current_replicated_version)

    next_replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    next_kubernetes_version = helpers.get_pinned_kubernetes_version(
        next_replicated_version)

    body = {
        'compatible': current_kubernetes_version == next_kubernetes_version
    }

    return jsonify(body)


@app.route('/kubernetes/deploy.yml')
@app.route('/<replicated_channel>/kubernetes/deploy.yml')
@app.route('/<app_slug>/<app_channel>/kubernetes/deploy.yml')
def get_replicated_kubernetes_yml(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    kwargs = get_kubernetes_yaml_template_args(replicated_channel,
                                                app_slug, app_channel)
    script = render_template(
        'kubernetes-yml-generate.sh', suppress_runtime=1, **kwargs)
    p = subprocess.Popen(
        ['bash -s deployment-yaml=1', '-'],
        shell=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE)
    p.stdin.write(script)
    p.stdin.close()
    p.wait()
    response = p.stdout.read()
    p.stdout.close()
    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')


def get_replicated_compose_v3_template_args(replicated_channel=None,
                                            app_slug=None,
                                            app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print("Looking up tags for:", replicated_channel, app_slug, app_channel)

    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'swarm')

    # Port mappings narrow after the release of replicated 2.0.1654 with
    # premkit
    port_range = helpers.get_port_range(replicated_version)
    # Only Replicated versions prior to 2.1.0 should mount the root file system
    root_volume = helpers.get_root_volume_mount(replicated_version)
    # Only Replicated versions prior to 2.5.0 should need these additional
    # mounted volumes
    additional_etc_mounts = helpers.get_additional_etc_mounts(
        replicated_version)
    # Replicated versions at or later than 2.5.0 should run as non root users
    username = helpers.get_replicated_username(replicated_version)
    # Replicated versions at or later than 2.22.0 use replicated_default overlay network for snapshots
    snapshots_use_overlay = helpers.snapshots_use_overlay(replicated_version)


    airgap = helpers.get_arg('airgap', '')
    ca = helpers.get_arg('ca', '')
    daemon_registry_address = helpers.get_arg('daemon_registry_address', '')
    group_id = helpers.get_arg('group_id', '')
    log_level = helpers.get_arg('log_level', '')
    public_address = helpers.get_arg('public_address', '')
    registry_bind_port = helpers.get_arg('registry_bind_port', '')
    swarm_stack_namespace = helpers.get_arg('swarm_stack_namespace', '')
    swarm_node_address = helpers.get_arg('swarm_node_address', '')
    tls_cert_path = helpers.get_arg('tls_cert_path', '')
    ui_bind_port = helpers.get_arg('ui_bind_port', '')
    user_id = helpers.get_arg('user_id', '')

    customer_base_url = helpers.get_arg('customer_base_url')

    return helpers.template_args(
        channel_name=replicated_channel,
        pinned_docker_version=pinned_docker_version,
        replicated_tag=replicated_tag,
        replicated_port_range=port_range,
        replicated_ui_tag=replicated_ui_tag,
        replicated_operator_tag=replicated_operator_tag,
        replicated_root_volume_mount=root_volume,
        replicated_additional_etc_mounts=additional_etc_mounts,
        replicated_username=username,
        # query params
        airgap=airgap,
        ca=ca,
        daemon_registry_address=daemon_registry_address,
        group_id=group_id,
        log_level=log_level,
        public_address=public_address,
        registry_bind_port=registry_bind_port,
        swarm_stack_namespace=swarm_stack_namespace,
        swarm_node_address=swarm_node_address,
        tls_cert_path=tls_cert_path,
        ui_bind_port=ui_bind_port,
        user_id=user_id,
        customer_base_url_override=customer_base_url,
        snapshots_use_overlay=snapshots_use_overlay, )


@app.route('/compose.yml')
@app.route('/<replicated_channel>/compose.yml')
@app.route('/<app_slug>/<app_channel>/compose.yml')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/compose.yml')
@app.route('/compose')  # deprecate
@app.route('/<replicated_channel>/compose')  # deprecate
def get_replicated_compose_v2(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print("Looking up tags for:", replicated_channel, app_slug, app_channel)

    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    data_dir_path = helpers.get_arg('data_dir_path', '/tmp')
    log_level = helpers.get_arg('log_level', '')
    operator_tags = helpers.get_arg('operator_tags', 'local')
    public_address = helpers.get_arg('public_address', '')
    ui_bind_port = helpers.get_arg('ui_bind_port', '')

    if semver.lt(replicated_version, '2.10.0', loose=False):
        tmpl_file = 'docker-compose-v2-legacy.yml'
    else:
        tmpl_file = 'docker-compose-v2.yml'
    response = render_template(
        tmpl_file,
        **helpers.template_args(
            channel_name=replicated_channel,
            replicated_tag=replicated_tag,
            replicated_ui_tag=replicated_ui_tag,
            replicated_operator_tag=replicated_operator_tag,
            # query params
            data_dir_path=data_dir_path,
            log_level=log_level,
            operator_tags=operator_tags,
            public_address=public_address,
            ui_bind_port=ui_bind_port, ))

    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')

def get_kubernetes_yaml_template_args(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print("Looking up tags for:", replicated_channel, app_slug, app_channel)
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)

    pv_base_path = helpers.get_arg('pv_base_path', '/opt/replicated/rook')
    log_level = helpers.get_arg('log_level', 'info')
    release_sequence = helpers.get_arg('release_sequence', None)
    storage_class = helpers.get_arg('storage_class', 'default')
    storage_provisioner = helpers.get_arg('storage_provisioner', 1)
    service_type = helpers.get_arg('service_type', 'NodePort')
    kubernetes_namespace = helpers.get_arg('kubernetes_namespace', 'default')
    ui_bind_port = helpers.get_arg('ui_bind_port', 8800)
    customer_base_url = helpers.get_arg('customer_base_url')
    proxy_address = helpers.get_arg('http_proxy', '')
    # 10.96.0.0/12 is the default service cidr
    no_proxy_addresses = helpers.get_arg('no_proxy_addresses', '10.96.0.0/12')

    return helpers.template_args(
            channel_name=replicated_channel,
            replicated_tag=replicated_tag,
            replicated_ui_tag=replicated_ui_tag,
            pv_base_path=pv_base_path,
            log_level=log_level,
            release_sequence=release_sequence,
            storage_class=storage_class,
            storage_provisioner=storage_provisioner,
            service_type=service_type,
            kubernetes_namespace=kubernetes_namespace,
            ui_bind_port=ui_bind_port,
            proxy_address=proxy_address,
            no_proxy_addresses=no_proxy_addresses,
            customer_base_url_override=customer_base_url, )

@app.route('/kubernetes-yml-generate')
@app.route('/kubernetes-yml-generate.sh')
@app.route('/<replicated_channel>/kubernetes-yml-generate')
@app.route('/<app_slug>/<app_channel>/kubernetes-yml-generate')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-yml-generate')
def get_replicated_kubernetes(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    kwargs = get_kubernetes_yaml_template_args(replicated_channel,
                                                app_slug, app_channel)


    response = render_template('kubernetes-yml-generate.sh', **kwargs)

    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')


@app.route('/swarm-init')
@app.route('/<replicated_channel>/swarm-init')
@app.route('/<app_slug>/<app_channel>/swarm-init')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/swarm-init')
def get_swarm_init_master(replicated_channel=None,
                          app_slug=None,
                          app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'swarm')

    compose_path = 'docker-compose-generate'
    worker_path = 'swarm-worker-join'
    channel_css = ''
    if app_slug and app_channel:
        compose_path = app_slug + '/' + app_channel + '/' + compose_path
        worker_path = app_slug + '/' + app_channel + '/' + worker_path
        channel_css = helpers.get_channel_css(app_slug, app_channel)
    if replicated_channel != 'stable':
        compose_path = replicated_channel + '/' + compose_path
        worker_path = replicated_channel + '/' + worker_path

    query = urllib.urlencode(request.args)

    response = render_template(
        'swarm-init.sh',
        **helpers.template_args(
            pinned_docker_version=pinned_docker_version,
            docker_compose_path=compose_path,
            swarm_worker_join_path=worker_path,
            app_channel_css=helpers.base64_encode(channel_css),
            docker_compose_query=query, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/swarm-worker-join')
@app.route('/<replicated_channel>/swarm-worker-join')
@app.route('/<app_slug>/<app_channel>/swarm-worker-join')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/swarm-worker-join')
def get_swarm_init_worker(replicated_channel=None,
                          app_slug=None,
                          app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'swarm')
    swarm_master_address = helpers.get_arg('swarm_master_address')
    swarm_token = helpers.get_arg('swarm_token')
    response = render_template('swarm-worker-join.sh',
                               **helpers.template_args(
                                   pinned_docker_version=pinned_docker_version,
                                   swarm_master_address=swarm_master_address,
                                   swarm_token=swarm_token, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-upgrade')
@app.route('/kubernetes-upgrade.sh')
def get_kubernetes_upgrade_master():
    response = render_template(
        'kubernetes-upgrade.sh',
        **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')

@app.route('/kubernetes-node-upgrade')
@app.route('/kubernetes-node-upgrade.sh')
def get_kubernetes_upgrade_worker():
    response = render_template(
        'kubernetes-node-upgrade.sh',
        **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')

@app.route('/kubernetes-init')
@app.route('/kubernetes-init.sh')
@app.route('/<replicated_channel>/kubernetes-init')
@app.route('/<app_slug>/<app_channel>/kubernetes-init')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-init')
def get_kubernetes_init_master(replicated_channel=None,
                               app_slug=None,
                               app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'kubernetes')

    pinned_kubernetes_version = helpers.get_pinned_kubernetes_version(
        replicated_version)

    generate_path = 'kubernetes-yml-generate'
    node_path = 'kubernetes-node-join'
    if app_slug and app_channel:
        generate_path = app_slug + '/' + app_channel + '/' + generate_path
        node_path = app_slug + '/' + app_channel + '/' + node_path
    if replicated_channel and replicated_channel != 'stable':
        generate_path = replicated_channel + '/' + generate_path
        node_path = replicated_channel + '/' + node_path
    query_args = dict(request.args)

    # unpack list args because otherwise we get weird stuff in YAML like
    #    value: '[u'/data/stuff']'
    query_args = {
        k: v[0] if isinstance(v, list) and len(v) > 0 else v
        for k, v in query_args.items()
    }

    query = urllib.urlencode(query_args)
    response = render_template(
        'kubernetes-init.sh',
        **helpers.template_args(
            pinned_docker_version=pinned_docker_version,
            kubernetes_version=pinned_kubernetes_version,
            kubernetes_generate_path=generate_path,
            kubernetes_node_join_path=node_path,
            kubernetes_manifests_query=query, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-node-join')
@app.route('/<replicated_channel>/kubernetes-node-join')
@app.route('/<app_slug>/<app_channel>/kube-node-join')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-node-join')
def get_kubernetes_node_join(replicated_channel=None,
                             app_slug=None,
                             app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel)
    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, 'kubernetes')
    pinned_kubernetes_version = helpers.get_pinned_kubernetes_version(
        replicated_version)

    kubeadm_token = helpers.get_arg('kubeadm_token', '')
    kubeadm_token_ca_hash = helpers.get_arg('kubeadm_token_ca_hash', '')
    kubernetes_master_address = helpers.get_arg('kubernetes_master_address',
                                                '')

    response = render_template(
        'kubernetes-node-join.sh',
        **helpers.template_args(
            pinned_docker_version=pinned_docker_version,
            kubernetes_version=pinned_kubernetes_version,
            kubernetes_master_address=kubernetes_master_address,
            kubeadm_token=kubeadm_token,
            kubeadm_token_ca_hash=kubeadm_token_ca_hash, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/migrate-v2')
def get_replicated_migrate_v2():
    response = render_template('migrate-v2.sh', **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')


@app.route('/utils/aws/ubuntu1404/replicated-init')
def get_replicated_init_aws_ubuntu1404():
    replicated_channel = helpers.get_arg('channel', 'stable')
    response = render_template('replicated-init-aws-ubuntu1404.sh',
                               **helpers.template_args(
                                   channel_name=replicated_channel, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/utils/aws/ubuntu1404/replicated-init.conf')
def get_replicated_upstart_aws_ubuntu1404():
    replicated_channel = helpers.get_arg('channel', 'stable')
    response = render_template('replicated-init-aws-bootstrap.conf',
                               **helpers.template_args(
                                   channel_name=replicated_channel, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/tag/best')
def get_best_docker_tag():
    version_range = helpers.get_arg('version', None)
    if not version_range:
        abort(400)

    replicated_channel = helpers.get_arg('channel', 'stable')
    best_version = helpers.get_best_replicated_version(version_range,
                                                       replicated_channel)
    if not best_version:
        abort(404)

    return best_version


@app.route('/studio')
def get_replicated_studio():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/native.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio-swarm')
def get_replicated_studio_swarm():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/swarm.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio-k8s')
def get_replicated_studio_k8s():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/k8s.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/native')
def get_replicated_studio_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/native-v2.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/swarm')
def get_replicated_studio_swarm_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/swarm-v2.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/k8s')
def get_replicated_studio_k8s_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template('studio/k8s-v2.sh',
                               **helpers.template_args(
                                   studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/compose/ship.yml')
def get_ship_yaml():
    try:
        customer_id = helpers.get_arg('customer_id')
        installation_id = helpers.get_arg('installation_id')
        log_level = helpers.get_arg('log_level', 'off')
        ship_tag = helpers.get_arg('ship_tag', 'alpha')
        ship_console_tag = helpers.get_arg('ship_console_tag', ship_tag)
        headless = helpers.get_arg('headless')

        if not customer_id:
            return helpers.compose_400(
                "Missing or invalid parameters: customer_id")

        customer_exists = helpers.does_customer_exist(customer_id)
        if not customer_exists:
            return helpers.compose_404(
                "Missing or invalid parameters: customer_id")

        response = render_template('ship-install-dynamic.yml',
                                   **helpers.template_args(
                                       customer_id=customer_id,
                                       log_level=log_level,
                                       ship_tag=ship_tag,
                                       ship_console_tag=ship_console_tag,
                                       headless=headless,
                                       installation_id=installation_id, ))

        return Response(response, mimetype='text/x-docker-compose')
    except:
        traceback.print_exc()
        return helpers.compose_500()
