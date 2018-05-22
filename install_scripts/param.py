from __future__ import print_function

import os


param_cache = {}

def init(sess):
  use_ssm = os.getenv('USE_EC2_PARAMETERS') != ''
  new_param_cache(sess, use_ssm)


def lookup(env_name, ssm_name, **kwargs):
  if not param_cache:
    raise Exception('must initialize param package')

  if not param_cache['ssm'] or not ssm_name:
    return os.getenv(env_name, kwargs.get('default', ''))

  cached_val = dict_get(ssm_name)
  if cached_val:
    return cached_val

  val, ok = ssm_get(ssm_name, kwargs.get('decrypt', False))
  return val if ok else kwargs.get('default', '')


def new_param_cache(sess, use_ssm):
  global param_cache
  if use_ssm:
    svc = sess.client('ssm')
  param_cache = {'ssm': svc, 'm': {}}


def ssm_get(ssm_name, decrypt):
  resp = ssm.get_parameters(
    Names=ssm_name,
    WithDecryption=decrypt
  )
  if not resp:
    print('Failed to get ssm param {}'.format(ssm_name))
    return ('', False)

  if os.getenv('DEBUG') and resp['InvalidParameters']:
    print('\n'.join(map(str, resp['InvalidParameters'])))

  if not resp.get('Parameters') or len(resp.get('Parameters')) == 0:
    return ('', False)

  val = resp['Parameters'][0]['Value']
  dict_set(ssm_name, val)
  return (val, True)


def dict_get(ssm_name):
  return param_cache.get('m').get(ssm_name)


def dict_set(ssm_name, val):
  param_cache.get('m').update({ssm_name:val})
