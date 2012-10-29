"""The application's model objects"""
import logging
import datetime as date
import re as regexp
import socket

from sqlalchemy import orm, Table, Column, Numeric, Integer, String, ForeignKey, Sequence, Unicode, CLOB, select, func, desc
from sqlalchemy.orm import relation, backref
from sqlalchemy.types import DateTime
from sqlalchemy.ext.declarative import declarative_base

from pylons import config
from urllib import urlencode
from urllib2 import Request, urlopen, URLError

from sitemonitor.model import meta

ORMBase = declarative_base()
log     = logging.getLogger(__name__)
timeout = 2

socket.setdefaulttimeout(timeout)

def init_model(engine):
    """Call me before using any of the tables or classes in the model"""
    ## Reflected tables must be defined and mapped here
    #global reflected_table
    #reflected_table = sa.Table("Reflected", meta.metadata, autoload=True,
    #                           autoload_with=engine)
    #orm.mapper(Reflected, reflected_table)
    #
    smMeta = orm.sessionmaker(autoflush=True, autocommit=False, bind=engine)
    meta.engine  = engine
    meta.Session = orm.scoped_session(smMeta)


## Non-reflected tables may be defined and mapped at module level
#foo_table = sa.Table("Foo", meta.metadata,
#    sa.Column("id", sa.types.Integer, primary_key=True),
#    sa.Column("bar", sa.types.String(255), nullable=False),
#    )
#
#class Foo(object):
#    pass
#
#orm.mapper(Foo, foo_table)


## Classes for reflected tables may be defined here, but the table and
## mapping itself must be done in the init_model function
#reflected_table = None
#
#class Reflected(object):
#    pass

siteMonitor = Table('SITE_MONITOR', ORMBase.metadata,
             Column('SITE_ID', Integer, ForeignKey('SITE.SITE_ID')),
             Column('MONITOR_ID', Integer, ForeignKey('MONITOR.MONITOR_ID'))
        )
"""
    DROP TABLE SITE_MONITOR;
    CREATE TABLE SITE_MONITOR (
        SITE_ID     NUMBER(38) NOT NULL,
        MONITOR_ID  NUMBER(38) NOT NULL,
        CONSTRAINT PK_SITE_MONITOR PRIMARY KEY (SITE_ID, MONITOR_ID),
        CONSTRAINT FK_SITE_ID FOREIGN KEY (SITE_ID) REFERENCES SITE (SITE_ID),
        CONSTRAINT FK_MONITOR_ID FOREIGN KEY (MONITOR_ID) REFERENCES MONITOR (MONITOR_ID)
    );

    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 1);
    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 2);
    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 3);
    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 4);
    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 5);
    INSERT INTO SITE_MONITOR (SITE_ID, MONITOR_ID) VALUES(1, 6);
    SELECT * FROM SITE_MONITOR;
"""


siteHost = Table('SITE_HOST', ORMBase.metadata,
                    Column('SITE_ID', Integer, ForeignKey('SITE.SITE_ID')),
                    Column('HOST_ID', Integer, ForeignKey('HOST.HOST_ID'))
            )
"""
    DROP TABLE SITE_HOST;
    CREATE TABLE SITE_HOST (
        SITE_ID  NUMBER(38) NOT NULL,
        HOST_ID  NUMBER(38) NOT NULL,
        CONSTRAINT PK_SITE_HOST PRIMARY KEY (SITE_ID, HOST_ID),
        CONSTRAINT FK_SH_S_SITE_ID FOREIGN KEY (SITE_ID) REFERENCES SITE (SITE_ID),
        CONSTRAINT FK_SH_H_HOST_ID FOREIGN KEY (HOST_ID) REFERENCES HOST (HOST_ID)
    );

    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 1);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 2);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 3);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 4);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 5);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 6);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 7);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 8);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 9);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 10);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 11);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 12);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(2, 13);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 14);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 15);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 16);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 17);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 18);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(3, 19);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 20);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 21);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 22);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 23);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 24);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(4, 25);
    INSERT INTO SITE_HOST (SITE_ID, HOST_ID) VALUES(1, 26);
    SELECT * FROM SITE_HOST;
    """


"""Site objects"""
class Site(ORMBase):
    """
    DROP TABLE SITE;
    CREATE TABLE SITE (
            SITE_ID       NUMBER(38) NOT NULL,
            SITE_NAME     VARCHAR2(100) NOT NULL,
            END_POINT     VARCHAR2(100) NOT NULL,
            COUNTRY_CODE  VARCHAR(2) NOT NULL,
            CREATED_DATE  DATE DEFAULT CURRENT_TIMESTAMP NOT NULL,
            CONSTRAINT PK_VERSION PRIMARY KEY (SITE_ID)
    );

    INSERT INTO SITE (SITE_ID, SITE_NAME, END_POINT, COUNTRY_CODE) VALUES (1, 'Publisher US', 'publisher', 'US');
    INSERT INTO SITE (SITE_ID, SITE_NAME, END_POINT, COUNTRY_CODE) VALUES (2, 'Publisher GB', 'publisher', 'GB');
    INSERT INTO SITE (SITE_ID, SITE_NAME, END_POINT, COUNTRY_CODE) VALUES (3, 'Publisher DE', 'publisher', 'DE');
    INSERT INTO SITE (SITE_ID, SITE_NAME, END_POINT, COUNTRY_CODE) VALUES (4, 'Publisher FR', 'publisher', 'FR');
    SELECT * FROM SITE;
    """

    __tablename__ = 'SITE'

    id            = Column('SITE_ID', Integer, primary_key=True)
    name          = Column('SITE_NAME', String(100), nullable=False)
    endPoint      = Column('END_POINT', String(100), nullable=False)
    countryCode   = Column('COUNTRY_CODE', String(2), nullable=False)
    createdDate   = Column('CREATED_DATE', DateTime, nullable=False)
    hosts         = relation('Host', secondary=siteHost, backref='hosts', lazy=False)
    monitors      = relation('Monitor', secondary=siteMonitor, backref='monitors', lazy=False)

    def getMaxId(self):
        max = meta.Session.query(self.__class__).from_statement(
            select(
                [self.__mapper__._with_polymorphic_selectable],
                select([func.max(self.__mapper__.c.id)]).label('id')==self.__mapper__.c.id)
        ).first()
        if max:
            self.id = max.id + 1
        else:
            self.id = 1

    def getAll(self):
        return meta.Session.query(self.__class__).all()

    def getById(self, id=None):
        if not id: return
        return meta.Session.query(self.__class__).filter_by(id=id).one()

    def getByName(self, name=None):
        if not name: return
        return meta.Session.query(self.__class__).filter_by(name=name).one()

    def getByCountryName(self, country=None, name=None):
        if not country or not name: return
        return meta.Session.query(self.__class__).filter_by(countryCode=country, endPoint=name).one()

    def getSet(self, limit=10, offset=0):
        return meta.Session.query(self.__class__).order_by(self.__class__.id).limit(limit).offset(offset).all()

    def getTotal(self):
        return meta.Session.query(self.__class__).count()

    def getEndPoint(self):
        return '%s/%s'%(self.countryCode, self.endPoint)

    def getColumnOne(self, prefs=None):
        monitors = self.monitors
        sets     = int(len(monitors) / 2)
        rows     = [ ]
        if prefs and prefs.has_key('col1'):
            rows = self.sortOrder(monitors, prefs['col1'])
        else:
            for i in range(sets):
                rows.append(monitors[i])
        return rows

    def getColumnTwo(self, prefs=None):
        monitors = self.monitors
        length   = len(monitors)
        sets     = int(length / 2)
        rows     = [ ]
        if prefs and prefs.has_key('col2'):
            rows = self.sortOrder(monitors, prefs['col2'])
        else:
            for i in range(sets, length):
                rows.append(monitors[i])
        return rows

    def sortOrder(self, list=None, order=None):
        if not list or not order: return
        hash    = { }
        ordered = [ ]
        for item in list:
            hash[item.endPoint] = item
        for item in order:
            ordered.append(hash[item])
        return ordered

    def setMonitorData(self, data=None):
        if not data:
            return self
        self.monitors = [ ]
        for id in data.getall('site_monitor'):
            self.monitors.append(Monitor().getById(id))
        return self.monitors

    def setHostData(self, data=None):
        if not data:
            return self
        self.hosts = [ ]
        for id in data.getall('site_host'):
            self.hosts.append(Host().getById(id))
        return self.hosts

    def addObject(self):
        self.getMaxId()
        return meta.Session.add(self)

    def deleteObject(self):
        return meta.Session.delete(self)


"""Monitor objects"""
class Monitor(ORMBase):
    """
    DROP TABLE MONITOR;
    CREATE TABLE MONITOR (
            MONITOR_ID    NUMBER(38) NOT NULL,
            MONITOR_NAME  VARCHAR2(100) NOT NULL,
            END_POINT     VARCHAR2(100) NOT NULL,
            CREATED_DATE  DATE DEFAULT CURRENT_TIMESTAMP NOT NULL,
            CONSTRAINT PK_VERSION PRIMARY KEY (MONITOR_ID)
    );

    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (1, 'Health Check', 'healthcheck');
    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (2, 'Splunk', 'splunk');
    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (3, 'Graphite', 'graphite');
    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (4, 'Keynote', 'keynote');
    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (5, 'Health Check', 'healthcheck3');
    INSERT INTO MONITOR (MONITOR_ID, MONITOR_NAME, END_POINT) VALUES (6, 'Splunk', 'splunk3');
    SELECT * FROM MONITOR;
    """

    __tablename__ = 'MONITOR'

    id            = Column('MONITOR_ID', Integer, primary_key=True)
    name          = Column('MONITOR_NAME', String(100), nullable=False)
    endPoint      = Column('END_POINT', String(100), nullable=False)
    createdDate   = Column('CREATED_DATE', DateTime, nullable=False)

    def getMaxId(self):
        max = meta.Session.query(self.__class__).from_statement(
            select(
                [self.__mapper__._with_polymorphic_selectable],
                select([func.max(self.__mapper__.c.id)]).label('id')==self.__mapper__.c.id)
        ).first()
        if max:
            self.id = max.id + 1
        else:
            self.id = 1

    def getAll(self):
        return meta.Session.query(self.__class__).order_by(self.__class__.id).all()

    def getById(self, id=None):
        if not id: return
        return meta.Session.query(self.__class__).filter_by(id=id).one()


"""Application objects"""
class Application(ORMBase):
    """
    DROP TABLE APPLICATION;
    CREATE TABLE APPLICATION (
        APPLICATION_ID        NUMBER(38) NOT NULL,
        APPLICATION_NAME      VARCHAR2(100) NOT NULL,
        APPLICATION_URL       VARCHAR2(1000),
        CONSTRAINT PK_APPLICATION PRIMARY KEY (APPLICATION_ID)
    );
    """

    __tablename__   = 'APPLICATION'

    id              = Column('APPLICATION_ID', Integer, primary_key = True)
    applicationName = Column('APPLICATION_NAME', String(100))
    applicationUrl  = Column('APPLICATION_URL', String(1000))

    def getMaxId(self):
        max = meta.Session.query(self.__class__).from_statement(
            select(
                [self.__mapper__._with_polymorphic_selectable],
                select([func.max(self.__mapper__.c.id)]).label('id')==self.__mapper__.c.id)
        ).first()
        if max:
            self.id = max.id + 1
        else:
            self.id = 1

    def getAll(self):
        return meta.Session.query(self.__class__).order_by(self.__class__.id).all()

    def getById(self, id=None):
        if not id: return
        return meta.Session.query(self.__class__).filter_by(id=id).one()

    def addObject(self):
        self.getMaxId()
        return meta.Session.add(self)

    def deleteObject(self):
        return meta.Session.delete(self)


"""Host objects"""
class Host(ORMBase):
    """
    DROP TABLE HOST;
    CREATE TABLE HOST (
        HOST_ID    NUMBER(38) NOT NULL,
        HOST_NAME  VARCHAR2(150) NOT NULL,
        HOST_IP    VARCHAR2(15) NOT NULL,
        HOST_PORT  Integer NOT NULL,
        VIP_NAME   VARCHAR2(150) NULL,
        STATUS     Integer NOT NULL,
        CONSTRAINT PK_HOST PRIMARY KEY (HOST_ID)
    );

    SELECT * FROM HOST;
    """

    __tablename__   = 'HOST'

    id              = Column('HOST_ID', Integer, primary_key = True)
    name            = Column('HOST_NAME', String(150))
    ip              = Column('HOST_IP', String(15))
    port            = Column('HOST_PORT', Integer)
    vip             = Column('VIP_NAME', String(150))
    status          = Column('STATUS', Integer)
    healthCheck     = ''

    def getMaxId(self):
        max = meta.Session.query(self.__class__).from_statement(
            select(
                [self.__mapper__._with_polymorphic_selectable],
                select([func.max(self.__mapper__.c.id)]).label('id')==self.__mapper__.c.id)
        ).first()
        if max:
            self.id = max.id + 1
        else:
            self.id = 1

    def getVipNames(self):
        return meta.Session.query(self.__class__).group_by(self.__mapper__.c.vip).all()

    def getByVip(self, vip=None):
        if not vip: return
        return meta.Session.query(self.__class__).filter_by(vip=vip).all()

    def getAll(self):
        return meta.Session.query(self.__class__).order_by(self.__class__.id).all()

    def getById(self, id=None):
        if not id: return
        return meta.Session.query(self.__class__).filter_by(id=id).one()

    def getHealthCheck(self, host=None, port=None):
        if not host:
            host = self.name
        if not port:
            port = self.port
        else:
            port = 80
        url = 'http://%s:%s/health-check'%(host, port)
        log.warning(url)
        try:
            f = urlopen(url)
            content = f.read()
        except URLError, e:
            log.error(e)
            self.healthCheck = 0
            return ''
        try:
            reg   = regexp.compile('SCALL-OK')
            match = reg.search(content)
            if match:
                self.healthCheck = 1
            else:
                self.healthCheck = 0
        except Exception, e:
            log.error(e)
        return ''

    def addObject(self):
        self.getMaxId()
        return meta.Session.add(self)

    def deleteObject(self):
        return meta.Session.delete(self)


"""Preference objects"""
class Preference(ORMBase):
    """
    DROP TABLE PREFERENCE;
    CREATE TABLE PREFERENCE (
        PREFERENCE_ID      NUMBER(38) NOT NULL,
        PREFERENCE_STRING  VARCHAR2(4000) NOT NULL,
        SITE_ID            NUMBER(38) NOT NULL,
        CONSTRAINT PK_PREFERENCE PRIMARY KEY (PREFERENCE_ID),
        CONSTRAINT FK_SITE_ID FOREIGN KEY (SITE_ID) REFERENCES SITE (SITE_ID)
    );

    SELECT * FROM PREFERENCE;
    """

    __tablename__   = 'PREFERENCE'

    id              = Column('PREFERENCE_ID', Integer, primary_key = True)
    string          = Column('PREFERENCE_STRING', String(4000))
    siteId          = Column('SITE_ID', Integer)

    def getMaxId(self):
        max = meta.Session.query(self.__class__).from_statement(
            select(
                [self.__mapper__._with_polymorphic_selectable],
                select([func.max(self.__mapper__.c.id)]).label('id')==self.__mapper__.c.id)
        ).first()
        if max:
            self.id = max.id + 1
        else:
            self.id = 1

    def getAll(self):
        return meta.Session.query(self.__class__).order_by(self.__class__.id).all()

    def getById(self, id=None):
        if not id: return
        result = None
        try:
            result = meta.Session.query(self.__class__).filter_by(id=id).one()
        except Exception, e:
            log.error(e)
        return result

    def getBySiteId(self, siteId=None):
        if not siteId: return
        result = None
        try:
            result = meta.Session.query(self.__class__).filter_by(siteId=siteId).one()
        except Exception, e:
            log.error(e)
        return result

    def getData(self):
        data = eval(self.string)
        return data

    def save(self, siteId=None, string=None):
        if not siteId or not string: return
        site = self.getBySiteId(siteId)
        if site:
            site.string = string
        else:
            self.siteId = siteId
            self.string = string
            self.addObject()
        meta.Session.commit()

    def addObject(self):
        self.getMaxId()
        return meta.Session.add(self)

    def deleteObject(self):
        return meta.Session.delete(self)


