LOG_LEVEL="{{ log_level }}"
RELEASE_SEQUENCE="{{ release_sequence }}"
UI_BIND_PORT="{{ ui_bind_port }}"
KUBERNETES_NAMESPACE="{{ kubernetes_namespace }}"
PV_BASE_PATH="{{ pv_base_path }}"
STORAGE_PROVISIONER="{{ storage_provisioner }}"
STORAGE_CLASS="{{ storage_class }}"
SERVICE_TYPE="{{ service_type }}"
PROXY_ADDRESS="{{ proxy_address }}"
NO_PROXY_ADDRESSES="{{ no_proxy_addresses }}"
IP_ALLOC_RANGE=10.32.0.0/12  # default for weave
CEPH_DASHBOARD_URL=
# booleans
AIRGAP="{{ airgap }}"
ENCRYPT_NETWORK="{{ encrypt_network }}"
WEAVE_SECRET=1
REPLICATED_YAML=1
REPLICATED_PVC=1
ROOK_SYSTEM_YAML=0
ROOK_CLUSTER_YAML=0
HOSTPATH_PROVISIONER_YAML=0
WEAVE_YAML=0
CONTOUR_YAML=0
DEPLOYMENT_YAML=0

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
        storage-provisioner|storage_provisioner)
            STORAGE_PROVISIONER="$_value"
            ;;
        storage-class|storage_class)
            STORAGE_CLASS="$_value"
            ;;
        service-type|service_type)
            SERVICE_TYPE="$_value"
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
        hostpath-provisioner-yaml|hostpath_provisioner_yaml)
            HOSTPATH_PROVISIONER_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        weave-yaml|weave_yaml)
            WEAVE_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        contour-yaml|contour_yaml)
            CONTOUR_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        deployment-yaml|deployment_yaml)
            DEPLOYMENT_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        ip-alloc-range|ip_alloc_range)
            IP_ALLOC_RANGE="$_value"
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        no-proxy-addresses|no_proxy_addresses)
            NO_PROXY_ADDRESSES="$_value"
            ;;
        encrypt-network|encrypt_network)
            ENCRYPT_NETWORK="$_value"
            ;;
        weave-secret|weave_secret)
            WEAVE_SECRET="$_value"
            ;;
        replicated-pvc|replicated_pvc)
            REPLICATED_PVC="$_value"
            ;;
        ceph-dashboard-url|ceph_dashboard_url)
            CEPH_DASHBOARD_URL="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

render_replicated_deployment() {
    # For airgap the local address is the hostIP so docker on remote nodes can
    # pull from the local registry.
    LOCAL_ADDRESS_SOURCE=status.podIP
    if [ "$AIRGAP" = "1" ]; then
        LOCAL_ADDRESS_SOURCE=status.hostIP
    fi

    # If using podID as the local address (non-airgap) then specify join address
    # for kubeadm on remote nodes
    K8S_MASTER_ADDRESS=
    if [ "$AIRGAP" != "1" ]; then
        K8S_MASTER_ADDRESS=$(cat <<-EOF
        - name: K8S_MASTER_ADDRESS
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
EOF
        )
    fi

    PROXY_ENVS=
    if [ -n "$PROXY_ADDRESS" ]; then
        PROXY_ENVS=$(cat <<-EOF
        - name: HTTP_PROXY
          value: $PROXY_ADDRESS
        - name: NO_PROXY
          value: $NO_PROXY_ADDRESSES
EOF
        )
    fi

    CEPH_DASHBOARD_ENV=
    if [ -n "$CEPH_DASHBOARD_URL" ]; then
        CEPH_DASHBOARD_ENV=$(cat <<-EOF
        - name: CEPH_DASHBOARD_URL
          value: $CEPH_DASHBOARD_URL
EOF
        )
    fi

    cat <<EOF
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
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "$DAEMON_NODE_KEY"
                operator: Exists
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
              fieldPath: "$LOCAL_ADDRESS_SOURCE"
$K8S_MASTER_ADDRESS
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
$PROXY_ENVS
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
$CEPH_DASHBOARD_ENV
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
EOF
}

render_replicated_pvc() {
    local size="10Gi"
    if [ "$AIRGAP" = "1" ]; then
        size="100Gi"
    fi
    cat <<EOF
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
      storage: "$size"
  storageClassName: "$STORAGE_CLASS"
EOF
}

render_replicated_specs() {
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
}

render_replicated_cluster_ip_service() {
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
}

render_replicated_node_port_service() {
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
}

render_replicated_ui_node_port_service() {
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
}

render_replicated_ui_service() {
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
    port: ${UI_BIND_PORT}
    targetPort: 8800
    protocol: TCP
EOF
}

render_rook_storage_class() {
    cat <<EOF
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: "$STORAGE_CLASS"
provisioner: ceph.rook.io/block
parameters:
  pool: replicapool
  clusterNamespace: rook-ceph
EOF
}

# https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/operator.yaml
# Deployment node affinity added to ensure image is available for airgap
render_rook_system_yaml() {
    cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph-system
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: cephclusters.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephCluster
    listKind: CephClusterList
    plural: cephclusters
    singular: cephcluster
  scope: Namespaced
  version: v1
  validation:
    openAPIV3Schema:
      properties:
        spec:
          properties:
            cephVersion:
              properties:
                allowUnsupported:
                  type: boolean
                image:
                  type: string
                name:
                  pattern: ^(luminous|mimic|nautilus)$
                  type: string
            dashboard:
              properties:
                enabled:
                  type: boolean
                urlPrefix:
                  type: string
            dataDirHostPath:
              pattern: ^/(\S+)
              type: string
            mon:
              properties:
                allowMultiplePerNode:
                  type: boolean
                count:
                  maximum: 9
                  minimum: 1
                  type: integer
              required:
              - count
            network:
              properties:
                hostNetwork:
                  type: boolean
            storage:
              properties:
                nodes:
                  items: {}
                  type: array
                useAllDevices: {}
                useAllNodes:
                  type: boolean
          required:
          - mon
  additionalPrinterColumns:
    - name: DataDirHostPath
      type: string
      description: Directory used on the K8s nodes
      JSONPath: .spec.dataDirHostPath
    - name: MonCount
      type: string
      description: Number of MONs
      JSONPath: .spec.mon.count
    - name: Age
      type: date
      JSONPath: .metadata.creationTimestamp
    - name: State
      type: string
      description: Current State
      JSONPath: .status.state
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: cephfilesystems.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephFilesystem
    listKind: CephFilesystemList
    plural: cephfilesystems
    singular: cephfilesystem
  scope: Namespaced
  version: v1
  additionalPrinterColumns:
    - name: MdsCount
      type: string
      description: Number of MDSs
      JSONPath: .spec.metadataServer.activeCount
    - name: Age
      type: date
      JSONPath: .metadata.creationTimestamp
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: cephobjectstores.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephObjectStore
    listKind: CephObjectStoreList
    plural: cephobjectstores
    singular: cephobjectstore
  scope: Namespaced
  version: v1
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: cephobjectstoreusers.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephObjectStoreUser
    listKind: CephObjectStoreUserList
    plural: cephobjectstoreusers
    singular: cephobjectstoreuser
  scope: Namespaced
  version: v1
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: cephblockpools.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephBlockPool
    listKind: CephBlockPoolList
    plural: cephblockpools
    singular: cephblockpool
  scope: Namespaced
  version: v1
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: volumes.rook.io
spec:
  group: rook.io
  names:
    kind: Volume
    listKind: VolumeList
    plural: volumes
    singular: volume
    shortNames:
    - rv
  scope: Namespaced
  version: v1alpha2
---
# The cluster role for managing all the cluster-specific resources in a namespace
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: rook-ceph-cluster-mgmt
  labels:
    operator: rook
    storage-backend: ceph
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  - pods
  - pods/log
  - services
  - configmaps
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
---
# The role for the operator to manage resources in the system namespace
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: Role
metadata:
  name: rook-ceph-system
  namespace: rook-ceph-system
  labels:
    operator: rook
    storage-backend: ceph
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - configmaps
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
  - daemonsets
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
---
# The cluster role for managing the Rook CRDs
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: rook-ceph-global
  labels:
    operator: rook
    storage-backend: ceph
rules:
- apiGroups:
  - ""
  resources:
  # Pod access is needed for fencing
  - pods
  # Node access is needed for determining nodes where mons should run
  - nodes
  - nodes/proxy
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - events
    # PVs and PVCs are managed by the Rook provisioner
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
  - storage.k8s.io
  resources:
  - storageclasses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - jobs
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
- apiGroups:
  - ceph.rook.io
  resources:
  - "*"
  verbs:
  - "*"
- apiGroups:
  - rook.io
  resources:
  - "*"
  verbs:
  - "*"
---
# Aspects of ceph-mgr that require cluster-wide access
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr-cluster
  labels:
    operator: rook
    storage-backend: ceph
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - nodes
  - nodes/proxy
  verbs:
  - get
  - list
  - watch
---
# The rook system service account used by the operator, agent, and discovery pods
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rook-ceph-system
  namespace: rook-ceph-system
  labels:
    operator: rook
    storage-backend: ceph
---
# Grant the operator, agent, and discovery agents access to resources in the rook-ceph-system namespace
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-system
  namespace: rook-ceph-system
  labels:
    operator: rook
    storage-backend: ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rook-ceph-system
subjects:
- kind: ServiceAccount
  name: rook-ceph-system
  namespace: rook-ceph-system
---
# Grant the rook system daemons cluster-wide access to manage the Rook CRDs, PVCs, and storage classes
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-global
  namespace: rook-ceph-system
  labels:
    operator: rook
    storage-backend: ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rook-ceph-global
subjects:
- kind: ServiceAccount
  name: rook-ceph-system
  namespace: rook-ceph-system
---
# The deployment for the rook operator
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: rook-ceph-operator
  namespace: rook-ceph-system
  labels:
    operator: rook
    storage-backend: ceph
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: rook-ceph-operator
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "$DAEMON_NODE_KEY"
                operator: Exists
      serviceAccountName: rook-ceph-system
      containers:
      - name: rook-ceph-operator
        image: rook/ceph:v0.9.0
        args: ["ceph", "operator"]
        volumeMounts:
        - mountPath: /var/lib/rook
          name: rook-config
        - mountPath: /etc/ceph
          name: default-config-dir
        env:
        - name: ROOK_ALLOW_MULTIPLE_FILESYSTEMS
          value: "false"
        # The logging level for the operator: INFO | DEBUG
        - name: ROOK_LOG_LEVEL
          value: "INFO"
        # The interval to check if every mon is in the quorum.
        - name: ROOK_MON_HEALTHCHECK_INTERVAL
          value: "45s"
        # The duration to wait before trying to failover or remove/replace the
        # current mon with a new mon (useful for compensating flapping network).
        - name: ROOK_MON_OUT_TIMEOUT
          value: "300s"
        # The duration between discovering devices in the rook-discover daemonset.
        - name: ROOK_DISCOVER_DEVICES_INTERVAL
          value: "60m"
        # Whether to start pods as privileged that mount a host path, which includes the Ceph mon and osd pods.
        # This is necessary to workaround the anyuid issues when running on OpenShift.
        # For more details see https://github.com/rook/rook/issues/1314#issuecomment-355799641
        - name: ROOK_HOSTPATH_REQUIRES_PRIVILEGED
          value: "false"
        # The name of the node to pass with the downward API
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        # The pod name to pass with the downward API
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        # The pod namespace to pass with the downward API
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
      volumes:
      - name: rook-config
        emptyDir: {}
      - name: default-config-dir
        emptyDir: {}
EOF
}

# https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/cluster.yaml
render_rook_cluster_yaml() {
    PV_BASE_PATH="${PV_BASE_PATH:-"/opt/replicated/rook"}"

    cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rook-ceph-osd
  namespace: rook-ceph
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rook-ceph-mgr
  namespace: rook-ceph
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-osd
  namespace: rook-ceph
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: [ "get", "list", "watch", "create", "update", "delete" ]
---
# Aspects of ceph-mgr that require access to the system namespace
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr-system
  namespace: rook-ceph
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
---
# Aspects of ceph-mgr that operate within the cluster's namespace
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr
  namespace: rook-ceph
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - jobs
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
- apiGroups:
  - ceph.rook.io
  resources:
  - "*"
  verbs:
  - "*"
---
# Allow the operator to create resources in this cluster's namespace
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-cluster-mgmt
  namespace: rook-ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rook-ceph-cluster-mgmt
subjects:
- kind: ServiceAccount
  name: rook-ceph-system
  namespace: rook-ceph-system
---
# Allow the osd pods in this namespace to work with configmaps
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-osd
  namespace: rook-ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rook-ceph-osd
subjects:
- kind: ServiceAccount
  name: rook-ceph-osd
  namespace: rook-ceph
---
# Allow the ceph mgr to access the cluster-specific resources necessary for the mgr modules
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr
  namespace: rook-ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rook-ceph-mgr
subjects:
- kind: ServiceAccount
  name: rook-ceph-mgr
  namespace: rook-ceph
---
# Allow the ceph mgr to access the rook system resources necessary for the mgr modules
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr-system
  namespace: rook-ceph-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rook-ceph-mgr-system
subjects:
- kind: ServiceAccount
  name: rook-ceph-mgr
  namespace: rook-ceph
---
# Allow the ceph mgr to access cluster-wide resources necessary for the mgr modules
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr-cluster
  namespace: rook-ceph
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rook-ceph-mgr-cluster
subjects:
- kind: ServiceAccount
  name: rook-ceph-mgr
  namespace: rook-ceph
---
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    # The container image used to launch the Ceph daemon pods (mon, mgr, osd, mds, rgw).
    # v12 is luminous, v13 is mimic, and v14 is nautilus.
    # RECOMMENDATION: In production, use a specific version tag instead of the general v13 flag, which pulls the latest release and could result in different
    # versions running within the cluster. See tags available at https://hub.docker.com/r/ceph/ceph/tags/.
    image: ceph/ceph:v12.2.8-20181023
    # Whether to allow unsupported versions of Ceph. Currently only luminous and mimic are supported.
    # After nautilus is released, Rook will be updated to support nautilus.
    # Do not set to true in production.
    allowUnsupported: false
  # The path on the host where configuration files will be persisted. If not specified, a kubernetes emptyDir will be created (not recommended).
  # Important: if you reinstall the cluster, make sure you delete this directory from each host or else the mons will fail to start on the new cluster.
  # In Minikube, the '/data' directory is configured to persist across reboots. Use "/data/rook" in Minikube environment.
  dataDirHostPath: /var/lib/replicated/rook
  # set the amount of mons to be started
  mon:
    count: 3
    allowMultiplePerNode: true
  # enable the ceph dashboard for viewing cluster status
  dashboard:
    enabled: true
  network:
    # toggle to use hostNetwork
    hostNetwork: false
  rbdMirroring:
    # The number of daemons that will perform the rbd mirroring.
    # rbd mirroring must be configured with "rbd mirror" from the rook toolbox.
    workers: 0
  # To control where various services will be scheduled by kubernetes, use the placement configuration sections below.
  # The example under 'all' would have all services scheduled on kubernetes nodes labeled with 'role=storage-node' and
  # tolerate taints with a key of 'storage-node'.
#  placement:
#    all:
#      nodeAffinity:
#        requiredDuringSchedulingIgnoredDuringExecution:
#          nodeSelectorTerms:
#          - matchExpressions:
#            - key: role
#              operator: In
#              values:
#              - storage-node
#      podAffinity:
#      podAntiAffinity:
#      tolerations:
#      - key: storage-node
#        operator: Exists
# The above placement information can also be specified for mon, osd, and mgr components
#    mon:
#    osd:
#    mgr:
  resources:
# The requests and limits set here, allow the mgr pod to use half of one CPU core and 1 gigabyte of memory
#    mgr:
#      limits:
#        cpu: "500m"
#        memory: "1024Mi"
#      requests:
#        cpu: "500m"
#        memory: "1024Mi"
# The above example requests/limits can also be added to the mon and osd components
#    mon:
#    osd:
  storage: # cluster level storage configuration and selection
    useAllNodes: true
    useAllDevices: false
    deviceFilter:
    location:
    config:
      # The default and recommended storeType is dynamically set to bluestore for devices and filestore for directories.
      # Set the storeType explicitly only if it is required not to use the default.
      # storeType: bluestore
      databaseSizeMB: "1024" # this value can be removed for environments with normal sized disks (100 GB or larger)
      journalSizeMB: "1024"  # this value can be removed for environments with normal sized disks (20 GB or larger)
      osdsPerDevice: "1" # this value can be overridden at the node or device level
# Cluster level list of directories to use for storage. These values will be set for all nodes that have no `directories` set.
    directories:
    - path: "$PV_BASE_PATH"
# Individual nodes and their config can be specified as well, but 'useAllNodes' above must be set to false. Then, only the named
# nodes below will be used as storage resources.  Each node's 'name' field should match their 'kubernetes.io/hostname' label.
#    nodes:
#    - name: "172.17.4.101"
#      directories: # specific directories to use for storage can be specified for each node
#      - path: "/rook/storage-dir"
#      resources:
#        limits:
#          cpu: "500m"
#          memory: "1024Mi"
#        requests:
#          cpu: "500m"
#          memory: "1024Mi"
#    - name: "172.17.4.201"
#      devices: # specific devices to use for storage can be specified for each node
#      - name: "sdb"
#      - name: "nvme01" # multiple osds can be created on high performance devices
#        config:
#          osdsPerDevice: "5"
#      config: # configuration can be specified at the node level which overrides the cluster level config
#        storeType: filestore
#    - name: "172.17.4.301"
#      deviceFilter: "^sd."
---
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  # The failure domain will spread the replicas of the data across different failure zones
  failureDomain: osd
  # The root of the crush hierarchy that will be used for the pool. If not set, will use "default".
  crushRoot: default
  # For a pool based on raw copies, specify the number of copies. A size of 1 indicates no redundancy.
  replicated:
    size: 1
EOF
}

render_hostpath_storage_class() {
    cat <<EOF
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: "$STORAGE_CLASS"
provisioner: replicated.com/hostpath
EOF
}

render_hostpath_provisioner_yaml() {
    PV_BASE_PATH="${PV_BASE_PATH:-"/opt/replicated/hostpath-provisioner"}"

    cat <<EOF
{% include 'kubernetes/yaml/hostpath_provisioner_deploy.yml' %}
EOF
}

render_weave_yaml() {
    weave_passwd_env=
    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        weave_passwd_env=$(cat <<-EOF
                - name: WEAVE_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: weave-passwd
                      key: weave-passwd
EOF
        )
        if [ "$WEAVE_SECRET" != "0" ]; then
            weave_password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
            cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: weave-passwd
  namespace: kube-system
stringData:
  weave-passwd: $weave_password
EOF
        fi
    fi

    cat <<EOF
---
apiVersion: v1
kind: List
items:
  - apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: weave-net
      labels:
        name: weave-net
      namespace: kube-system
  - apiVersion: rbac.authorization.k8s.io/v1beta1
    kind: ClusterRole
    metadata:
      name: weave-net
      labels:
        name: weave-net
    rules:
      - apiGroups:
          - ''
        resources:
          - pods
          - namespaces
          - nodes
        verbs:
          - get
          - list
          - watch
      - apiGroups:
          - networking.k8s.io
        resources:
          - networkpolicies
        verbs:
          - get
          - list
          - watch
      - apiGroups:
          - ''
        resources:
          - nodes/status
        verbs:
          - patch
          - update
  - apiVersion: rbac.authorization.k8s.io/v1beta1
    kind: ClusterRoleBinding
    metadata:
      name: weave-net
      labels:
        name: weave-net
    roleRef:
      kind: ClusterRole
      name: weave-net
      apiGroup: rbac.authorization.k8s.io
    subjects:
      - kind: ServiceAccount
        name: weave-net
        namespace: kube-system
  - apiVersion: rbac.authorization.k8s.io/v1beta1
    kind: Role
    metadata:
      name: weave-net
      labels:
        name: weave-net
      namespace: kube-system
    rules:
      - apiGroups:
          - ''
        resourceNames:
          - weave-net
        resources:
          - configmaps
        verbs:
          - get
          - update
      - apiGroups:
          - ''
        resources:
          - configmaps
        verbs:
          - create
  - apiVersion: rbac.authorization.k8s.io/v1beta1
    kind: RoleBinding
    metadata:
      name: weave-net
      labels:
        name: weave-net
      namespace: kube-system
    roleRef:
      kind: Role
      name: weave-net
      apiGroup: rbac.authorization.k8s.io
    subjects:
      - kind: ServiceAccount
        name: weave-net
        namespace: kube-system
  - apiVersion: extensions/v1beta1
    kind: DaemonSet
    metadata:
      name: weave-net
      labels:
        name: weave-net
      namespace: kube-system
    spec:
      minReadySeconds: 5
      template:
        metadata:
          labels:
            name: weave-net
        spec:
          containers:
            - name: weave
              command:
                - /home/weave/launch.sh
              env:
                - name: HOSTNAME
                  valueFrom:
                    fieldRef:
                      apiVersion: v1
                      fieldPath: spec.nodeName
                - name: IPALLOC_RANGE
                  value: $IP_ALLOC_RANGE
$weave_passwd_env
              image: 'weaveworks/weave-kube:2.5.0'
              livenessProbe:
                httpGet:
                  host: 127.0.0.1
                  path: /status
                  port: 6784
                initialDelaySeconds: 30
              resources:
                requests:
                  cpu: 10m
              securityContext:
                privileged: true
              volumeMounts:
                - name: weavedb
                  mountPath: /weavedb
                - name: cni-bin
                  mountPath: /host/opt
                - name: cni-bin2
                  mountPath: /host/home
                - name: cni-conf
                  mountPath: /host/etc
                - name: dbus
                  mountPath: /host/var/lib/dbus
                - name: lib-modules
                  mountPath: /lib/modules
                - name: xtables-lock
                  mountPath: /run/xtables.lock
            - name: weave-npc
              args: []
              env:
                - name: HOSTNAME
                  valueFrom:
                    fieldRef:
                      apiVersion: v1
                      fieldPath: spec.nodeName
              image: 'weaveworks/weave-npc:2.5.0'
              resources:
                requests:
                  cpu: 10m
              securityContext:
                privileged: true
              volumeMounts:
                - name: xtables-lock
                  mountPath: /run/xtables.lock
          hostNetwork: true
          hostPID: true
          restartPolicy: Always
          securityContext:
            seLinuxOptions: {}
          serviceAccountName: weave-net
          tolerations:
            - effect: NoSchedule
              operator: Exists
          volumes:
            - name: weavedb
              hostPath:
                path: /var/lib/weave
            - name: cni-bin
              hostPath:
                path: /opt
            - name: cni-bin2
              hostPath:
                path: /home
            - name: cni-conf
              hostPath:
                path: /etc
            - name: dbus
              hostPath:
                path: /var/lib/dbus
            - name: lib-modules
              hostPath:
                path: /lib/modules
            - name: xtables-lock
              hostPath:
                path: /run/xtables.lock
                type: FileOrCreate
      updateStrategy:
        type: RollingUpdate
EOF
}

render_contour_yaml() {
    cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: heptio-contour
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: contour
  namespace: heptio-contour
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressroutes.contour.heptio.com
  labels:
    component: ingressroute
spec:
  group: contour.heptio.com
  version: v1beta1
  scope: Namespaced
  names:
    plural: ingressroutes
    kind: IngressRoute
  additionalPrinterColumns:
    - name: FQDN
      type: string
      description: Fully qualified domain name
      JSONPath: .spec.virtualhost.fqdn
    - name: TLS Secret
      type: string
      description: Secret with TLS credentials
      JSONPath: .spec.virtualhost.tls.secretName
    - name: First route
      type: string
      description: First routes defined
      JSONPath: .spec.routes[0].match
    - name: Status
      type: string
      description: The current status of the IngressRoute
      JSONPath: .status.currentStatus
    - name: Status Description
      type: string
      description: Description of the current status
      JSONPath: .status.description
  validation:
    openAPIV3Schema:
      properties:
        spec:
          properties:
            virtualhost:
              properties:
                fqdn:
                  type: string
                  pattern: ^([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+[a-z]{2,}$
                tls:
                  properties:
                    secretName:
                      type: string
                      pattern: ^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$ # DNS-1123 subdomain
                    minimumProtocolVersion:
                      type: string
                      enum:
                        - "1.3"
                        - "1.2"
                        - "1.1"
            strategy:
              type: string
              enum:
                - RoundRobin
                - WeightedLeastRequest
                - Random
                - RingHash
                - Maglev
            healthCheck:
              type: object
              required:
                - path
              properties:
                path:
                  type: string
                  pattern: ^\/.*$
                intervalSeconds:
                  type: integer
                timeoutSeconds:
                  type: integer
                unhealthyThresholdCount:
                  type: integer
                healthyThresholdCount:
                  type: integer
            routes:
              type: array
              items:
                required:
                  - match
                properties:
                  match:
                    type: string
                    pattern: ^\/.*$
                  delegate:
                    type: object
                    required:
                      - name
                    properties:
                      name:
                        type: string
                        pattern: ^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$ # DNS-1123 subdomain
                      namespace:
                        type: string
                        pattern: ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ # DNS-1123 label
                  services:
                    type: array
                    items:
                      type: object
                      required:
                        - name
                        - port
                      properties:
                        name:
                          type: string
                          pattern: ^[a-z]([-a-z0-9]*[a-z0-9])?$ # DNS-1035 label
                        port:
                          type: integer
                        weight:
                          type: integer
                        strategy:
                          type: string
                          enum:
                            - RoundRobin
                            - WeightedLeastRequest
                            - Random
                            - RingHash
                            - Maglev
                        healthCheck:
                          type: object
                          required:
                            - path
                          properties:
                            path:
                              type: string
                              pattern: ^\/.*$
                            intervalSeconds:
                              type: integer
                            timeoutSeconds:
                              type: integer
                            unhealthyThresholdCount:
                              type: integer
                            healthyThresholdCount:
                              type: integer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: contour
  name: contour
  namespace: heptio-contour
spec:
  selector:
    matchLabels:
      app: contour
  replicas: 2
  template:
    metadata:
      labels:
        app: contour
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8002"
        prometheus.io/path: "/stats"
        prometheus.io/format: "prometheus"
    spec:
      containers:
      - image: gcr.io/heptio-images/contour:v0.8.0
        imagePullPolicy: Always
        name: contour
        command: ["contour"]
        args: ["serve", "--incluster"]
      - image: docker.io/envoyproxy/envoy-alpine:v1.7.0
        name: envoy
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8443
          name: https
        command: ["envoy"]
        args:
        - --config-path /config/contour.yaml
        - --service-cluster cluster0
        - --service-node node0
        - --log-level info
        - --v2-config-only
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8002
          initialDelaySeconds: 3
          periodSeconds: 3
        volumeMounts:
        - name: contour-config
          mountPath: /config
        lifecycle:
          preStop:
            exec:
              command: ["wget", "-qO-", "http://localhost:9001/healthcheck/fail"] 
      initContainers:
      - image: gcr.io/heptio-images/contour:v0.8.0
        imagePullPolicy: Always
        name: envoy-initconfig
        command: ["contour"]
        args:
        - bootstrap
        # Uncomment the statsd-enable to enable statsd metrics
        #- --statsd-enable
        # Uncomment to set a custom stats emission address and port
        #- --stats-address=0.0.0.0
        #- --stats-port=8002
        - /config/contour.yaml
        volumeMounts:
        - name: contour-config
          mountPath: /config
      volumes:
      - name: contour-config
        emptyDir: {}
      dnsPolicy: ClusterFirst
      serviceAccountName: contour
      terminationGracePeriodSeconds: 30
      # The affinity stanza below tells Kubernetes to try hard not to place 2 of
      # these pods on the same node.
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: contour
              topologyKey: kubernetes.io/hostname
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: contour
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: contour
subjects:
- kind: ServiceAccount
  name: contour
  namespace: heptio-contour
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: contour
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - endpoints
  - nodes
  - pods
  - secrets
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs:
  - get
  - list
  - watch
- apiGroups: ["contour.heptio.com"]
  resources: ["ingressroutes"]
  verbs:
  - get
  - list
  - watch
  - put
  - post
  - patch
---
apiVersion: v1
kind: Service
metadata:
 name: contour
 namespace: heptio-contour
 annotations:
  # This annotation puts the AWS ELB into "TCP" mode so that it does not
  # do HTTP negotiation for HTTPS connections at the ELB edge.
  # The downside of this is the remote IP address of all connections will
  # appear to be the internal address of the ELB. See docs/proxy-proto.md
  # for information about enabling the PROXY protocol on the ELB to recover
  # the original remote IP address.
  service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
spec:
 ports:
 - port: 80
   name: http
   protocol: TCP
   targetPort: 8080
   nodePort: 80
 - port: 443
   name: https
   protocol: TCP
   targetPort: 8443
   nodePort: 443
 selector:
   app: contour
 type: NodePort
EOF
}

################################################################################
# Execution starts here
################################################################################

if [ "$WEAVE_YAML" = "1" ]; then
    render_weave_yaml
fi

if [ "$CONTOUR_YAML" = "1" ]; then
    render_contour_yaml
fi

if [ "$ROOK_CLUSTER_YAML" = "1" ]; then
    render_rook_cluster_yaml
fi

if [ "$ROOK_SYSTEM_YAML" = "1" ]; then
    render_rook_system_yaml
fi

if [ "$HOSTPATH_PROVISIONER_YAML" = "1" ]; then
    render_hostpath_provisioner_yaml
fi

if [ "$REPLICATED_YAML" = "1" ]; then
    case "$STORAGE_PROVISIONER" in
        rook|1)
            render_rook_storage_class
            ;;
        hostpath)
            render_hostpath_storage_class
            ;;
        0|"")
            ;;
        *)
            bail "Error: unknown storage provisioner \"$STORAGE_PROVISIONER\""
            ;;
    esac

    if [ "$REPLICATED_PVC" != "0" ]; then
        render_replicated_pvc
    fi
    render_replicated_specs
    render_replicated_deployment

    if [ "$AIRGAP" = "1" ]; then
        render_replicated_node_port_service
    else
        render_replicated_cluster_ip_service
    fi

    if [ "$SERVICE_TYPE" = "NodePort" ]; then
        render_replicated_ui_node_port_service
    else
        render_replicated_ui_service
    fi
fi

if [ "$DEPLOYMENT_YAML" = "1" ]; then
    render_replicated_deployment
fi
