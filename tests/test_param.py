from install_scripts import param


def test_param_env(mocker):
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()

    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE'})
    val = param.lookup('TEST_KEY', default='DEFAULT VALUE')
    assert val == 'TEST VALUE'

    # there is no param cache with env
    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE 2'})
    val = param.lookup('TEST_KEY', default='DEFAULT VALUE')
    assert val == 'TEST VALUE 2'

    # test default
    val = param.lookup('TEST_KEY_NOTFOUND', default='DEFAULT VALUE')
    assert val == 'DEFAULT VALUE'


def test_dict_init(mocker):
    # test dict init with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    ssm_val = param.param_cache.ssm
    assert ssm_val is None

    m_map = param.param_cache.m
    assert m_map == {}


def test_ssm_dict_init(mocker):
    mocker.patch('install_scripts.param.get_parameters_from_ssm',
                 return_value={})

    # test dict init with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    ssm_val = param.param_cache.ssm
    assert ssm_val is not None

    m_map = param.param_cache.m
    assert m_map == {}


def test_dict_get(mocker):
    # test dict_get with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.param_cache.m['ENV_NAME'] = 'test_value'

    val = param.dict_get('ENV_NAME')
    assert val == 'test_value'


def test_dict_set(mocker):
    # test dict_set with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.dict_set('ENV_NAME', 'test_value')

    val_get = param.dict_get('ENV_NAME')
    assert val_get == 'test_value'


def test_default(mocker):
    # test default with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.dict_set('ENV_NAME', 'test_value')

    # since USE_EC2_PARAMETERS is NOT set, the param cache is NOT utilized
    # i.e., the DEFAULT value will be returned by lookup
    val = param.lookup('CACHE_MISS', default='default_value')
    assert val == 'default_value'


def test_ssm_param_cache_hit(mocker):
    mocker.patch('install_scripts.param.get_parameters_from_ssm',
                 return_value={'ENV_NAME': 'test_value'})

    # test default with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()

    # we should expect a cache hit here, i.e. we should NOT expect an
    # exception triggered by an api call without creds
    val = param.lookup('ENV_NAME', default='default_value')
    assert val == 'test_value'


def test_ssm_param_cache_miss(mocker):
    mocker.patch('install_scripts.param.get_parameters_from_ssm',
                 return_value={'ENV_NAME': 'test_value'})

    # test default with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()

    val = param.lookup('CACHE_MISS', default='default_value')
    assert val == 'default_value'
