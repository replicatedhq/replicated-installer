import os
import boto3

from install_scripts import param
from install_scripts.app import app

param.init(boto3.session.Session(region_name=os.getenv('AWS_REGION', 'us-east-1')))

if __name__ == '__main__':
    app.run(debug=(os.getenv('ENVIRONMENT') == 'dev'), host='0.0.0.0')
