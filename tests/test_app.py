import pytest

from install_scripts import helpers, param
from install_scripts.app import app


VERSION_KEYS = [
    'replicated_tag', 'replicated_ui_tag', 'replicated_operator_tag',
    'current_replicated_version', 'next_replicated_version',
    'pinned_docker_version', 'kubernetes_version', 'docker_version',
]


@pytest.mark.parametrize('path', ['/', '/docker-install.sh', '/some/sub-path'])
@pytest.mark.parametrize('key', VERSION_KEYS)
@pytest.mark.parametrize('payload', [
    '<img src=x onerror=alert(document.domain)>',
    '<svg onload=alert(document.domain)>',
])
def test_invalid_versions_are_plain_text(path, key, payload):
    response = app.test_client().get(path, query_string={key: payload})

    assert response.status_code == 400
    assert response.content_type == 'text/plain; charset=utf-8'
    assert response.headers['X-Content-Type-Options'] == 'nosniff'
    assert response.get_data(as_text=True) == 'Invalid value for {}: {}'.format(
        key, payload)


def test_other_bad_requests_are_plain_text(mocker):
    message = 'no releases for product replicated and channel <svg onload=alert(1)>'
    mocker.patch('install_scripts.helpers.get_replicated_version',
                 side_effect=helpers.BadRequestException(message))

    response = app.test_client().get('/version')

    assert response.status_code == 400
    assert response.content_type == 'text/plain; charset=utf-8'
    assert response.headers['X-Content-Type-Options'] == 'nosniff'
    assert response.get_data(as_text=True) == message


@pytest.mark.parametrize('key', VERSION_KEYS)
def test_valid_versions_are_accepted(key):
    response = app.test_client().get('/healthz', query_string={key: '1.2.3'})

    assert response.status_code == 200


def test_docker_script_remains_a_shell_script(monkeypatch):
    monkeypatch.setattr(param, 'param_cache', param.ParamCache(None))
    response = app.test_client().get('/docker-install.sh',
                                    query_string={'docker_version': '24.0.2'})

    assert response.status_code == 200
    assert response.mimetype == 'text/x-shellscript'
    assert response.get_data(as_text=True).startswith('#!/bin/sh')
