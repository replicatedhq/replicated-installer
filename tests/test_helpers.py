from install_scripts import helpers
from install_scripts.app import app


def test_get_replicated_version_app(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value='2.5.2')
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_tag=2.6.0'):
        version = helpers.get_replicated_version('stable', 'test-app',
                                                 'stables')
    assert version == '2.5.2'


def test_get_replicated_version_arg(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_tag=2.6.0'):
        version = helpers.get_replicated_version('stable', 'test-app',
                                                 'stables')
    assert version == '2.6.0'


def test_get_replicated_version_current(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/'):
        version = helpers.get_replicated_version('stable', 'test-app',
                                                 'stables')
    assert version == '2.6.2'


def test_get_replicated_ui_version_app(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value='2.5.2')
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_ui_tag=2.6.0'):
        version = helpers.get_replicated_ui_version('stable', 'test-app',
                                                    'stables')
    assert version == '2.5.2'


def test_get_replicated_ui_version_arg(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_ui_tag=2.6.0'):
        version = helpers.get_replicated_ui_version('stable', 'test-app',
                                                    'stables')
    assert version == '2.6.0'


def test_get_replicated_ui_version_replicated_arg(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_tag=2.6.1'):
        version = helpers.get_replicated_ui_version('stable', 'test-app',
                                                    'stables')
    assert version == '2.6.1'


def test_get_replicated_ui_version_current(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/'):
        version = helpers.get_replicated_ui_version('stable', 'test-app',
                                                    'stables')
    assert version == '2.6.2'


def test_get_replicated_operator_version_app(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value='2.5.2')
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_operator_tag=2.6.0'):
        version = helpers.get_replicated_operator_version(
            'stable', 'test-app', 'stables')
    assert version == '2.5.2'


def test_get_replicated_operator_version_arg(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_operator_tag=2.6.0'):
        version = helpers.get_replicated_operator_version(
            'stable', 'test-app', 'stables')
    assert version == '2.6.0'


def test_get_replicated_operator_version_replicated_arg(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/?replicated_tag=2.6.1'):
        version = helpers.get_replicated_operator_version(
            'stable', 'test-app', 'stables')
    assert version == '2.6.1'


def test_get_replicated_operator_version_current(mocker):
    mocker.patch(
        'install_scripts.helpers.get_version_for_app', return_value=None)
    mocker.patch(
        'install_scripts.helpers.get_current_replicated_version',
        return_value='2.6.2')
    with app.test_request_context('/'):
        version = helpers.get_replicated_operator_version(
            'stable', 'test-app', 'stables')
    assert version == '2.6.2'


def test_get_premkit_data_dir():
    assert helpers.get_premkit_data_dir('2.11.1') == '/premkit/data'
    assert helpers.get_premkit_data_dir('2.13.0') == '/tmp/premkit-data'
    assert helpers.get_premkit_data_dir('2.13.1') == ''
    assert helpers.get_premkit_data_dir('2.14.0') == ''
