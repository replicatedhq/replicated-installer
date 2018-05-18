import os
import boto3

from install_scripts.app import app

if __name__ == '__main__':
    param.init(boto3.session.Session(region_name=os.getenv('AWS_REGION', 'us-east-1')))
    app.run(debug=(os.getenv('ENVIRONMENT') == 'dev'), host='0.0.0.0')
