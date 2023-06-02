from __future__ import print_function

import constant
from flask import Flask, Response, abort, redirect, render_template, request, \
    jsonify
import semver
import subprocess
import sys
import os
import json
import traceback
import urllib
from shellescape import quote
import tempfile

from . import db, helpers, param, images

app = Flask(__name__)

_images = images.get_default_images()

@app.teardown_appcontext
def teardown_db(exception):
    db.teardown()


@app.route('/healthz')
def get_healthz():
    return ''


@app.route('/dbz')
def get_dbz():
    this_db = db.get()
    if this_db is not None:
        return ''
    else:
        return Response('db not found', status=500)


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
    elif major >= 24:
        tmpl_file = 'docker-install/24-0-ce.sh'
    elif major >= 20:
        tmpl_file = 'docker-install/20-10-ce.sh'
    elif major >= 19:
        tmpl_file = 'docker-install/19-03-ce.sh'
    elif major == 18:
        tmpl_file = 'docker-install/18-09-ce.sh'
    elif major == 17 and minor <= 5:
        tmpl_file = 'docker-install/17-03-ce.sh'
    elif major == 17 and minor <= 6:
        tmpl_file = 'docker-install/17-06-ce.sh'
    else:
        tmpl_file = 'docker-install/17-12-ce.sh'
    kwargs = {
        'docker_version': helpers.get_arg('docker_version', ''),
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

    scheduler = helpers.get_arg('scheduler', None)
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    return replicated_version


@app.route('/<path:path>')
def catch_all(path):
    clean_path = quote(path)
    kwargs = helpers.template_args(path=clean_path)
    response = render_template('resolve-route.sh', **kwargs)
    return Response(response, mimetype='text/x-shellscript')


@app.route('/', defaults={'replicated_channel': 'stable'})
@app.route('/stable', defaults={'replicated_channel': 'stable'})
@app.route('/unstable', defaults={'replicated_channel': 'unstable'})
@app.route('/beta', defaults={'replicated_channel': 'beta'})
def get_replicated_one_point_two(replicated_channel):
    kwargs = helpers.template_args(channel_name=replicated_channel)
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
    print('Looking up tags for:', replicated_channel,
          app_slug, app_channel, file=sys.stderr)

    scheduler = constant.SCHEDULER_REPLICATED
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, scheduler)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    # The operator tag is passed into a similar script, so it shouldn't have
    # the channel prefix.
    replicated_operator_tag = replicated_operator_version

    channel_css = ''
    terms = ''
    if app_slug and app_channel:
        channel_css = helpers.get_channel_css(app_slug, app_channel)
        terms = helpers.get_terms(app_slug, app_channel)

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
            channel_name=replicated_channel,
            pinned_docker_version=pinned_docker_version,
            replicated_version=replicated_version,
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
            use_fast_timeouts=fast_timeouts,
            channel_css=helpers.base64_encode(channel_css),
            terms=helpers.base64_encode(terms),
        ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/operator')
@app.route('/<replicated_channel>/operator')
@app.route('/operator/<app_slug>/<app_channel>')
@app.route('/<replicated_channel>/operator/<app_slug>/<app_channel>')
def get_replicated_operator(replicated_channel=None,
                            app_slug=None,
                            app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print('Looking up tags for:', replicated_channel,
          app_slug, app_channel, file=sys.stderr)

    scheduler = constant.SCHEDULER_REPLICATED
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_operator_version, scheduler)

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
            replicated_version=replicated_operator_version,
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

    response = render_template('swarm/docker-compose-generate.sh', **kwargs)
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
        'swarm/docker-compose-generate-safe.sh', suppress_runtime=1, **kwargs)


    with tempfile.NamedTemporaryFile(delete=False) as tmpTemplateConfig:
        json.dump(kwargs, tmpTemplateConfig)
        tmpTemplateConfig.flush()

        p = subprocess.Popen(
            ['/dcg', '--config', tmpTemplateConfig.name],
            shell=False,
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
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    current_replicated_version = helpers.get_arg('current_replicated_version',
                                                 '')
    parsed = semver.parse(current_replicated_version, loose=False)
    if parsed is None:
        abort(400)
    current_kubernetes_version = helpers.get_pinned_kubernetes_version(
        current_replicated_version)

    scheduler = None
    # scheduler-less releases prior to 2.38.0
    if semver.gte(current_replicated_version, '2.38.0', loose=False):
        scheduler = constant.SCHEDULER_KUBERNETES
    next_replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    next_replicated_version = helpers.get_arg('next_replicated_version',
                                              next_replicated_version)

    next_kubernetes_version = helpers.get_pinned_kubernetes_version(
        next_replicated_version)

    body = {
        'compatible': current_kubernetes_version == next_kubernetes_version
    }

    return jsonify(body)

@app.route('/kubernetes-images.json')
def get_kubernetes_images():
    return jsonify(_images)

@app.route('/kubernetes/deploy.yml')
@app.route('/<replicated_channel>/kubernetes/deploy.yml')
@app.route('/<app_slug>/<app_channel>/kubernetes/deploy.yml')
def get_replicated_kubernetes_yml(replicated_channel=None,
                                  app_slug=None,
                                  app_channel=None):
    kwargs = get_kubernetes_yaml_template_args(replicated_channel, app_slug,
                                               app_channel)

    script = render_template(
        'kubernetes/yml-generate.sh', suppress_runtime=1, **kwargs)
    p = subprocess.Popen(
        ['bash -s deployment-yaml=1', '-'],
        shell=False,
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


@app.route('/kubernetes/operator.yml')
@app.route('/<replicated_channel>/kubernetes/operator.yml')
@app.route('/<app_slug>/<app_channel>/kubernetes/operator.yml')
def get_kubernetes_operator_yml(replicated_channel=None,
                                app_slug=None,
                                app_channel=None):
    kwargs = get_kubernetes_yaml_template_args(replicated_channel, app_slug,
                                               app_channel)

    script = render_template(
        'kubernetes/yml-generate.sh', suppress_runtime=1, **kwargs)
    p = subprocess.Popen(
        ['bash -s rek-operator-yaml=1', '-'],
        shell=False,
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
    print('Looking up tags for:', replicated_channel,
          app_slug, app_channel, file=sys.stderr)

    scheduler = constant.SCHEDULER_SWARM
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, scheduler)

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
    # Replicated versions at or later than 2.22.0 use replicated_default
    # overlay network for snapshots
    snapshots_use_overlay = helpers.snapshots_use_overlay(replicated_version)

    airgap = helpers.get_arg('airgap', '')
    ca = helpers.get_arg('ca', '')
    cert = helpers.get_arg('cert', '')
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
    http_proxy = helpers.get_arg('http_proxy', '')
    no_proxy_addresses = helpers.get_arg('no_proxy_addresses', '')

    customer_base_url = helpers.get_arg('customer_base_url')

    return helpers.template_args(
        channel_name=replicated_channel,
        pinned_docker_version=pinned_docker_version,
        replicated_version=replicated_version,
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
        cert=cert,
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
        http_proxy=http_proxy,
        no_proxy_addresses=no_proxy_addresses,
        customer_base_url_override=customer_base_url,
        snapshots_use_overlay=snapshots_use_overlay,
    )


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
    print('Looking up tags for:', replicated_channel,
          app_slug, app_channel, file=sys.stderr)

    scheduler = constant.SCHEDULER_SWARM
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

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
        tmpl_file = 'swarm/docker-compose-v2-legacy.yml'
    else:
        tmpl_file = 'swarm/docker-compose-v2.yml'
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
            ui_bind_port=ui_bind_port,
        ))

    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')


def get_kubernetes_yaml_template_args(replicated_channel=None,
                                      app_slug=None,
                                      app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    print('Looking up tags for:', replicated_channel,
          app_slug, app_channel, file=sys.stderr)

    scheduler = constant.SCHEDULER_KUBERNETES
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_ui_version = helpers.get_replicated_ui_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    replicated_operator_version = helpers.get_replicated_operator_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    replicated_tag = '{}-{}'.format(replicated_channel, replicated_version)
    replicated_ui_tag = '{}-{}'.format(replicated_channel,
                                       replicated_ui_version)
    replicated_operator_tag = '{}-{}'.format(replicated_channel,
                                             replicated_operator_version)

    storage_provisioner = helpers.get_arg('storage_provisioner', 'rook')
    pv_base_path = helpers.get_arg('pv_base_path', '')
    log_level = helpers.get_arg('log_level', 'info')
    storage_class = helpers.get_arg('storage_class', 'default')
    service_type = helpers.get_arg('service_type', 'NodePort')
    kubernetes_namespace = helpers.get_arg('kubernetes_namespace', 'default')
    ui_bind_port = helpers.get_arg('ui_bind_port', 8800)
    customer_base_url = helpers.get_arg('customer_base_url')
    proxy_address = helpers.get_arg('http_proxy', '')
    # 10.96.0.0/12 is the default service cidr
    no_proxy_addresses = helpers.get_arg('no_proxy_addresses', '10.96.0.0/12')
    api_service_address = helpers.get_arg('api_service_address', '')
    ha_cluster = '1' if helpers.get_arg('ha_cluster') == 'true' else '0'
    purge_dead_nodes = '1' if helpers.get_arg(
        'purge_dead_nodes') == 'true' else '0'
    maintain_rook_storage_nodes = '1' if helpers.get_arg(
        'maintain_rook_storage_nodes') == 'true' else '0'
    app_registry_advertise_host = helpers.get_arg(
        'app_registry_advertise_host', '')

    return helpers.template_args(
        channel_name=replicated_channel,
        replicated_version=replicated_version,
        replicated_tag=replicated_tag,
        replicated_ui_tag=replicated_ui_tag,
        replicated_operator_tag=replicated_operator_tag,
        pv_base_path=pv_base_path,
        log_level=log_level,
        storage_provisioner=storage_provisioner,
        storage_class=storage_class,
        service_type=service_type,
        kubernetes_namespace=kubernetes_namespace,
        ui_bind_port=ui_bind_port,
        customer_base_url_override=customer_base_url,
        proxy_address=proxy_address,
        no_proxy_addresses=no_proxy_addresses,
        api_service_address=api_service_address,
        ha_cluster=ha_cluster,
        purge_dead_nodes=purge_dead_nodes,
        maintain_rook_storage_nodes=maintain_rook_storage_nodes,
        app_registry_advertise_host=app_registry_advertise_host,
    )


@app.route('/kubernetes-yml-generate')
@app.route('/kubernetes-yml-generate.sh')
@app.route('/<replicated_channel>/kubernetes-yml-generate')
@app.route('/<app_slug>/<app_channel>/kubernetes-yml-generate')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-yml-generate')
def get_replicated_kubernetes(replicated_channel=None,
                              app_slug=None,
                              app_channel=None):
    kwargs = get_kubernetes_yaml_template_args(replicated_channel, app_slug,
                                               app_channel)

    response = render_template('kubernetes/yml-generate.sh', **kwargs)

    if helpers.get_arg('accept', None) == 'text':
        return Response(response, mimetype='text/plain')
    return Response(response, mimetype='application/x-yaml')


@app.route('/swarm-init')
@app.route('/<replicated_channel>/swarm-init')
@app.route('/<app_slug>/<app_channel>/swarm-init')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/swarm-init')
def get_swarm_init_primary(replicated_channel=None,
                           app_slug=None,
                           app_channel=None):
    return helpers.error_script(status=404,
        error_message="Swarm is no longer supported. For more information see https://docs.replicated.com/vendor/distributing-workflow")


@app.route('/swarm-worker-join')
@app.route('/<replicated_channel>/swarm-worker-join')
@app.route('/<app_slug>/<app_channel>/swarm-worker-join')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/swarm-worker-join')
@app.route('/swarm-join')
@app.route('/<replicated_channel>/swarm-join')
@app.route('/<app_slug>/<app_channel>/swarm-join')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/swarm-join')
def get_swarm_init_worker(replicated_channel=None,
                          app_slug=None,
                          app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'

    scheduler = constant.SCHEDULER_SWARM
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, scheduler)
    swarm_manager_address = helpers.get_arg('swarm_manager_address')
    if swarm_manager_address == '':
        swarm_manager_address = helpers.get_arg('swarm_master_address')
    swarm_token = helpers.get_arg('swarm_token')
    username = helpers.get_replicated_username_swarm(replicated_version)
    response = render_template(
        'swarm/worker-join.sh',
        **helpers.template_args(
            pinned_docker_version=pinned_docker_version,
            swarm_manager_address=swarm_manager_address,
            swarm_token=swarm_token,
            replicated_username=username,
        ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-node-upgrade')
@app.route('/kubernetes-node-upgrade.sh')
@app.route('/<replicated_channel>/kubernetes-node-upgrade')
def get_kubernetes_upgrade_secondary(replicated_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'

    scheduler = constant.SCHEDULER_KUBERNETES
    replicated_version = helpers.get_replicated_version(
        replicated_channel, None, None, scheduler=scheduler)

    pinned_kubernetes_version = helpers.get_pinned_kubernetes_version(
        replicated_version)
    kubernetes_version = helpers.get_arg('kubernetes_version',
                                         pinned_kubernetes_version)

    response = render_template(
        'kubernetes/node-upgrade.sh',
        **helpers.template_args(kubernetes_version=kubernetes_version, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-update-apiserver-certs')
@app.route('/kubernetes-update-apiserver-certs.sh')
@app.route('/<replicated_channel>/kubernetes-update-apiserver-certs')
def get_kubernetes_update_apiserver_certs(replicated_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'

    response = render_template(
        'kubernetes/update-apiserver-certs.sh',
        **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-migrate')
@app.route('/kubernetes-migrate.sh')
@app.route('/<replicated_channel>/kubernetes-migrate')
@app.route('/<app_slug>/<app_channel>/kubernetes-migrate')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-migrate')
def get_kubernetes_migrate(replicated_channel=None,
                           app_slug=None,
                           app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'
    # use app_channel to lookup replicated version, but don't add to
    # init script because we don't want terms and branding

    scheduler = constant.SCHEDULER_KUBERNETES
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    init_path = 'kubernetes-init'
    if replicated_channel != 'stable':
        init_path = replicated_channel + '/' + init_path

    query_args = dict(request.args)
    # unpack list args because otherwise we get weird stuff in YAML like
    #    value: '[u'/data/stuff']'
    query_args = {
        k: v[0] if isinstance(v, list) and len(v) > 0 else v
        for k, v in query_args.items()
    }
    query_args['replicated_tag'] = query_args.get(
        'replicated_tag', replicated_version)
    query = urllib.urlencode(query_args)

    response = render_template(
        'kubernetes/migrate.sh',
        **helpers.template_args(
            replicated_version=replicated_version,
            kubernetes_init_path=init_path,
            kubernetes_init_query=query,
        ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/kubernetes-init')
@app.route('/kubernetes-init.sh')
@app.route('/<replicated_channel>/kubernetes-init')
@app.route('/<app_slug>/<app_channel>/kubernetes-init')
@app.route('/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-init')
def get_kubernetes_init_primary(replicated_channel=None,
                                app_slug=None,
                                app_channel=None):
    return helpers.error_script(status=404,
        error_message="This installation method is no longer supported. For ditributing applications using Kubernetes see https://docs.replicated.com/vendor/distributing-workflow")


@app.route('/kubernetes-node-join')
@app.route('/<replicated_channel>/kubernetes-node-join')
@app.route('/<app_slug>/<app_channel>/kube-node-join')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/kubernetes-node-join')
def get_kubernetes_node_join(replicated_channel=None,
                             app_slug=None,
                             app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'

    scheduler = constant.SCHEDULER_KUBERNETES
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)

    pinned_docker_version = helpers.get_pinned_docker_version(
        replicated_version, scheduler)
    pinned_kubernetes_version = helpers.get_pinned_kubernetes_version(
        replicated_version)
    kubernetes_version = helpers.get_arg('kubernetes_version',
                                         pinned_kubernetes_version)

    kubeadm_token = helpers.get_arg('kubeadm_token', '')
    kubeadm_token_ca_hash = helpers.get_arg('kubeadm_token_ca_hash', '')
    kubernetes_primary_address = helpers.get_arg('kubernetes_primary_address',
                                                 '')
    if kubernetes_primary_address == '':
        kubernetes_primary_address = helpers.get_arg(
            'kubernetes_master_address', '')

    response = render_template(
        'kubernetes/node-join.sh',
        **helpers.template_args(
            pinned_docker_version=pinned_docker_version,
            kubernetes_version=kubernetes_version,
            kubernetes_primary_address=kubernetes_primary_address,
            kubeadm_token=kubeadm_token,
            kubeadm_token_ca_hash=kubeadm_token_ca_hash,
        ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/migrate-v2')
def get_replicated_migrate_v2():
    response = render_template('migrate-v2.sh', **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')


@app.route('/utils/aws/ubuntu1404/replicated-init')
def get_replicated_init_aws_ubuntu1404():
    replicated_channel = helpers.get_arg('channel', 'stable')
    response = render_template(
        'replicated-init-aws-ubuntu1404.sh',
        **helpers.template_args(channel_name=replicated_channel, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/utils/aws/ubuntu1404/replicated-init.conf')
def get_replicated_upstart_aws_ubuntu1404():
    replicated_channel = helpers.get_arg('channel', 'stable')
    response = render_template(
        'replicated-init-aws-bootstrap.conf',
        **helpers.template_args(channel_name=replicated_channel, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/tag/best')
def get_best_docker_tag():
    version_range = helpers.get_arg('version', None)
    if not version_range:
        abort(400)

    replicated_channel = helpers.get_arg('channel', 'stable')
    scheduler = helpers.get_arg('scheduler', None)
    best_version = helpers.get_best_replicated_version(version_range,
                                                       replicated_channel,
                                                       scheduler=scheduler)
    if not best_version:
        abort(404)

    return best_version


@app.route('/airgap')
@app.route('/<replicated_channel>/airgap')
@app.route('/<app_slug>/<app_channel>/airgap')
@app.route(
    '/<replicated_channel>/<app_slug>/<app_channel>/airgap')
def get_airgap_bundle(replicated_channel=None,
                      app_slug=None,
                      app_channel=None):
    replicated_channel = replicated_channel if replicated_channel else 'stable'

    scheduler = helpers.get_arg('scheduler', None)
    replicated_version = helpers.get_replicated_version(
        replicated_channel, app_slug, app_channel, scheduler=scheduler)
    current_replicated_version = helpers.get_current_replicated_version(
        replicated_channel, scheduler=scheduler)

    bucket = 'replicated-airgap-work'
    env = param.lookup('ENVIRONMENT', default='production')
    if env == 'staging':
        bucket = 'replicated-airgap-work-staging'

    if replicated_version == current_replicated_version:
        file_suffix = ''
        if replicated_channel == 'beta':
            file_suffix = '-beta'
        elif replicated_channel == 'unstable':
            file_suffix = '-unstable'

        file = 'replicated{}.tar.gz'.format(file_suffix)
        if scheduler == 'kubernetes':
            file = 'replicated{}__docker__kubernetes.tar.gz'.format(
                file_suffix)

        url = 'https://s3.amazonaws.com/{}/{}'.format(bucket, file)
        return redirect(url, code=302)
    else:
        file_suffix = '-{0}%2B{0}%2B{0}'.format(replicated_version)
        file = 'replicated{}.tar.gz'.format(file_suffix)
        url = 'https://s3.amazonaws.com/{}/{}/{}'.format(
            bucket, replicated_channel, file)
        return redirect(url, code=302)


@app.route('/preflights')
def preflights():
    response = render_template(
        'preflights.sh',
        **helpers.template_args())
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio')
def get_replicated_studio():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/native.sh',
        **helpers.template_args(studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio-swarm')
def get_replicated_studio_swarm():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/swarm.sh',
        **helpers.template_args(studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio-k8s')
def get_replicated_studio_k8s():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/k8s.sh', **helpers.template_args(
            studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/native')
def get_replicated_studio_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/native-v2.sh',
        **helpers.template_args(studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/swarm')
def get_replicated_studio_swarm_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/swarm-v2.sh',
        **helpers.template_args(studio_base_path=studio_path, ))
    return Response(response, mimetype='text/x-shellscript')


@app.route('/studio/k8s')
def get_replicated_studio_k8s_v2():
    studio_path = helpers.get_arg('studio_base_path', '$HOME')
    response = render_template(
        'studio/k8s-v2.sh',
        **helpers.template_args(studio_base_path=studio_path, ))
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
                'Missing or invalid parameters: customer_id')

        customer_exists = helpers.does_customer_exist(customer_id)
        if not customer_exists:
            return helpers.compose_404(
                'Missing or invalid parameters: customer_id')

        response = render_template(
            'ship-install-dynamic.yml',
            **helpers.template_args(
                customer_id=customer_id,
                log_level=log_level,
                ship_tag=ship_tag,
                ship_console_tag=ship_console_tag,
                headless=headless,
                installation_id=installation_id,
            ))

        return Response(response, mimetype='text/x-docker-compose')
    except:
        traceback.print_exc()
        return helpers.compose_500()
