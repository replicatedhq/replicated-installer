from __future__ import print_function

import os
import boto3

from botocore.exceptions import ClientError

param_cache = {}

def init(sess):
  use_ssm = os.getenv('USE_EC2_PARAMETERS')
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
  svc = None
  if use_ssm:
    svc = sess.client('ssm')
  param_cache = {'ssm': svc, 'm': {}}


def ssm_get(ssm_name, decrypt):
  try:
    resp = param_cache.get('ssm').get_parameter(
      Name=ssm_name,
      WithDecryption=decrypt
    )
  except ClientError as e:
    if e.response['Error']['Code'] == 'ParameterNotFound':
      return ('', False)
    raise e

  if not resp.get('Parameter'):
    return ('', False)

  val = resp['Parameter']['Value']
  dict_set(ssm_name, val)
  return (val, True)


def dict_get(ssm_name):
  return param_cache.get('m').get(ssm_name)


def dict_set(ssm_name, val):
  param_cache.get('m').update({ssm_name:val})
