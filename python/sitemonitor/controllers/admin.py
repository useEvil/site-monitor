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
from sitemonitor.model import Site, Host, Monitor
from sitemonitor.model.meta import Session as db

from webhelpers.pylonslib import Flash as _Flash
flash  = _Flash()
log    = logging.getLogger(__name__)

class AdminController(BaseController):
    """view of all of the fixed rates and values"""
#    @AuthorizationControl('index')
    def index(self, limitText='limit', limit=10, offsetText='offset', offset=0):
        log.debug('index')
        log.debug("fetching Service data")
        siteObject = Site()
        c.limit    = int(limit)
        c.offset   = int(offset)
        c.user     = getUser()
        c.sites    = siteObject.getSet(c.limit, c.offset)
        c.total    = siteObject.getTotal()
        c.monitors = Monitor().getAll()
        c.vips     = Host().getVipNames()
        c.length   = len(c.sites)
        self._prev_next()
        return render('admin.html')

    @jsonify
    @restrict('GET')
    def monitor(self, id=None):
        log.debug('monitor')
        """ json data for monitors or a single monitor """
        result = ''
        if id:
            log.debug("fetching Monitor data for ID: %s"%id)
            monitorId     = int(id)
            monitorObject = Monitor().getById(monitorId)
            result        = { 'monitor': self._monitor_to_json(monitorObject) }
        else:
            log.debug("fetching All Monitor data")
            monitorObjects = Monitor().getAll()
            objects        = [ ]
            for monitorObject in monitorObjects:
                objects.append(self._monitor_to_json(monitorObject))
            result = { 'monitors': objects }
        log.debug(result)
        return result

    @jsonify
    @restrict('GET')
    def site(self, id=None):
        log.debug('site')
        """ json data for sites or a single site """
        result = ''
        if id:
            log.debug("fetching Site data for ID: %s"%id)
            siteId     = int(id)
            siteObject = Site().getById(siteId)
            result     = { 'site': self._site_to_json(siteObject) }
        else:
            log.debug("fetching All Site data")
            siteObjects = Site().getAll()
            objects     = [ ]
            for siteObject in siteObjects:
                objects.append(self._site_to_json(siteObject))
            result = { 'sites': objects }
        log.debug(result)
        return result

    @jsonify
    @restrict('GET')
    def host(self, country="US", name=None):
        log.debug('host')
        log.debug("Getting Hosts for country: %s and VIP: %s"%(country, name))
        hosts = Host().getByVip(name)
        names = [ ]
        for host in hosts:
            names.append({
                'id': host.id,
                'ip': host.ip,
                'port': host.port,
                'name': host.name,
                'status': host.status,
                'label': '%s (%d)'%(host.name, host.id)
            })
        result = { 'hosts': names }
        log.debug(result)
        return result

    @jsonify
    @restrict('GET')
#    @AuthorizationControl('version')
    def version(self, name=None):
        log.debug('version')
        """ json data for version """
        if name:
            log.debug("fetching Version data for ID: %s"%name)
            versionObject = Version().getById(int(name))
            result = { }
            result['previous'] = eval(versionObject.previous)
            result['active']   = eval(versionObject.active)
            return result
        else:
            message = {
                'status':  404,
                'title':   'Error Creating User',
                'message': e.message
            }
        return message

#    @AuthorizationControl('versions')
    def versions(self, limit=10, offset=0):
        log.debug('version')
        version    = Version()
        c.user     = getUser()
        c.limit    = int(limit)
        c.offset   = int(offset)
        c.versions = version.getSetUser(c.limit, c.offset)
        c.total    = version.getTotalUser()
        c.length   = len(c.versions)
        self._prev_next()
        return render("admin-versions.html")

    @jsonify
    @restrict("POST")
#    @AuthorizationControl('new')
    def new(self):
        log.debug('new')
        """ create a single user db record """
        params = request.params
        log.debug(params)
        try:
            """ attempt to create a new user """
            userObject = User()
            userObject.addObject()
            userObject.setUserData(params, getUser('id'))
            userObject.setGroupData(params)
            self._log_version(userObject.userName, 'userCreate', json.dumps(self._user_to_json(userObject)), "{'id': 0, 'group': [ ]}")
            db.commit()
            message = {
                'status':  200,
                'userId':  userObject.id,
                'title':   'Successfully Created User',
                'message': 'User %s successfully created.'%userObject.userName
            }
        except InvalidRequestError, e:
            log.error(e.message)
            message = {
                'status':  404,
                'title':   'Error Creating User',
                'message': e.message
            }
        return message

    @jsonify
    @restrict("POST")
#    @AuthorizationControl('update')
    def update(self, id=None):
        log.debug('update')
        """ updates a single user db record """
        params = request.params
        log.debug(params)
        """ check to see if there is a User ID """
        if not id:
            message = {
                'status':  404,
                'title':   'Error Updating User',
                'message': 'No ID given.'
            }
            return message
        """ attempt to update User """
        try:
            userId     = int(id)
            userObject = User().getById(userId)
            previous   = json.dumps(self._user_to_json(userObject))
            userObject.setUserData(params, getUser('id'))
            userObject.setGroupData(params)
            self._log_version(userObject.userName, 'userUpdate', json.dumps(self._user_to_json(userObject)), previous)
            db.commit()
            message = {
                'status':  200,
                'userId':  userObject.id,
                'title':   'Successfully Updated User',
                'message': 'User %s successfully updated.'%userObject.userName
            }
        except InvalidRequestError, e:
            message = {
                'status':  404,
                'title':   'Error Updating User',
                'message': e.message
            }
        return message

    @jsonify
    @restrict("GET")
#    @AuthorizationControl('delete')
    def delete(self, id=None):
        log.debug('delete')
        """ deletes a single user db record """
        """ check to see if there is a User ID """
        if not id:
            message = {
                'status':  404,
                'title':   'Error Deleting User',
                'message': 'No ID given.'
            }
            return message
        """ attempt to delete User """
        try:
            userId     = int(id)
            userObject = User().getById(userId)
            userName   = userObject.userName
            userObject.deleteObject()
            self._log_version(userObject.userName, 'userDelete', "{'id': 0, 'group': [ ]}", json.dumps(self._user_to_json(userObject)))
            db.commit()
            message = {
                'status':  200,
                'title':   'Successfully Deleted User',
                'message': 'User %s successfully deleted.'%userName
            }
        except InvalidRequestError, e:
            message = {
                'status':  404,
                'title':   'Error Deleting User',
                'message': e.message
            }
        return message

    @jsonify
    @restrict("POST")
#    @AuthorizationControl('details')
    def details(self):
        log.debug('details')
        """ create a single user db record """
        params = request.params
        log.debug(params)
        try:
            """ attempt to create a new user """
#            self._log_version(userObject.userName, 'userCreate', json.dumps(self._user_to_json(userObject)), "{'id': 0, 'group': [ ]}")
            if params['form'] == 'monitor':
                if params['objectId']:
                    object = Monitor().getById(int(params['objectId']))
                else:
                    object = Monitor()
                    object.getMaxId()
                object.name     = params['objectName']
                object.endPoint = params['objectEndPoint']
            elif params['form'] == 'site':
                if params['objectId']:
                    object = Site().getById(int(params['objectId']))
                else:
                    object = Site()
                object.name        = params['objectName']
                object.endPoint    = params['objectEndPoint']
                object.countryCode = params['objectCountryCode']
                object.createdDate = date.datetime.today()
                object.setMonitorData(params)
                object.setHostData(params)
            if params['action'] == 'created':
                object.addObject()
            elif params['action'] == 'deleted':
                object.deleteObject()
            db.commit()
            message = {
                'status':  200,
                'form': params['form'],
                'title':   'Successfully Created User',
                'message': 'Object successfully %s.'%params['action']
            }
        except InvalidRequestError, e:
            log.error(e.message)
            message = {
                'status':  404,
                'form': params['form'],
                'title':   'Error Creating User',
                'message': e.message
            }
        return message

    @restrict("GET")
#    @AuthorizationControl('rollback')
    def rollback(self, id=None):
        log.debug('rollback')
        """ rollback fixed rate object """
        log.debug("Rolling back ID: %s!"%id)
        object    = Version().getById(int(id))
        json_cmds = eval(object.previous)
        userId    = json_cmds['id']
        log.debug("User ID: %s!"%userId)
        try:
            userObject = User().getById(userId)
        except Exception, e:
            userObject = User()
        """ rollback User object """
        if object.action == 'userUpdate':
            userObject.setUserData(json_cmds, getUser('id'))
            action = object.action
        elif object.action == 'userDelete':
            userObject.setUserData(json_cmds, getUser('id'))
            action = 'userCreate'
        elif object.action == 'userCreate':
            userObject.deleteObject()
            action = 'userDelete'
        self._log_version(userObject.userName, action, object.previous, object.active)
        """ redirect to versions page """
        try:
            db.commit()
        except Exception, e:
            log.debug(e)
            abort(500)
        """ redirect to versions page """
        return redirect(url(action = 'versions'))


## these probably belong in a util class, 
## but methods prefixed with "_" are private and not exposed as controller actions
    def _str_to_date(self,strdate):
        """ return a datetime obj from a string """
        ruledate = None
        try:
            ruledate = date.datetime.strptime(strdate, "%Y-%m-%d")
        except ValueError:
            raise
        return ruledate

    def _user_to_json(self, userObject=None):
        """ dump to json string """
        if not userObject:
            return
        groups = [ ]
        for g in userObject.groups:
            group  = { }
            group['id']    = g.id
            group['label'] = g.groupName
            groups.append(group)
        result = {
            'id': userObject.id,
            'userName': userObject.userName,
            'firstName': userObject.firstName,
            'lastName': userObject.lastName,
            'emailAddress': userObject.emailAddress,
            'createdDate': userObject.createdDate.strftime('%Y-%m-%d'),
            'updatedDate': userObject.updatedDate.strftime('%Y-%m-%d'),
            'updatedBy': userObject.updatedBy,
            'effectiveStart': userObject.effectiveStart.strftime('%Y-%m-%d'),
            'effectiveEnd': userObject.effectiveEnd.strftime('%Y-%m-%d'),
            'actionType': userObject.actionType or 0,
            'group': groups,
        }
        return result

    def _site_to_json(self, site=None):
        """ dump to json string """
        if not site:
            return
        result = {
            'id': site.id,
            'name': site.name,
            'endPoint': site.endPoint,
            'countryCode': site.countryCode,
            'createdDate': site.createdDate.strftime('%Y-%m-%d'),
            'label': '%d-%s-%s-%s'%(site.id, site.name, site.endPoint, site.countryCode),
            'hosts': self._host_to_json(site.hosts),
            'monitors': self._monitor_to_json(site.monitors),
        }
        return result

    def _host_to_json(self, hosts=None):
        """ dump to json string """
        if not hosts:
            return
        result = [ ]
        for host in hosts:
            result.append({
                'id': host.id,
                'name': host.name,
                'label': '%s (%d)'%(host.name, host.id),
                'ip': host.ip,
                'port': host.port,
                'vip': host.vip,
                'status': host.status,
            })
        return result

    def _monitor_to_json(self, monitors=None):
        """ dump to json string """
        if not monitors:
            return
        result = [ ]
        if type(monitors) == Monitor:
            result = {
                    'id': monitors.id,
                    'name': monitors.name,
                    'label': '%s (%d)'%(monitors.name, monitors.id),
                    'label': '%d-%s-%s'%(monitors.id, monitors.name, monitors.endPoint),
                    'endPoint': monitors.endPoint,
            }
        else:
            for monitor in monitors:
                result.append({
                    'id': monitor.id,
                    'name': monitor.name,
                    'label': '%s (%d)'%(monitor.name, monitor.id),
                    'label': '%d-%s-%s'%(monitor.id, monitor.name, monitor.endPoint),
                    'endPoint': monitor.endPoint,
                })
        return result

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
        version.mid         = id
        version.username    = getUser('id')
        version.action      = action
        version.active      = new_json_string
        version.previous    = old_json_string
        version.createdDate = date.datetime.today()
        version.addObject()


def getUser(key=None):
    user   = {
        'id': h.hasUserId(session) or 'site_monitor_tool',
        'role': h.hasRole(session, 'versions')
    }
    if key:
        return user[key]
    else:
        return user
