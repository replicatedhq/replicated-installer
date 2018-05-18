from __future__ import print_function

import os


param_cache = {}

def init(sess):
  use_ssm = os.environ['USE_EC2_PARAMETERS'] != ''
  new_param_cache(sess, use_ssm)


def lookup(env_name, ssm_name, **kwargs):
  if not param_cache:
    raise Exception('must initialize param package')

  if not param_cache['ssm'] or not ssm_name:
    return os.environ[env_name]

  cached_val = dict_get(ssm_name)
  if cached_val:
    return cached_val

  val, _ = ssm_get(ssm_name, kwargs.get('decrypt', False))
  if val:
    return val

  return kwargs.get('default', '')


def new_param_cache(sess, use_ssm):
  if use_ssm:
    svc = sess.client('ssm')
  param_cache = {'ssm':svc, 'm':{}}


def ssm_get(ssm_name, decrypt):
  resp = ssm.get_parameters(
    Names=ssm_name,
    WithDecryption=decrypt
  )
  if not resp:
    print('Failed to get ssm param {}'.format(ssm_name))

  if not os.environ['DEBUG'] and resp['InvalidParameters']:
    print('\n'.join(map(str, resp['InvalidParameters'])))

  if not resp['Parameters']:
    return ('', False)

  val = resp['Parameters'][0]['Value']
  dict_set(ssm_name, val)
  return (val, True)


def dict_get(ssm_name):
  return param_cache.get('m').get(ssm_name)


def dict_set(ssm_name, val):
  param_cache.get('m').update({ssm_name:val})
