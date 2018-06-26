from __future__ import print_function

import os

import mysql.connector
from flask import g

from . import param


# This creates and tears down mysql connection for all requests
def get():
    db = getattr(g, '_database', None)
    if db is not None:
        return db

    print("Connecting to db")
    database = param.lookup('MYSQL_DATABASE', '/mysql/database')
    if database == '':
        database = param.lookup('MYSQL_DB', '/mysql/database')
    password = param.lookup('MYSQL_PASSWORD', '/mysql/password', decrypt=True)
    if password == '':
        password = param.lookup('MYSQL_PASS', '/mysql/password', decrypt=True)
    db = g._database = mysql.connector.connect(
        host=param.lookup('MYSQL_HOST', '/mysql/host'),
        port=param.lookup('MYSQL_PORT', '/mysql/port'),
        database=database,
        user=param.lookup('MYSQL_USER', '/mysql/user'),
        password=password)
    return db


def teardown():
    db = getattr(g, '_database', None)
    if db is not None:
        print('Closing db connection')
        db.close()
