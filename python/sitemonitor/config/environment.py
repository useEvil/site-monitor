"""Pylons environment configuration"""
import os

from genshi.template import TemplateLoader
from pylons.configuration import PylonsConfig
from sqlalchemy import engine_from_config

import sitemonitor.lib.app_globals as app_globals
import sitemonitor.lib.helpers
from sitemonitor.config.routing import make_map
from sitemonitor.model import init_model

def load_environment(global_conf, app_conf):
    """Configure the Pylons environment via the ``pylons.config``
    object
    """
    # Pylons paths
    config = PylonsConfig()
    root   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    paths  = dict(root=root,
                 controllers=os.path.join(root, 'controllers'),
                 static_files=os.path.join(root, 'public'),
                 templates=[os.path.join(root, 'templates')])

    # Initialize config with the basic options
    config.init_app(global_conf, app_conf, package='sitemonitor', paths=paths)

    config['routes.map'] = make_map(config)
    config['pylons.app_globals'] = app_globals.Globals(config)
    config['pylons.h'] = sitemonitor.lib.helpers
    config['pylons.strict_tmpl_context'] = False

    # Create the Genshi TemplateLoader
    config['pylons.app_globals'].genshi_loader = TemplateLoader(
        paths['templates'], auto_reload=True)

    # Setup the SQLAlchemy database engine
    engine = engine_from_config(config, 'sqlalchemy.')
    init_model(engine)

    # Optionally, if removing the CacheMiddleware and using the
    # cache in the new 1.0 style, add under the previous lines:
    import pylons
    pylons.cache._push_object(config['pylons.app_globals'].cache)

    # CONFIGURATION OPTIONS HERE (note: all config options will override
    # any Pylons config options)
    return config
