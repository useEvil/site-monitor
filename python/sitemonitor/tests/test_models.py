from sitemonitor.lib.mechanize import Mechanize
from sitemonitor.model import meta
from sitemonitor.tests import *

class TestModels(TestModel):
    """The unit tests for all of our model classes.  Just ensures we can read and write expected
    data to the tables."""
    
    def testModel(self):
        mechanize = Mechanize().getLink('http://my.keynote.com/newmykeynote/start.aspx')

        pass

