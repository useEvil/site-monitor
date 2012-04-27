"""The Splunk Controller API

Provides the Splink class for subclassing.
"""
import time

from zope.testbrowser.browser import Browser
from pylons import config

HOST = config.get('splunk.host')

class Mechanize:

    def getLink(self, url=None):
        if not url: return

        # /////////////////////////////////////////////////////////////////////////////
        # Scenario 1: do a simple search for all web server logs
        # /////////////////////////////////////////////////////////////////////////////

        # start search
        browser = Browser()


        # Get URL
        #
        # Option A: return all of the matched events
        browser.open(url)

        ctrl = browser.getControl(name='josso_username')
        ctrl.value = 'shopzi'

        ctrl = browser.getControl(name='josso_password')
        ctrl.value = 'olympic'

        ctrl = browser.getControl(name='submitButtonName')
        ctrl.click()

        print browser.contents

