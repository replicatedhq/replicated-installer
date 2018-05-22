from __future__ import print_function

import os

import mysql.connector
from flask import g

from . import param


# This creates and tears down mysql connection for all requests
def get():
    db = getattr(g, '_database', None)
    if db is None:
        print("Connecting to db")
        db = g._database = mysql.connector.connect(
            host=param.lookup('MYSQL_HOST', '/mysql/host'),
            port=param.lookup('MYSQL_PORT', '/mysql/port'),
            database=param.lookup('MYSQL_DB', '/mysql/database'),
            user=param.lookup('MYSQL_USER', '/mysql/user'),
            password=param.lookup('MYSQL_PASS', '/mysql/password', decrypt=True))
    return db


def teardown():
    db = getattr(g, '_database', None)
    if db is not None:
        print('Closing db connection')
        db.close()
