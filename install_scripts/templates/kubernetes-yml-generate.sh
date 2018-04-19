AIRGAP="{{ airgap }}"
LOG_LEVEL="{{ log_level }}"
RELEASE_SEQUENCE="{{ release_sequence }}"
UI_BIND_PORT="{{ ui_bind_port }}"
KUBERNETES_NAMESPACE="{{ kubernetes_namespace }}"
PV_BASE_PATH="{{ pv_base_path }}"
STORAGE_CLASS="{{ storage_class }}"
SERVICE_TYPE="{{ service_type }}"
# booleans
AIRGAP="{{ airgap }}"
STORAGE_PROVISIONER="{{ storage_provisioner }}"
REPLICATED_YAML=1
ROOK_SYSTEM_YAML=0
ROOK_CLUSTER_YAML=0

{% include 'common/kubernetes.sh' %}

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        kubernetes-namespace|kubernetes_namespace)
            KUBERNETES_NAMESPACE="$_value"
            ;;
        pv-base-path|pv_base_path)
            PV_BASE_PATH="$_value"
            ;;
        storage-class|storage_class)
            STORAGE_CLASS="$_value"
            ;;
        service-type|service_type)
            SERVICE_TYPE="$_value"
            ;;
        storage-provisioner|storage_provisioner)
            STORAGE_PROVISIONER="$_value"
            ;;
        replicated-yaml|replicated_yaml)
            REPLICATED_YAML="$_value"
            ;;
        rook-system-yaml|rook_system_yaml)
            ROOK_SYSTEM_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-cluster-yaml|rook_cluster_yaml)
            ROOK_CLUSTER_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

AFFINITY=
if [ "$AIRGAP" = "1" ]; then
    AFFINITY=$(cat <<-EOF
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "$DAEMON_NODE_KEY"
                operator: Exists
EOF
)
fi

# For airgap the local address is the hostIP so docker on remote nodes can pull
# from the local registry.
LOCAL_ADDRESS_SOURCE=status.podIP
if [ "$AIRGAP" = "1" ]; then
    LOCAL_ADDRESS_SOURCE=status.hostIP
fi

if [ "$REPLICATED_YAML" = "1" ]; then
    if [ "$STORAGE_PROVISIONER" = "1" ]; then
        cat <<EOF
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: "$STORAGE_CLASS"
provisioner: rook.io/block
parameters:
  pool: replicapool
EOF
    fi

    cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: replicated-admin
  namespace: "$KUBERNETES_NAMESPACE"
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: ServiceAccount
    name: default
    namespace: "$KUBERNETES_NAMESPACE"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: replicated
  labels:
    app: replicated
    tier: master
spec:
  selector:
    matchLabels:
      app: replicated
      tier: master
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: replicated
        tier: master
    spec:
$AFFINITY
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
{%- endif %}{% if customer_base_url_override %}
        - name: MARKET_BASE_URL
          value: "{{customer_base_url_override}}"
{%- endif %}{% if replicated_env == "staging" %}
        - name: MARKET_BASE_URL
          value: {{ customer_base_url_override|default('https://api.staging.replicated.com/market', true) }}
        - name: DATA_BASE_URL
          value: https://data.staging.replicated.com/market
        - name: VENDOR_REGISTRY
          value: registry.staging.replicated.com
        - name: INSTALLER_URL
          value: https://get.staging.replicated.com
        - name: REPLICATED_IMAGE_TAG_SUFFIX
          value: .staging
{%- endif %}
        - name: LOCAL_ADDRESS
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: K8S_STORAGECLASS
          value: "$STORAGE_CLASS"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: AIRGAP
          value: "$AIRGAP"
        ports:
        - containerPort: 9874
        - containerPort: 9877
        - containerPort: 9878
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
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: "$STORAGE_CLASS"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replicated-pv-claim
  labels:
    app: replicated
    tier: master
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "$STORAGE_CLASS"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replicated-statsd-graphite-storage
  labels:
    app: replicated
    tier: statsd
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "$STORAGE_CLASS"
EOF
    if [ "$AIRGAP" = "1" ]; then
        cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated
  labels:
    app: replicated
    tier: master
spec:
  type: NodePort
  selector:
    app: replicated
    tier: master
  ports:
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
EOF
    else
        cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated
  labels:
    app: replicated
    tier: master
spec:
  selector:
    app: replicated
    tier: master
  ports:
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
EOF
    fi

    if [ "$SERVICE_TYPE" = "NodePort" ]; then
        cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated-ui
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
EOF
    else
        cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated-ui
  labels:
    app: replicated
    tier: master
spec:
  type: "$SERVICE_TYPE"
  selector:
    app: replicated
    tier: master
  ports:
  - name: replicated-ui
    port: 8800
    protocol: TCP
EOF
    fi
fi

if [ "$ROOK_SYSTEM_YAML" = "1" ]; then
    cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: rook-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rook-operator
rules:
- apiGroups:
  - ""
  resources:
  - namespaces
  - serviceaccounts
  - secrets
  - pods
  - services
  - nodes
  - nodes/proxy
  - configmaps
  - events
  - persistentvolumes
  - persistentvolumeclaims
  verbs:
  - get
  - list
  - watch
  - patch
  - create
  - update
  - delete
- apiGroups:
  - extensions
  resources:
  - thirdpartyresources
  - deployments
  - daemonsets
  - replicasets
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - get
  - list
  - watch
  - create
  - delete
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - clusterroles
  - clusterrolebindings
  - roles
  - rolebindings
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
- apiGroups:
  - storage.k8s.io
  resources:
  - storageclasses
  verbs:
  - get
  - list
  - watch
  - delete
- apiGroups:
  - rook.io
  resources:
  - "*"
  verbs:
  - "*"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rook-operator
  namespace: rook-system
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rook-operator
  namespace: rook-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rook-operator
subjects:
- kind: ServiceAccount
  name: rook-operator
  namespace: rook-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-operator
  namespace: rook-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rook-operator
  template:
    metadata:
      labels:
        app: rook-operator
    spec:
      serviceAccountName: rook-operator
      containers:
      - name: rook-operator
        image: rook/rook:v0.7.1
        args: ["operator"]
        env:
        # To disable RBAC, uncomment the following:
        # - name: RBAC_ENABLED
        #  value: "false"
        # Rook Agent toleration. Will tolerate all taints with all keys.
        # Choose between NoSchedule, PreferNoSchedule and NoExecute:
        # - name: AGENT_TOLERATION
        #  value: "NoSchedule"
        # (Optional) Rook Agent toleration key. Set this to the key of the taint you want to tolerate
        # - name: AGENT_TOLERATION_KEY
        #  value: "<KeyOfTheTaintToTolerate>"
        # Set the path where the Rook agent can find the flex volumes
        # - name: FLEXVOLUME_DIR_PATH
        #  value: "<PathToFlexVolumes>"
        # The interval to check if every mon is in the quorum.
        - name: ROOK_MON_HEALTHCHECK_INTERVAL
          value: "45s"
        # The duration to wait before trying to failover or remove/replace the
        # current mon with a new mon (useful for compensating flapping network).
        - name: ROOK_MON_OUT_TIMEOUT
          value: "300s"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
EOF
fi

if [ "$ROOK_CLUSTER_YAML" = "1" ]; then
    cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
    name: rook
---
apiVersion: rook.io/v1alpha1
kind: Cluster
metadata:
  name: rook
  namespace: rook
spec:
  versionTag: v0.7.1
  dataDirHostPath: /var/lib/replicated/rook
  storage:
    useAllNodes: true
    useAllDevices: false
    storeConfig:
      storeType: filestore
      journalSizeMB: 1024
    directories:
    - path: "{{ pv_base_path }}"
---
apiVersion: rook.io/v1alpha1
kind: Pool
metadata:
  name: replicapool
  namespace: rook
spec:
  replicated:
    size: 1
EOF
fi
