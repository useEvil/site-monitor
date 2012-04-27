"""Helper functions

Consists of functions to typically be used within templates, but also
available to Controllers. This module is available to templates as 'h'.
"""
# Import helpers as desired, or define your own, ie:
#from webhelpers.html.tags import checkbox, password
import datetime as date

from pylons import url

STR_DATE_FORMAT = '%Y-%m-%d'
ROLES = {
    'index':    'Editor',
    'search':   'Editor',
    'edit':     'Editor',
    'pending':  'Approver',
    'history':  'Editor',
    'versions': 'Admin',
    'update':   'Editor',
    'delete':   'Editor',
    'rollback': 'Admin',
    'approve':  'Approver',
}


def cssSelector(*parts):
    if not parts:
        return
    return joinParts(*parts)

def cssId(*parts):
    if not id:
        return
    return { 'id': joinParts(*parts) }

def cssHref(*parts):
    if not id:
        return
    return { 'href': '#' + joinParts(*parts) }

def joinParts(*parts):
    return "_".join(parts)

def isEditor(user=None):
    if user:
        if user['role'] == 'Editor':
            return 1
    return None

def hasUserId(session=None):
    if session:
        return session.has_key('userid') and session['userid'] or None
    return None

def hasRole(session=None, role=None):
    if session:
        return session.has_key('permissions') and role in session['permissions'] and ROLES[role] or None
    return None

def hasSelected(site=None, selected=None):
    if site and selected:
        return site.getEndPoint() == selected.getEndPoint() and 'selected' or None
    return None
