Mongo replica set watcher (adjusted for Rancher)
---
*Little* bash script, wrapped into a docker container, to be ground control
for any mongo replica set within [Rancher](http://rancher.com/).

Environment
---
* `MONGO_REPLSET` ..name of replica set
> "rs0"
* `VERBOSE` ..verbose level according to [https://en.wikipedia.org/wiki/Syslog#Severity_level](https://en.wikipedia.org/wiki/Syslog#Severity_level)
> 6
* `META_URL` ..rancher meta data url [http://docs.rancher.com/rancher/metadata-service/](http://docs.rancher.com/rancher/metadata-service/)
> "http://rancher-metadata/2015-07-25"
* `SERVICE` .. (dns) service name
> "mongo"
* `HOST_LABEL` .. host label for mongo instance preference [http://docs.rancher.com/rancher/rancher-ui/infrastructure/hosts/custom/#host-labels](http://docs.rancher.com/rancher/rancher-ui/infrastructure/hosts/custom/#host-labels)
> "mongo"
* `INTERVAL` .. instance lookup interval (in secs)
> 30
* `MAINTENANCE` .. if mongo instance preferences are of when to recondig replica set. (as [cron tab expression1](https://github.com/fentas/cronexpr))
> "@daily"
* `AUTHENTICATION` .. mongo authentication (has to be admin to reconfig cluster) (as "<user>:<password>")
> ""

TODO
---
Work in progress.

Usage
---
command line
```sh

```

docker-compose
```yml

```

Behavior
---
TODO: Describe..

Light reading
---
* [http://docs.rancher.com/rancher/](http://docs.rancher.com/rancher/)
* [https://docs.mongodb.org/manual/core/replica-set-members/](https://docs.mongodb.org/manual/core/replica-set-members/)
* [https://docs.mongodb.org/manual/reference/method/rs.reconfig/#rs.reconfig](https://docs.mongodb.org/manual/reference/method/rs.reconfig/#rs.reconfig)

Contributing
---
Alway welcome. Feel free to create issues or pull requests.

Licence
---
AGPLv3 - [http://choosealicense.com/licenses/agpl-3.0/](http://choosealicense.com/licenses/agpl-3.0/)
