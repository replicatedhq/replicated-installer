Install-Scripts
===============

Python and nginx hosted scripts used to install and update Replicated.

## Setup

```
make dev
make shell_composer
make run
```

You may need to alter `make shell` to match the environment where you're running `mysql`, etc.

Also need to add at least one release to your local mysql. 

```sql
INSERT INTO product_version_channel_release VALUES ('replicated_v2', '2.9.3', 'stable', NOW());
```

## Testing

```
curl 'http://127.0.0.1:8090/docker?replicated_tag=2.0.1604&replicated_ui_tag=2.0.14&replicated_operator_tag=2.0.13'
```

## Releasing

Releases are created when a tag is pushed to the upstream repository in the format `v[0-9]+(\.[0-9]+)*(-.*)*`.

Tags should match the target Replicated version. Optionally a pre-release version can be specified such as `-alpha`.

Releases can then be deployed to production by releasing the CircleCI hold.

```
git tag -a v2.39.1 -m "Release 2.39.1" && git push origin v2.39.1
```
