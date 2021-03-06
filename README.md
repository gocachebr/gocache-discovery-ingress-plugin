# GoCache Api Discovery plugin
This plugin mirrors the traffic without copying actual data, only the schema.

## Environment variables needed

### GOCACHE_DISCOVERY_TOKEN

Authentication token, you can get it from GoCache support chat or in the api discovery section of the panel

### GOCACHE_DISCOVERY_MAX_REQUESTS_STORED (optional)

Maximum amount of requests that would be stored to be sent at once in a single request. Increasing this number can delay the discovery process in a few minutes depending on the request rate, but it helps reducing the outgoing requests to the discovery, as it will condense in a single one.
*Default*: 50

### GOCACHE_DISCOVERY_REQUEST_RETENTION_SECONDS (optional)

If by any reason, the requests never reach the maximum define at `GOCACHE_DISCOVERY_MAX_REQUESTS_STORED`, the remaining requests can be sent after a certain time.
*Default*: 60

### GOCACHE_DISCOVERY_DNS_NAMESERVERS (optional)

Set default resolver DNS for the discovery telemetry service. Usually there is no need to change it, this section is here just to resolve the GOCACHE_DISCOVERY_HOSTNAME.
*Default*: "8.8.8.8, 8.8.8.9"

### GOCACHE_DISCOVERY_HOSTNAME (optional)

*Default*: "api-inventory.gocache.com.br"

## Installation

### Using helm

You need to add an `extraInitContainers` directive to your helm config:
```yaml
extraInitContainers:
  - image: k8s.gcr.io/git-sync/git-sync:v3.1.7
    name: init-clone-plugins
    imagePullPolicy: Always
    volumeMounts:
    - name: lua-plugins
      mountPath: /plugins
    env:
    - name: GIT_SYNC_REPO
      value: "https://github.com/gocachebr/gocache-discovery-ingress-plugin.git"
    - name: GIT_SYNC_BRANCH
      value: "main"
    - name: GIT_SYNC_ROOT
      value: "/plugins"
    - name: GIT_SYNC_DEST
      value: "gocache"
    - name: GIT_SYNC_ONE_TIME
      value: "true"
    - name: GIT_SYNC_DEPTH
      value: "1"
```

Then, mount the volumes for the plugin:
```yaml
  extraVolumes:
  - name: lua-plugins
    emptyDir: {}
  extraVolumeMounts:
  - name: lua-plugins
    mountPath: /etc/nginx/lua/plugins
```
Add another section for the envs:
```yaml
  extraEnvs:
  - name: GOCACHE_DISCOVERY_TOKEN
    value: "<yourtoken>"
  - name: GOCACHE_DISCOVERY_ADDERESS
    value: "129.159.62.11"
  - name: GOCACHE_DISCOVERY_HOSTNAME
  	value: api-inventory.gocache.com.br
```
And finally, enable the plugin:

```yaml
config:
    plugins: gocache
    lua-shared-dicts: "gocache: 30M"
```

Here's the full controller, let's say you named it `values.yaml`:
```yaml
controller:
  extraEnvs:
  - name: GOCACHE_DISCOVERY_TOKEN
    value: "<yourtoken>"
  - name: GOCACHE_DISCOVERY_ADDERESS
    value: "129.159.62.11"
  - name: GOCACHE_DISCOVERY_HOSTNAME
  	value: api-inventory.gocache.com.br
  extraVolumes:
  - name: lua-plugins
    emptyDir: {}
  extraInitContainers:
  - image: k8s.gcr.io/git-sync/git-sync:v3.1.7
    name: init-clone-plugins
    imagePullPolicy: Always
    volumeMounts:
    - name: lua-plugins
      mountPath: /plugins
    env:
    - name: GIT_SYNC_REPO
      value: "https://github.com/gocachebr/gocache-discovery-ingress-plugin.git"
    - name: GIT_SYNC_BRANCH
      value: "main"
    - name: GIT_SYNC_ROOT
      value: "/plugins"
    - name: GIT_SYNC_DEST
      value: "gocache"
    - name: GIT_SYNC_ONE_TIME
      value: "true"
    - name: GIT_SYNC_DEPTH
      value: "1"
  extraVolumeMounts:
  - name: lua-plugins
    mountPath: /etc/nginx/lua/plugins
  config:
    plugins: gocache
    lua-shared-dicts: "gocache: 30M"
```

Once done, you can apply it:
```bash
helm install --version 4.1.2 ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx -f values.yaml
```
Or:
```bash
helm upgrade ingress-nginx -f values.yaml ingress-nginx/ingress-nginx -n ingress-nginx
```

### Using baremetal containers

inside your deploy.yaml that usually are provided by ingress itself, there is a section for `Deployment`. In that section you must create the volumes, set some environment variables and add an `initContainer` for the plugin code itself.

Here's all the fields needed:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  ...
spec:
  ...
  template:
    ...
    spec:
      initContainers:
      - image: k8s.gcr.io/git-sync/git-sync:v3.1.7
        name: init-clone-plugins
        imagePullPolicy: Always
        volumeMounts:
        - name: lua-plugins
          mountPath: /plugins
        env:
        - name: GIT_SYNC_REPO
          value: "https://github.com/gocachebr/gocache-discovery-ingress-plugin.git"
        - name: GIT_SYNC_BRANCH
          value: "main"
        - name: GIT_SYNC_ROOT
          value: "/plugins"
        - name: GIT_SYNC_DEST
          value: "gocache"
        - name: GIT_SYNC_ONE_TIME
          value: "true"
        - name: GIT_SYNC_DEPTH
          value: "1"
      containers:
      - args:
        ...
        env:
        ...
        - name: GOCACHE_DISCOVERY_ADDERESS
          value: "129.159.62.11"
        - name: GOCACHE_DISCOVERY_HOSTNAME
  		  value: api-inventory.gocache.com.br
        - name: GOCACHE_DISCOVERY_TOKEN
          value: "<yourtoken>"
        ...
        volumeMounts:
        ...
        - name: lua-plugins
          mountPath: /etc/nginx/lua/plugins
      ...
      volumes:
      - name: webhook-cert
        secret:
          secretName: ingress-nginx-admission
      - name: lua-plugins
        emptyDir: {}
```

### Config map method

There is an alternative method for installing the plugin using the config map instead of the git-sync method.
To make it simple, follow the previous steps but remove all the section from `initContainer` or `extraInitContainers`

Then you need to adjust the volumes accordingly

#### HELM volumes

```yaml
extraVolumes:
  - name: gocache-plugin
    configMap:
      name: gocache-plugin
  extraVolumeMounts:
  - name: gocache-plugin
    mountPath: /etc/nginx/lua/plugins/gocache/
```

#### Baremetal volumes

```yaml
...
	volumeMounts:
    - name: gocache-plugin
      mountPath: /etc/nginx/lua/plugins/gocache/
volumes:
- name: gocache-plugin
  configMap:
  name: gocache-plugin
```

#### Config map itself

Now, you can create a file called `gocache-plugin.yaml` and add the following in it:
```yaml
apiVersion: v1
kind: ConfigMap
data:
  main.lua: |
  	<plugin code here>
metadata:
  name: gocache-plugin
  namespace: ingress-nginx

```

Note that is needed to copy the content of the main.lua to the section highlighted in the config map, otherwise you will get an error or empty config file. Another important thing is that you might need to change the namespace accordingly to the setup previously.

Once done, you can apply the config
```bash
kubectl apply -f gocache-plugin.yaml
```

