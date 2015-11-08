Mongo replica set watcher (adjusted for Rancher)
---
*Little* bash script, wrapped into a docker container, to be ground control
for any mongo replica set within [Rancher](http://rancher.com/).

Environment
---
* `MONGO_REPLSET` ..name of replica set
> "rs0"

* `PORT` ..port for mongo instances
> 27017

* `VERBOSE` ..verbose level according to [https://en.wikipedia.org/wiki/Syslog#Severity_level](https://en.wikipedia.org/wiki/Syslog#Severity_level)
> 6

* `META_URL` ..rancher [meta data](http://docs.rancher.com/rancher/metadata-service/) url
> "http://rancher-metadata/2015-07-25"

* `SERVICE` ..(dns) service name
> "mongo-replset"

* `HOST_LABEL` ..[host label](http://docs.rancher.com/rancher/rancher-ui/infrastructure/hosts/custom/#host-labels) for mongo instance preference
> "mongo"

* `INTERVAL` ..instance lookup interval (in secs)
> 30

* `MAINTENANCE` ..if mongo instance preferences are of when to recondig replica set. (as [cron tab expression](https://github.com/fentas/cronexpr))
> "@daily"

* `AUTHENTICATION` ..needs admin permissions! (as "<< user >>**:**<< password >>")
> ""

Behavior
---
Checks every mongod instance behind a service and compares it to its
host label (as means of configuration).
This can be `primary`, `secondary`, `arbiter` and `hidden`.

If the replica set is not initialized yet, it will force `reconfig` accordingly to
the given host labels. (e.g. if `arbiter` **priority** of this member will be **0** and
*arbiterOnly* **true**)

If it is already initialized and there are any missfits, a `reconfig` will be
triggered on the specified `MAINTINACE` time.

Also it has an eye on newcomers and stales. Meaning it will *add* or *remove*
this instances accordingly. **Notice** if a `hidden` instance is newly added it will
be **not** hidden until a `reconfig`.

Workflow
---
First consider to create a config file for mongod on each host.
> Here one example for **PRIMARY**, **SECONDARY**, **ARBITER** construct.
> (`/data/mongo/mongod.yml`)

**If you expose port 27017 you need at least 3 different hosts.**

##### PRIMARY
```yml
storage:
  dbPath: "/data/db/"
  directoryPerDB: true
  journal:
    enabled: true
net:
  bindIp: 127.0.0.1
  port: 27017
security:
  # same key on every host
  keyFile: "/data/key/mongo-rs0.key"
  #TODO: first create admin user
  #authorization: "enabled"
replication:
  # usually takes 5% of free space. Set this depending on free space.
  oplogSizeMB: 10240
  replSetName: "rs0"
```
##### SECONDARY
```yml
# secondary
storage:
  dbPath: "/data/db/"
  directoryPerDB: true
  journal:
    enabled: true
net:
  bindIp: 127.0.0.1
  port: 27017
security:
  keyFile: "/data/key/mongo-rs0.key"
  #TODO: first create admin user
  #authorization: "enabled"
replication:
  # usually takes 5% of free space.
  oplogSizeMB: 10240
  replSetName: "rs0"
```
##### ARBITER
```yml
# arbiter
storage:
  dbPath: "/data/arb/"
  directoryPerDB: true
  journal:
    enabled: false
  mmapv1:
    smallFiles: true
net:
  bindIp: 127.0.0.1
  port: 27017
security:
  keyFile: "/data/key/mongo-rs0.key"
  #TODO: first create admin user
#   authorization: "enabled"
replication:
  # arbiter do not have any data. Prevent space allocation.
  oplogSizeMB: 8
  replSetName: "rs0"
```

Then add your hosts to Rancher. Each with a label named `mongo`. As value for
this label you specify the role of of the mongo instance. You can add host
labels on first time registration over cli or using `rancher/server` ui.
[See here for more](http://docs.rancher.com/rancher/rancher-ui/infrastructure/hosts/custom/#host-labels)

Now start your mongod instances, easily on specifying `mongo` key as schedule
requirement.
[See here for more](http://docs.rancher.com/rancher/concepts/scheduling/)
> Here's an example.

##### rancher-compose.yml
```yml
mongo-replSet-rs0:
  scale: 3
```

##### docker-compose.yml
```yml
mongo-replSet-rs0:
  container_name: mongo-replSet-rs0
  image: mongo:3.0
  command: mongod --config /mongod.yml
  stdin_open: true
  tty: true
  restart: always
  ports:
    - "27017:27017"
  volumes:
    - /data/mongo/mongod.yml:/mongod.yml:ro
  labels:
    io.rancher.scheduler.affinity:host_label: mongo in (primary, secondary, arbiter, hidden)
  health_check:
    port: 27017
    interval: 2000
    healthy_threshold: 2
    unhealthy_threshold: 3
    response_timeout: 2000
```

After that there should be 3 mongod instances running on the specified hosts.
This leaves you with the last step, starting this docker container.
> Maybe like this.

##### rancher-compose.yml
```yml
mongo-replSet-watch:
  scale: 1
```

##### docker-compose.yml
```yml
mongo-replSet-watch:
  image: fentas/mongo-replset:latest
  stdin_open: true
  tty: true
  restart: always
  links:
  - mongo-replSet-rs0:mongo-replset
  environment:
    SERVICE: "mongo-replSet"
    MONGO_REPLSET: "rs0"
    AUTHENTICATION: "<admin user>:<password>"
  labels:
    # do this if you have more then 3 hosts (for this example)
    io.rancher.scheduler.affinity:host_label_ne: mongo in (primary, secondary, arbiter, hidden)
    io.rancher.container.pull_image: always
```

This shoud be it.

TODOs
---
* Testing
* Then uploading to docker hub.
* Work in progress. Any ideas?

Light reading
---
* [http://docs.rancher.com/rancher/](http://docs.rancher.com/rancher/)
* [https://docs.mongodb.org/manual/core/replica-set-members/](https://docs.mongodb.org/manual/core/replica-set-members/)
* [https://docs.mongodb.org/manual/reference/method/rs.reconfig/#rs.reconfig](https://docs.mongodb.org/manual/reference/method/rs.reconfig/#rs.reconfig)

Contributing
---
Alway welcome. Feel free to create issues or pull requests.

Originally forked from [https://github.com/azenk/mongodb-kubernetes](https://github.com/azenk/mongodb-kubernetes)

Licence
---
AGPLv3 - [http://choosealicense.com/licenses/agpl-3.0/](http://choosealicense.com/licenses/agpl-3.0/)
