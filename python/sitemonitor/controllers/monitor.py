import os
import string
import logging
import simplejson as json
import datetime as date
import sitemonitor.lib.helpers as h

from sqlalchemy.exceptions import InvalidRequestError
from pylons import request, response, session, tmpl_context as c
from pylons.controllers.util import abort, redirect
from pylons.decorators.rest import restrict
from pylons.decorators import jsonify
from pylons import config, url

from sitemonitor.lib.base import BaseController, render
#from sitemonitor.lib.authorization import AuthorizationControl
from sitemonitor.model import Site, Monitor, Preference
from sitemonitor.model.meta import Session as db

from webhelpers.pylonslib import Flash as _Flash
flash  = _Flash()
log    = logging.getLogger(__name__)

class MonitorController(BaseController):
    """view of all of the Sites to Monitor"""
    @restrict('GET')
    def index(self, country="US", name=None):
        log.debug('index')
        c.user  = getUser()
        c.sites = Site().getAll()
        if name:
            c.site = Site().getByCountryName(country, name)
            prefs  = Preference().getBySiteId(c.site.id)
            if prefs:
                c.prefs = prefs.getData()
        c.info_messages = flash.pop_messages()
        return render('index.html')

    @restrict('GET')
    def healthcheck(self, country="US", name=None):
        log.debug('healthcheck')
        log.debug("Getting Health Checks for country: %s %s"%(country,name))
        if name:
            c.site  = Site().getByCountryName(country, name)
            c.hosts = c.site.hosts
            prefs   = Preference().getBySiteId(c.site.id)
            if prefs:
                c.prefs = prefs.getData()
        c.info_messages = flash.pop_messages()
        return render('health-check.html')

    @restrict('GET')
    def splunk(self, country="US", name=None):
        log.debug('splunk')
        log.debug("Getting Splunk Data for country: %s %s"%(country,name))
        if name:
            c.site  = Site().getByCountryName(country, name)
            c.hosts = c.site.hosts
            prefs   = Preference().getBySiteId(c.site.id)
            if prefs:
                c.prefs = prefs.getData()
        c.info_messages = flash.pop_messages()
        return render('splunk.html')

    @restrict('GET')
    def graphite(self, country="US", name=None):
        log.debug('graphite')
        log.debug("Getting Splunk Data for country: %s %s"%(country,name))
        if name:
            c.site  = Site().getByCountryName(country, name)
            c.hosts = c.site.hosts
            prefs   = Preference().getBySiteId(c.site.id)
            if prefs:
                c.prefs = prefs.getData()
        c.info_messages = flash.pop_messages()
        return render('graphite.html')

    @restrict('GET')
    def keynote(self, country="US", name=None):
        log.debug('keynote')
        log.debug("Getting Keynote Data for country: %s %s"%(country,name))
        if name:
            c.site  = Site().getByCountryName(country, name)
            c.hosts = c.site.hosts
            prefs   = Preference().getBySiteId(c.site.id)
            if prefs:
                c.prefs = prefs.getData()
        c.info_messages = flash.pop_messages()
        return render('keynote.html')

    @jsonify
    @restrict('POST')
    def preferences(self):
        log.debug('preferences')
        log.debug('Saving Preferences')
        params = request.params
        log.debug(params)
        col1 = params.getall('sort1[]')
        col2 = params.getall('sort2[]')
        result = {
            'site': params['site'],
            'col1': col1,
            'col2': col2
        }
        log.debug(result)
        json_string = json.dumps(result)
        Preference().save(params['site'], json_string)
        log.debug(json_string)
        return json_string

    @restrict("POST")
#    @AuthorizationControl('setby')
    def setby(self):
        log.debug('setby')
        """ sets the smart pricing factor for atoms """
        params = request.params
        log.debug(params)
        qFactor = QualityFactor()
        try:
            categories = params.getall('category_id')
            atoms      = params.getall('atom_id')
            for cid in categories:
                all_atoms = [ ]
                if cid in atoms and params.has_key('factor_' + cid):
#                    log.debug("By Atom: %s"%cid)
#                    log.debug("Atom: PublisherID: %s; Atom ID: %s; Factor: %s; Notes: %s; Country Code: %s;"%(params['publisher_id'], cid, params['factor_' + cid], params['notes_' + cid], params['country']))
                    qFactor.set(params['publisher_id'], cid, params['factor_' + cid], params['notes_' + cid], getUser('id'))
                else:
                    category  = TaxiiCategory(int(cid), None, params['country'])
                    all_atoms = self._all_atoms(category, all_atoms)
#                    log.debug("By Category: %s"%cid)
#                    log.debug("CID: %d; Label: %s"%(category.id(), category.label()))
                    for atomId in all_atoms:
                        if atomId in atoms and params.has_key('factor_' + atomId):
                            continue
#                        log.debug("CID Atoms: PublisherID: %s; Atom ID: %s; Factor: %s; Notes: %s; Country Code: %s;"%(params['publisher_id'], atomId, params['factor_' + cid], params['notes_' + cid], params['country']))
                        qFactor.set(params['publisher_id'], atomId, params['factor_' + cid], params['notes_' + cid], getUser('id'))
            db.commit()
            flash("Categories Updated for Publisher ID: %s"%params['publisher_id'])
        except Exception, e:
            log.debug(e)
            flash("Failed to update Categories")
        return redirect(url(action = 'index'))

    def logout(self):
        session.delete()
        host = config.get('auth.host')
        if not host:
            host = os.uname()[1]
        return redirect(url('http://' + host + ':' + config.get('auth.port') + config.get('auth.path')))


## these probably belong in a util class, 
## but methods prefixed with "_" are private and not exposed as controller actions
    def _get_health_check(self, hosts):
        result = [ ]
        for host in hosts:
            status = host.getHealthCheck()
            print '==== host [%s] = [%s]'%(host.name, status)
            result.append({'host': host.name, 'staus': status})
        return result

    def _str_to_date(self, strdate):
        """ return a datetime obj from a string """
        ruledate = None
        try:
            ruledate = date.datetime.strptime(strdate, "%Y-%m-%d")
        except ValueError:
            raise
        return ruledate

    def _object_to_hash(self, object=None, data={ }):
        """ dump to json string """
        if not object:
            return data
        # Publisher
        if hasattr(object, 'atomId'):
            data['atomId'] = object.atomId
        if hasattr(object, 'publisherId'):
            data['publisherId'] = object.publisherId
        if hasattr(object, 'name'):
            data['name'] = object.name
        if hasattr(object, 'country'):
            data['country'] = object.country
        # QualityFactor or Most Recent
        if hasattr(object, 'qualityFactor'):
            data['qualityFactor'] = str(object.qualityFactor())
        if hasattr(object, 'notes'):
            data['notes'] = object.notes
        if hasattr(object, 'dateCreated'):
            data['dateCreated'] = str(object.dateCreated)
        if hasattr(object, 'dateApproved'):
            data['dateApproved'] = str(object.dateApproved)
        if hasattr(object, 'approvedBy'):
            data['approvedBy'] = object.approvedBy
#        print '==== %s'%(data)
        return data

    def _prev_next(self):
        log.debug("Total: %s, Length: %s, Limit: %s, Offset: %s"%(c.total, c.length, c.limit, c.offset))
        """ prev values """
        if c.offset:
            log.debug("prev: Offset: %s > 0"%(c.offset))
            c.prev = c.offset - c.limit
        if c.prev < 0:
            log.debug("prev: Prev: %s < 0"%(c.prev))
            c.prev = 0
        """ next values """
        if c.length < c.limit:
            log.debug("next: Length: %s < Limit: %s"%(c.length, c.limit))
            c.next = 0
        elif c.total == (c.offset + c.limit):
            log.debug("next: Total: %s == Offset: %s + Limit: %s"%(c.total, c.offset, c.limit))
            c.next = 0
        elif c.total > c.limit:
            log.debug("next: Total: %s > Limit: %s"%(c.total, c.limit))
            c.next = c.limit + c.offset

    def _log_version(self, id, action, new_json_string, old_json_string):
        return
        version = Version()
        version.adminId     = id
        version.adminName   = getUser('id')
        version.action      = action
        version.active      = new_json_string
        version.previous    = old_json_string
        version.createdDate = date.datetime.today()
        version.addObject()


def getUser(key=None):
    user   = {
        'id': h.hasUserId(session) or 'site_monitor_tool',
        'role': h.hasRole(session, 'versions') or h.hasRole(session, 'update') or None
    }
    if key:
        return user[key]
    else:
        return user
