import os

from install_scripts import param


def test_param_env(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})
    param.init()

    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE'})
    val = param.lookup('TEST_KEY', '/test/key', default='DEFAULT VALUE')
    assert val == 'TEST VALUE'

    # there is no param cache with env
    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE 2'})
    val = param.lookup('TEST_KEY', '/test/key', default='DEFAULT VALUE')
    assert val == 'TEST VALUE 2'

    # test default
    val = param.lookup('TEST_KEY_NOTFOUND', '/test/key/notfound', default='DEFAULT VALUE')
    assert val == 'DEFAULT VALUE'


def test_ssm_param_cache(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})
    param.init()

    param.dict_set('/test/key', 'ANOTHER_TEST_VALUE')

    val_get = param.dict_get('/test/key')
    assert val_get == 'ANOTHER_TEST_VALUE'

    val = param.lookup('ANOTHER_TEST_KEY', '/test/key', default='DEFAULT VALUE')
    assert val == 'ANOTHER_TEST_VALUE'

    # test default
    val = param.lookup('ANOTHER_TEST_KEY_NOTFOUND', '/test/key/notfound', default='DEFAULT VALUE')
    assert val == 'DEFAULT VALUE'
