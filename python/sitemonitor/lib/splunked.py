"""The Splunk Controller API

Provides the Splink class for subclassing.
"""
import time
import splunk

from splunk import auth, search
from pylons import config

HOST = config.get('splunk.host')
splunk.mergeHostPath(HOST, True)

class Splunk:
    # first get the session key
    # (the method will automatically cache during the interactive session)
    auth.getSessionKey('admin','changeme')

    def searchSplunk(self):
        # /////////////////////////////////////////////////////////////////////////////
        # Scenario 1: do a simple search for all web server logs
        # /////////////////////////////////////////////////////////////////////////////

        # start search
        job = search.dispatch('search index="coherence" host="*hou" source="coherence_gc_log" sourcetype="garbagecollection" | timechart max(gctime) by host')

        # at this point, Splunk is running the search in the background; how long it
        # takes depends on how much data is indexed, and the scope of the search
        #
        # from this point, we explore some of the things you can do:
        #
        #
        # Option A: return all of the matched events

        # this will stream events back until the last event is reached
#        for event in job:
#            print event

        # Option B: just return the host field all of the matched events
#        for event in job:
#                print event['host']

        # Option C: return specific events

        # wait until the job has completed before trying to access arbirary indices
        while not job.isDone:
            time.sleep(1)

        # print the total number of matched events
        print len(job)
        print job.count

        # print the second event (remember that python is 0-indexed)
        print job[1]

        # print the first 10
        for event in job[0:10]:
                print event

        # print the last 5
        for event in job[:-5]:
            print event

        # clean up
        job.cancel()

    def searchSplunkSummarize(self):
        # /////////////////////////////////////////////////////////////////////////////
        # Scenario 2: do a search for all web server logs and summarize
        # /////////////////////////////////////////////////////////////////////////////

        # start search
        job = search.dispatch('search sourcetype="access_combined" | timechart count')

        # the 'job' object has 2 distinct result containers: 'events' and 'results'
        # 'events' contains the data in a non-transformed manner
        # 'results' contains the data that is post-transformed, i.e. after being
        # processed by the 'timechart' operator

        # wait for search to complete, and make the results available
        while not job.isDone:
            time.sleep(1)

        # print out the results
        for result in job.results:
            print result

        # because we used the 'timechart' operator, the previous loop will output a
        # compacted string; to get at a native dictionary of fields:
        for result in job.results:
            print result.fields     # prints a standard python str() of a dict object

        # or, if we just want the raw events
#        for event in job.events:
#            print event
#            print event.time    # returns a datetime.datetime object

        # clean up
        job.cancel()
