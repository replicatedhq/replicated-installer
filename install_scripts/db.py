from __future__ import print_function

import sys

import mysql.connector
from flask import g

from . import param


# This creates and tears down mysql connection for all requests
def get():
    db = getattr(g, '_database', None)
    if db is not None:
        return db

    print("Connecting to db", file=sys.stderr)
    database = param.lookup('MYSQL_DATABASE')
    if not database:
        database = param.lookup('MYSQL_DB')
    password = param.lookup('MYSQL_PASSWORD')
    if not password:
        password = param.lookup('MYSQL_PASS')
    db = g._database = mysql.connector.connect(
        host=param.lookup('MYSQL_HOST'),
        port=param.lookup('MYSQL_PORT'),
        database=database,
        user=param.lookup('MYSQL_USER'),
        password=password)
    return db


def teardown():
    db = getattr(g, '_database', None)
    if db is not None:
        print('Closing db connection', file=sys.stderr)
        db.close()
