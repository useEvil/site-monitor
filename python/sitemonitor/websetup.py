"""Setup the site-monitor application"""
import logging
import pylons.test

from sitemonitor.config.environment import load_environment
from sitemonitor.model import meta

log = logging.getLogger(__name__)

def setup_app(command, conf, vars):
    # Don't reload the app if it was loaded under the testing environment
    if not pylons.test.pylonsapp:
        """Place any commands to setup sitemonitor here"""
        load_environment(conf.global_conf, conf.local_conf)

    # Create the tables if they don't already exist
    meta.metadata.create_all(bind=meta.engine)
