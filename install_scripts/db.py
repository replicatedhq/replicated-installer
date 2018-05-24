from __future__ import print_function

import os

import mysql.connector
from flask import g


# This creates and tears down mysql connection for all requests
def get():
    db = getattr(g, '_database', None)
    if db is None:
        print("Connecting to db")
        db = g._database = mysql.connector.connect(
            host=os.environ['MYSQL_HOST'],
            port=os.environ['MYSQL_PORT'],
            database=os.environ['MYSQL_DB'],
            user=os.environ['MYSQL_USER'],
            password=os.environ['MYSQL_PASS'])
    return db


def teardown():
    db = getattr(g, '_database', None)
    if db is not None:
        print('Closing db connection')
        db.close()
