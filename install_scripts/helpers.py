from __future__ import print_function

import base64
import json
import sys
import yaml

import semver
from flask import request, render_template, Response

from . import db, param

_default_docker_version = '18.09.2'


def template_args(**kwargs):
    args = {
        'pinned_docker_version':
        get_default_docker_version(),
        'min_docker_version':
        param.lookup(
            'MIN_DOCKER_VERSION',
            '/install_scripts/min_docker_version',
            default='1.7.1'),
        'replicated_env':
        param.lookup(
            'ENVIRONMENT', '/replicated/environment', default='production'),
        'environment_tag_suffix':
        get_environment_tag_suffix(
            param.lookup(
                'ENVIRONMENT', '/replicated/environment',
                default='production')),
        'replicated_install_url':
        param.lookup(
            'REPLICATED_INSTALL_URL',
            '/replicated/installer_url',
            default='https://get.replicated.com'),
        'replicated_prem_graphql_endpoint':
        param.lookup(
            'GRAPHQL_PREM_ENDPOINT',
            '/graphql/prem_endpoint',
            default='https://pg.replicated.com/graphql'),
        'replicated_registry_endpoint':
        param.lookup(
            'REGISTRY_ENDPOINT',
            '/registry_v2/advertise_address',
            default='registry.replicated.com'),
        'replicated_docker_host':
        param.lookup(
            'REPLICATED_DOCKER_HOST',
            '/replicated/docker_host',
            default='quay.io'),
    }
    if get_arg('replicated_env') in ('staging', 'production'):
        args['replicated_env'] = get_arg('replicated_env')
    if get_arg('no-ce-on-ee', get_arg('no_ce_on_ee')) is not None:
        args['no_ce_on_ee'] = True
    if get_arg('hard_fail_on_loopback') is not None:
        args['hard_fail_on_loopback'] = True
    if get_arg('hard_fail_on_firewalld') is not None:
        args['hard_fail_on_firewalld'] = True
    if get_arg('disable_contour') is not None:
        args['disable_contour'] = True
    if get_arg('no_clear') is not None:
        args['no_clear'] = True
    if kwargs:
        args.update(kwargs)
    return args


def get_arg(name, dflt=None):
    return request.args.get(name) if request.args.get(name) else dflt


def get_pinned_docker_version(replicated_version, scheduler):
    version_info = semver.parse(replicated_version, loose=False)
    cursor = db.get().cursor()
    query = (
        'SELECT dockerversion '
        'FROM pinned_docker_version '
        'WHERE scheduler = %s AND ( '
        '  (major < %s) OR '
        '  (major = %s AND minor < %s) OR '
        '  (major = %s AND minor = %s AND patch <= %s) '
        ')'
        'ORDER BY major DESC, minor DESC, patch DESC '
        'LIMIT 1')
    cursor.execute(query, (
        scheduler,
        version_info.major,
        version_info.major, version_info.minor,
        version_info.major, version_info.minor, version_info.patch,
    ))

    (docker_version, ) = cursor.fetchone()
    cursor.close()

    if docker_version == 'default':
        return get_default_docker_version()  # fall back to this if default
    return docker_version


def get_pinned_kubernetes_version(replicated_version):
    version_info = semver.parse(replicated_version, loose=False)
    cursor = db.get().cursor()
    query = (
        'SELECT kubernetes_version '
        'FROM pinned_kubernetes_version '
        'WHERE ( '
        '  (major < %s) OR '
        '  (major = %s AND minor < %s) OR '
        '  (major = %s AND minor = %s AND patch <= %s) '
        ')'
        'ORDER BY major DESC, minor DESC, patch DESC '
        'LIMIT 1')
    cursor.execute(query, (
        version_info.major,
        version_info.major, version_info.minor,
        version_info.major, version_info.minor, version_info.patch,
    ))
    (kubernetes_version, ) = cursor.fetchone()
    cursor.close()

    return kubernetes_version


def get_default_docker_version():
    return param.lookup(
        'PINNED_DOCKER_VERSION',
        '/install_scripts/pinned_docker_version',
        default=_default_docker_version)


def get_replicated_version(replicated_channel, app_slug, app_channel,
                           scheduler=None):
    return get_best_version('replicated_tag', None, replicated_channel,
                            app_slug, app_channel, scheduler=scheduler)


def get_replicated_ui_version(replicated_channel, app_slug, app_channel,
                              scheduler=None):
    return get_best_version('replicated_ui_tag', 'replicated_tag',
                            replicated_channel, app_slug, app_channel,
                            scheduler=scheduler)


def get_replicated_operator_version(replicated_channel, app_slug, app_channel,
                                    scheduler=None):
    return get_best_version('replicated_operator_tag', 'replicated_tag',
                            replicated_channel, app_slug, app_channel,
                            scheduler=scheduler)


def get_best_version(arg_name, default_arg_name, replicated_channel, app_slug,
                     app_channel, scheduler=None):
    if app_slug and app_channel:
        app_version = get_version_for_app(app_slug, app_channel,
                                          replicated_channel,
                                          scheduler=scheduler)
        if app_version:
            return app_version

    arg_version = get_arg(arg_name, get_arg(default_arg_name, None))
    if arg_version:
        # versions were different between products
        if semver.lt(arg_version, '2.1.0', loose=False):
            return arg_version
        # this only checks replicated_v2 product version
        if (replicated_channel == 'stable' and
                get_arg('build', '') == 'prestable'):
            # prestable builds use beta channel version
            if is_valid_replicated_version(arg_version, 'beta',
                                           scheduler=scheduler):
                return arg_version
        elif is_valid_replicated_version(arg_version, replicated_channel,
                                         scheduler=scheduler):
            return arg_version
        raise Exception('version {} does not exist'.format(arg_version))

    return get_current_replicated_version(replicated_channel,
                                          scheduler=scheduler)


def get_replicated_username(version_tag):
    if semver.lt(version_tag, '2.5.0', loose=False):
        return 'root'
    return 'replicated'


def get_replicated_username_swarm(version_tag):
    if semver.lt(version_tag, '2.32.0', loose=False):
        return 'root'
    return 'replicated'


def get_port_range(replicated_tag):
    if semver.lt(replicated_tag, '2.0.1654', loose=False):
        return '9874-9880:9874-9880/tcp'
    return '9874-9879:9874-9879/tcp'


def get_premkit_data_dir(replicated_tag):
    if semver.lt(replicated_tag, '2.13.0', loose=False):
        return '/premkit/data'
    elif semver.lt(replicated_tag, '2.13.1', loose=False):
        return '/tmp/premkit-data'
    return ''


def get_root_volume_mount(version_tag):
    if semver.lt(version_tag, '2.1.0-alpha', loose=False):
        return '-v /:/replicated/host:ro'
    return ''


def get_additional_etc_mounts(version_tag):
    if semver.lt(version_tag, '2.5.0', loose=False):
        return ('-v /etc/replicated.conf:/etc/replicated.conf '
                '-v /etc/replicated.alias:/etc/replicated.alias '
                '-v /etc/docker/certs.d:/host/etc/docker/certs.d')
    return ''


def get_operator_additional_etc_mounts(version_tag):
    if semver.lt(version_tag, '2.5.0', loose=False):
        return '-v /etc/docker/certs.d:/host/etc/docker/certs.d'
    return ''


def get_version_for_app(app_slug, app_channel, replicated_channel,
                        scheduler=None):
    version_range = None
    for doc in get_app_version_config(app_slug, app_channel):
        if not doc or 'host_requirements' not in doc:
            continue
        host_requirements = doc['host_requirements']
        if (not host_requirements
                or 'replicated_version' not in host_requirements):
            continue
        version_range = host_requirements['replicated_version']
        break

    if not version_range:
        return None

    return get_best_replicated_version(version_range, replicated_channel,
                                       scheduler=scheduler)


def get_terms(app_slug, app_channel):
    for doc in get_app_version_config(app_slug, app_channel):
        if not doc:
            continue
        terms = doc.get('terms')
        if terms is not None:
            if terms.get('markdown', '') != '':
                return json.dumps(terms)
            break
    return ''


def get_app_version_config(app_slug, app_channel):

    # kubernetes and swarm yaml is not valid yaml
    def handle_iter_exc(gen):
        while True:
            try:
                yield next(gen)
            except StopIteration:
                raise
            except Exception as exc:
                print('Invalid yaml: {}:'.format(exc), file=sys.stderr)

    cursor = db.get().cursor()
    query = ('SELECT ar.config '
             'FROM app a '
             '   INNER JOIN app_channel ac ON a.appid = ac.appid '
             '   INNER JOIN app_release ar ON a.appid = ar.appid '
             '      AND ac.releasesequence = ar.sequence '
             'WHERE a.slug = %s AND ac.name = %s AND ac.is_archived = 0 '
             'LIMIT 1')
    cursor.execute(query, (app_slug, app_channel))
    row = cursor.fetchone()
    cursor.close()
    if row is None:
        return []
    (config_raw, ) = row
    return [
        doc for doc in handle_iter_exc(
            yaml.load_all(base64.b64decode(config_raw)))
    ]


def get_current_replicated_version(replicated_channel, scheduler=None):
    cursor = db.get().cursor()
    product = 'replicated_v2'
    if not scheduler:
        query = ('SELECT version '
                 'FROM product_version_channel_release '
                 'WHERE product = %s AND channel = %s')
        cursor.execute(query, (
            product, replicated_channel,
        ))
    else:
        # select the default if the scheduler row does not exist
        query = ('SELECT version '
                 'FROM product_version_channel_release '
                 'WHERE (product = %s OR product = %s) AND channel = %s '
                 'ORDER BY FIELD(product, %s, %s) '
                 'LIMIT 1')
        cursor.execute(query, (
            product + '-' + scheduler, product,
            replicated_channel,
            product + '-' + scheduler, product,
        ))
    row = cursor.fetchone()
    cursor.close()
    if row is None:
        raise Exception('no releases for product {} and channel {}'.format(
            product, replicated_channel))
    (version, ) = row

    print('Current Replicated version for {}: {}'.format(
        replicated_channel, version), file=sys.stderr)
    return version


def get_best_replicated_version(version_range, replicated_channel,
                                scheduler=None):

    # we do not make scheduler-less releases past 2.37
    if not scheduler and semver.ltr('2.37.99', version_range, loose=False):
        return get_current_replicated_version(replicated_channel,
                                              scheduler=None)

    cursor = db.get().cursor()
    product = 'replicated_v2'
    if not scheduler:
        query = ('SELECT version '
                 'FROM product_version_channel_release_history '
                 'WHERE product = %s AND channel = %s')
        cursor.execute(query, (product, replicated_channel))
    if scheduler:
        # select the default if the scheduler row does not exist
        query = ('SELECT version '
                 'FROM product_version_channel_release_history '
                 'WHERE (product = %s OR product = %s) AND channel = %s')
        cursor.execute(query, (
            product + '-' + scheduler, product,
            replicated_channel,
        ))

    best_v = semver.max_satisfying(
        version_list_generator(cursor), version_range, loose=False)
    cursor.close()

    print('Best matching Replicated version for {}: {}'.format(
        version_range, best_v), file=sys.stderr)
    return best_v


def is_valid_replicated_version(version, replicated_channel, scheduler=None):
    cursor = db.get().cursor()
    product = 'replicated_v2'
    if not scheduler:
        query = ('SELECT version '
                 'FROM product_version_channel_release_history '
                 'WHERE product = %s AND channel = %s AND version = %s '
                 'LIMIT 1')
        cursor.execute(query, (product, replicated_channel, version))
    if scheduler:
        # select the default if the scheduler row does not exist
        query = ('SELECT version '
                 'FROM product_version_channel_release_history '
                 'WHERE (product = %s OR product = %s) AND '
                 '  channel = %s AND version = %s '
                 'LIMIT 1')
        cursor.execute(query, (
            product + '-' + scheduler, product,
            replicated_channel, version,
        ))
    row = cursor.fetchone()
    cursor.close()
    if row is None:
        return False
    return True


def version_list_generator(cursor):
    for (version, ) in cursor:
        try:
            semver.make_semver(version, loose=False)
            yield version
        except Exception as exc:
            print('Skipping {}: {}'.format(version, exc), file=sys.stderr)
            continue


def get_channel_css(app_slug, app_channel):
    cursor = db.get().cursor()
    query = ('SELECT acb.css '
             'FROM app a '
             '   INNER JOIN app_channel ac ON a.appid = ac.appid '
             '   INNER JOIN app_channel_branding acb '
             '       ON acb.channelid = ac.channelid '
             'WHERE a.slug = %s AND ac.name = %s AND ac.is_archived = 0 '
             'LIMIT 1')
    cursor.execute(query, (app_slug, app_channel))
    row = cursor.fetchone()
    cursor.close()

    if row:
        return row[0]
    return ''


def does_customer_exist(customer_id):
    cursor = db.get().cursor()
    query = ('SELECT id ' 'FROM customer ' 'WHERE id = %s')
    cursor.execute(query, (customer_id, ))
    row = cursor.fetchone()
    cursor.close()

    if row:
        return True
    return False


# Produce base64 encoding with linebreaks.
def base64_encode(data):
    encoded = base64.b64encode(data)
    return '\n'.join(
        encoded[pos:pos + 76] for pos in xrange(0, len(encoded), 76))


def get_docker_deb_pkg_version(docker_version, lsb_dist, dist_version):
    major, minor, patch = map(int, docker_version.split('.'))
    if major == 18:
        return ''  # unused
    elif major == 1:
        if minor < 12 or (minor == 12 and patch <= 3):
            return '{}-0~${{dist_version}}'.format(docker_version)
        return '{}-0~${{lsb_dist}}-${{dist_version}}'.format(docker_version)
    elif major == 17:
        if minor <= 5:
            return '{}~ce-0~${{lsb_dist}}-${{dist_version}}'.format(
                docker_version)
        return '{}~ce-0~${{lsb_dist}}'.format(docker_version)
    # if docker version is unknown lets just return default version
    return get_docker_deb_pkg_version(get_default_docker_version(), lsb_dist,
                                      dist_version)


def get_docker_rpm_pkg_version(docker_version, lsb_dist, dist_version):
    major, minor, _ = map(int, docker_version.split('.'))
    if major == 18:
        return ''  # unused
    elif major == 1:
        if lsb_dist == 'ol' or (lsb_dist in ('centos', 'rhel')
                                and dist_version == '6'):
            return '{}-1.el${{dist_version}}'.format(docker_version)
        return '{}-1.el${{dist_version}}.centos'.format(docker_version)
    elif major == 17:
        if lsb_dist == 'ol' and minor <= 5:
            return '{}.ce-1.el${{dist_version}}'.format(docker_version)
        elif lsb_dist == 'fedora':
            return '{}.ce-1.fc${{dist_version}}'.format(docker_version)
        return '{}.ce-1.el${{dist_version}}.centos'.format(docker_version)
    # if docker version is unknown lets just return default version
    return get_docker_rpm_pkg_version(get_default_docker_version(), lsb_dist,
                                      dist_version)


def get_environment_tag_suffix(env):
    if env == 'staging':
        return '.staging'
    return ''


def compose_400(error_message='Bad Request'):
    response = render_template(
        'error/compose_400.yml',
        **template_args(
            error_message=error_message,
            base_url=request.base_url,
        ))
    return Response(response, status=400, mimetype='text/x-docker-compose')


def compose_404(error_message='Not Found'):
    response = render_template(
        'error/compose_404.yml',
        **template_args(
            error_message=error_message,
            base_url=request.base_url,
        ))
    return Response(response, status=404, mimetype='text/x-docker-compose')


def compose_500():
    response = render_template('error/compose_500.yml',
                               **template_args(base_url=request.base_url, ))
    return Response(response, status=500, mimetype='text/x-docker-compose')


def snapshots_use_overlay(replicated_version):
    if semver.lt(replicated_version, '2.22.0', loose=False):
        return False
    return True
