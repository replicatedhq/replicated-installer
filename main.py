import os

from install_scripts.app import app

if __name__ == '__main__':
    app.run(debug=(os.getenv('ENVIRONMENT') == 'dev'), host='0.0.0.0')
