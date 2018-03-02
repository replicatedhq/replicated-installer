
AIRGAP=0
GROUP_ID=
LOG_LEVEL=info
NO_PROXY=1

PUBLIC_ADDRESS=
PRIVATE_ADDRESS=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
PV_BASE_PATH="/opt/replicated/hostpath-provisioner"
SKIP_DOCKER_PULL=0
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # arigap implies "no proxy" and "skip docker"
            AIRGAP=1
            NO_PROXY=1
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        kubernetes-namespace|kubernetes_namespace)
            KUBERNETES_NAMESPACE="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        pv-base-path|pv_base__path)
            PV_BASE_PATH="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
        # TODO custom SELinux domain
    esac
    shift
done

cat <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: replicated
  labels:
    app: replicated
    tier: master
spec:
  template:
    metadata:
      labels:
        app: replicated
        tier: master
    spec:
      serviceAccountName: default
      containers:
      - name: replicated
        image: "{{ replicated_docker_host }}/replicated/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        env:
        - name: SCHEDULER_ENGINE
          value: kubernetes
        - name: RELEASE_CHANNEL
          value: "{{ channel_name }}"{% if release_sequence %}
        - name: RELEASE_SEQUENCE
          value: "$RELEASE_SEQUENCE"
{%- endif %}{% if replicated_env == "staging" %}
        - name: MARKET_BASE_URL
          value: https://api.staging.replicated.com/market
        - name: DATA_BASE_URL
          value: https://data.staging.replicated.com/market
        - name: VENDOR_REGISTRY
          value: registry.staging.replicated.com
        - name: INSTALLER_URL
          value: https://get.staging.replicated.com
        - name: REPLICATED_IMAGE_TAG_SUFFIX
          value: .staging
{%- endif %}
        - name: LOCAL_ADDRESS # TODO: deprecate this
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: K8S_STORAGECLASS
          value: default
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"{% if custom_selinux_replicated_domain %}
        - name: SELINUX_REPLICATED_DOMAIN
          value: "{{ selinux_replicated_domain }}"
{%- endif %}
        ports:
        - containerPort: 9874
        - containerPort: 9877
        - containerPort: 9878
        securityContext:
          seLinuxOptions:
            type: "{{ selinux_replicated_domain }}"
        volumeMounts:
        - name: replicated-persistent
          mountPath: /var/lib/replicated
        - name: replicated-socket
          mountPath: /var/run/replicated
        - name: docker-socket
          mountPath: /host/var/run/docker.sock
        - name: replicated-conf
          mountPath: /host/etc/replicated.conf
        - name: proc
          mountPath: /host/proc
          readOnly: true
      - name: replicated-ui
        image: "{{ replicated_docker_host }}/replicated/replicated-ui:{{ replicated_ui_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        env:
        - name: RELEASE_CHANNEL
          value: "{{ channel_name }}"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        ports:
        - containerPort: 8800
        securityContext:
          seLinuxOptions:
            type: "{{ selinux_replicated_domain }}"
        volumeMounts:
        - name: replicated-socket
          mountPath: /var/run/replicated
      volumes:
      - name: replicated-persistent
        persistentVolumeClaim:
          claimName: replicated-pv-claim
      - name: replicated-socket
      - name: docker-socket
        hostPath:
          path: /var/run/docker.sock
      - name: replicated-conf
        hostPath:
          path: /etc/replicated.conf
      - name: proc
        hostPath:
          path: /proc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replicated-premkit-data-volume
  labels:
    app: replicated
    tier: premkit
  annotations:
    volume.beta.kubernetes.io/storage-class: "default"
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: replicated-hostpath-provisioner
spec:
  replicas: 1
  template:
    metadata:
      labels:
        tier: controller
        kind: storage-provisioner
    spec:
      containers:
      - name: provisioner
        image: quay.io/replicated/replicated-hostpath-provisioner:93a99cb
        imagePullPolicy: IfNotPresent
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: PV_BASE_PATH
          value: "$PV_BASE_PATH"
        volumeMounts:
          - name: pv-volume
            mountPath: /opt/replicated/hostpath-provisioner
      volumes:
        - name: pv-volume
          hostPath:
            path: /opt/replicated/hostpath-provisioner
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replicated-pv-claim
  labels:
    app: replicated
    tier: master
  annotations:
    volume.beta.kubernetes.io/storage-class: "default"
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replicated-statsd-graphite-storage
  labels:
    app: replicated
    tier: statsd
  annotations:
    volume.beta.kubernetes.io/storage-class: "default"
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: default
provisioner: replicated.com/hostpath
---
apiVersion: v1
kind: Service
metadata:
  name: replicated
  labels:
    app: replicated
    tier: master
spec:
  type: ClusterIP
  selector:
    app: replicated
    tier: master
  ports:
  - name: replicated-ui
    port: 8800
    protocol: TCP
  - name: replicated-registry
    port: 9874
    protocol: TCP
  - name: replicated-iapi
    port: 9877
    protocol: TCP
  - name: replicated-snapshots
    port: 9878
    protocol: TCP
  - name: replicated-support
    port: 9881
    protocol: TCP
    targetPort: 9881
---
apiVersion: v1
kind: Service
metadata:
  name: replicated-node
  labels:
    app: replicated
    tier: master
spec:
  type: NodePort
  selector:
    app: replicated
    tier: master
  ports:
  - name: replicated-ui
    port: 8800
    nodePort: ${UI_BIND_PORT}
    protocol: TCP
  - name: replicated-registry
    port: 9874
    nodePort: 9874
    protocol: TCP
  - name: replicated-iapi
    port: 9877
    nodePort: 9877
    protocol: TCP
  - name: replicated-snapshots
    port: 9878
    nodePort: 9878
    protocol: TCP
  - name: replicated-support
    port: 9881
    nodePort: 9881
    protocol: TCP
    targetPort: 9881

EOF

