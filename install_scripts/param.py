from __future__ import print_function

import boto3
import os
import sys

param_cache = None

param_lookup = {
    'ENVIRONMENT': '/replicated/environment',
    'GRAPHQL_PREM_ENDPOINT': '/graphql/prem_endpoint',
    'MIN_DOCKER_VERSION': '/install_scripts/min_docker_version',
    'MYSQL_DATABASE': '/mysql/database',
    'MYSQL_DB': '/mysql/database',
    'MYSQL_PASSWORD': '/install_scripts/mysql_password',
    'MYSQL_PASS': '/install_scripts/mysql_password',
    'MYSQL_HOST': '/mysql/host',
    'MYSQL_PORT': '/mysql/port',
    'MYSQL_USER': '/install_scripts/mysql_user',
    'NOT_FOUND': '/blah/blah',  # why not just to make sure
    'PINNED_DOCKER_VERSION': '/install_scripts/pinned_docker_version',
    'PINNED_KUBERNETES_VERSION': '/install_scripts/pinned_kubernetes_version',
    'REGISTRY_ENDPOINT': '/registry_v2/advertise_address',
    'REPLICATED_INSTALL_URL': '/replicated/installer_url',
}


class ParamCache:
    def __init__(self, ssm):
        self.ssm = ssm
        self.m = {}


def init():
    use_ssm = os.getenv("USE_EC2_PARAMETERS", '') != ''
    new_param_cache(use_ssm)
    if use_ssm:
        for env_name, val in get_parameters_from_ssm().items():
            dict_set(env_name, val)


def lookup(env_name, **kwargs):
    if param_cache is None:
        raise Exception('must initialize param cache')

    cached_val = dict_get(env_name)
    if cached_val:
        return cached_val

    return os.getenv(env_name, kwargs.get('default', ''))


def new_param_cache(use_ssm):
    global param_cache
    svc = None
    if use_ssm:
        print("Param is using SSM", file=sys.stderr)
        sess = boto3.session.Session(
            region_name=os.getenv('AWS_REGION', 'us-east-1'))
        svc = sess.client('ssm')
    param_cache = ParamCache(svc)


def get_parameters_from_ssm():
    ssm_names = []
    params = {}
    reverseLookup = {}

    for env_name, ssm_name in param_lookup.items():
        if ssm_name != "":
            ssm_names.append(ssm_name)
            reverseLookup[ssm_name] = env_name

    for names in list(chunk(ssm_names, 10)):
        output = param_cache.ssm.get_parameters(
            Names=names,
            WithDecryption=True, )

        for name in output['InvalidParameters']:
            print("Ssm param {} invalid".format(name), file=sys.stderr)

        for param in output['Parameters']:
            params[reverseLookup[param['Name']]] = param['Value']

    return params


def dict_get(env_name):
    return param_cache.m.get(env_name)


def dict_set(env_name, val):
    param_cache.m.update({env_name: val})


def chunk(l, n):
    for i in range(0, len(l), n):
        yield l[i:i + n]
