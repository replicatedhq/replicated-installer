#!/bin/bash

set -e

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
REPLICATED_DOCKER_HOST="{{ replicated_docker_host }}"
# replicated components registry
REGISTRY_ADDRESS_OVERRIDE="{{ registry_address_override }}"
APP_REGISTRY_ADVERTISE_HOST="{{ app_registry_advertise_host }}"
IP_ALLOC_RANGE=10.32.0.0/12  # default for weave
CEPH_DASHBOARD_URL=
CEPH_DASHBOARD_USER=
CEPH_DASHBOARD_PASSWORD=
# booleans
AIRGAP="{{ airgap }}"
ENCRYPT_NETWORK="{{ encrypt_network }}"
WEAVE_SECRET=1
REPLICATED_YAML=1
REPLICATED_PVC=1
ROOK_SYSTEM_YAML=0
ROOK_CLUSTER_YAML=0
STORAGE_CLASS_YAML=0
HOSTPATH_PROVISIONER_YAML=0
WEAVE_YAML=0
CONTOUR_YAML=0
DEPLOYMENT_YAML=0
REGISTRY_YAML=0
REK_OPERATOR_YAML=0
BIND_DAEMON_NODE=0
API_SERVICE_ADDRESS="{{ api_service_address }}"
HA_CLUSTER="{{ ha_cluster }}"

{% include 'common/kubernetes.sh' %}

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            BIND_DAEMON_NODE=1
            ;;
        bind-daemon-node|bind_daemon_node)
            BIND_DAEMON_NODE=1
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
        ha)
            HA_CLUSTER=1
            ;;
        api-service-address|api_service_address)
            API_SERVICE_ADDRESS="$_value"
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
        storage-class-yaml|storage_class_yaml)
            STORAGE_CLASS_YAML="$_value"
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
        registry-yaml|registry_yaml)
            REGISTRY_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rek-operator-yaml|rek_operator_yaml)
            REK_OPERATOR_YAML="$_value"
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
        ceph-dashboard-user|ceph_dashboard_user)
            CEPH_DASHBOARD_USER="$_value"
            ;;
        ceph-dashboard-password|ceph_dashboard_password)
            CEPH_DASHBOARD_PASSWORD="$_value"
            ;;
        registry-address-override|registry_address_override)
            REGISTRY_ADDRESS_OVERRIDE="$_value"
            ;;
        app-registry-advertise-host|app_registry_advertise_host)
            APP_REGISTRY_ADVERTISE_HOST="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

render_replicated_deployment() {
    # On non-ha installs the daemon cannot change nodes because the join script uses the host IP
    # for the Kubernetes API server IP
    AFFINITY=
    if [ "$BIND_DAEMON_NODE" = "1" ]; then
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
        - name: CEPH_DASHBOARD_USER
          value: "$CEPH_DASHBOARD_USER"
        - name: CEPH_DASHBOARD_PASSWORD
          value: "$CEPH_DASHBOARD_PASSWORD"
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
$AFFINITY
      containers:
      - name: replicated
        image: "${REGISTRY_ADDRESS_OVERRIDE:-$REPLICATED_DOCKER_HOST}/replicated/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        env:
        - name: SCHEDULER_ENGINE
          value: kubernetes
        - name: RELEASE_CHANNEL
          value: "{{ channel_name }}"{% if release_sequence %}
        - name: RELEASE_SEQUENCE
          value: "$RELEASE_SEQUENCE"
{%- endif %}
        - name: COMPONENT_IMAGES_REGISTRY_ADDRESS_OVERRIDE
          value: "$REGISTRY_ADDRESS_OVERRIDE"{% if customer_base_url_override %}
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
              fieldPath: status.podIP
        - name: K8S_MASTER_ADDRESS
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: K8S_HOST_IP
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: K8S_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
EOF
    if [ -n "$APP_REGISTRY_ADVERTISE_HOST" ]; then
        cat <<EOF
        - name: REGISTRY_ADVERTISE_ADDRESS
          value: "$APP_REGISTRY_ADVERTISE_HOST:9874"
EOF
    fi
    if [ -n "$API_SERVICE_ADDRESS" ]; then
        cat <<EOF
        - name: K8S_SERVICE_ADDRESS
          value: "$API_SERVICE_ADDRESS"
EOF
    fi
    if [ "$HA_CLUSTER" = "1" ]; then
        cat <<EOF
        - name: HA_CLUSTER
          value: "true"
EOF
    fi
    cat <<EOF
        - name: K8S_STORAGECLASS
          value: "$STORAGE_CLASS"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: AIRGAP
          value: "$AIRGAP"
$PROXY_ENVS
        ports:
        - containerPort: 9874
        - containerPort: 9876
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
        image: "${REGISTRY_ADDRESS_OVERRIDE:-$REPLICATED_DOCKER_HOST}/replicated/replicated-ui:{{ replicated_ui_tag }}{{ environment_tag_suffix }}"
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

render_premkit_statsd_pvcs() {
    cat <<EOF
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

render_replicated_service() {
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

render_replicated_registry_service() {
    cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated-registry
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
EOF
}

render_replicated_api_service() {
    # TODO: we may want to change this to a clusterip service if we add any more routes other than
    # the pki bundle route which is unnecessary on installs other than HA.
    cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: replicated-api
  labels:
    app: replicated
    tier: master
spec:
  type: NodePort
  selector:
    app: replicated
    tier: master
  ports:
  - name: replicated-api
    port: 9876
    nodePort: 9876
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

render_cluster_role_binding() {
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
EOF
}

render_rook_storage_class() {
    cat <<EOF
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: "$STORAGE_CLASS"
   annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ceph.rook.io/block
parameters:
  pool: replicapool
  clusterNamespace: rook-ceph
EOF
}

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
                port:
                  type: integer
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
                preferredCount:
                  maximum: 9
                  minimum: 0
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
  name: cephnfses.ceph.rook.io
spec:
  group: ceph.rook.io
  names:
    kind: CephNFS
    listKind: CephNFSList
    plural: cephnfses
    singular: cephnfs
    shortNames:
    - nfs
  scope: Namespaced
  version: v1
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
  - apps
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
  - apps
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
  - endpoints
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
      serviceAccountName: rook-ceph-system
      containers:
      - name: rook-ceph-operator
        image: rook/ceph:master
        args: ["ceph", "operator"]
        volumeMounts:
        - mountPath: /var/lib/rook
          name: rook-config
        - mountPath: /etc/ceph
          name: default-config-dir
        env:
        # Allow rook to create multiple file systems. Note: This is considered
        # an experimental feature in Ceph as described at
        # http://docs.ceph.com/docs/master/cephfs/experimental-features/#multiple-filesystems-within-a-ceph-cluster
        # which might cause mons to crash as seen in https://github.com/rook/rook/issues/1027
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
          value: "600s"
        # The duration between discovering devices in the rook-discover daemonset.
        - name: ROOK_DISCOVER_DEVICES_INTERVAL
          value: "60m"
        # Whether to start pods as privileged that mount a host path, which includes the Ceph mon and osd pods.
        # This is necessary to workaround the anyuid issues when running on OpenShift.
        # For more details see https://github.com/rook/rook/issues/1314#issuecomment-355799641
        - name: ROOK_HOSTPATH_REQUIRES_PRIVILEGED
          value: "false"
        # In some situations SELinux relabelling breaks (times out) on large filesystems, and doesn't work with cephfs ReadWriteMany volumes (last relabel wins).
        # Disable it here if you have similar issues.
        # For more details see https://github.com/rook/rook/issues/2417
        - name: ROOK_ENABLE_SELINUX_RELABELING
          value: "true"
        # In large volumes it will take some time to chown all the files. Disable it here if you have performance issues.
        # For more details see https://github.com/rook/rook/issues/2254
        - name: ROOK_ENABLE_FSGROUP
          value: "true"
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
kind: ClusterRole
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
  kind: ClusterRole
  name: rook-ceph-mgr-system
subjects:
- kind: ServiceAccount
  name: rook-ceph-mgr
  namespace: rook-ceph
---
# Allow the ceph mgr to access cluster-wide resources necessary for the mgr modules
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-mgr-cluster
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
    image: ceph/ceph:v14.2
    # Whether to allow unsupported versions of Ceph. Currently only luminous and mimic are supported.
    # After nautilus is released, Rook will be updated to support nautilus.
    # Do not set to true in production.
    allowUnsupported: false
  # The path on the host where configuration files will be persisted. Must be specified.
  # Important: if you reinstall the cluster, make sure you delete this directory from each host or else the mons will fail to start on the new cluster.
  # In Minikube, the '/data' directory is configured to persist across reboots. Use "/data/rook" in Minikube environment.
  dataDirHostPath: /var/lib/rook
  # set the amount of mons to be started
  mon:
    count: 1
    preferredCount: 3
    allowMultiplePerNode: false
  # enable the ceph dashboard for viewing cluster status
  dashboard:
    enabled: true
    # serve the dashboard under a subpath (useful when you are accessing the dashboard via a reverse proxy)
    urlPrefix: /ceph
    # serve the dashboard at the given port.
    port: 7000
    # serve the dashboard using SSL
    ssl: false
  network:
    # toggle to use hostNetwork
    hostNetwork: false
  rbdMirroring:
    # The number of daemons that will perform the rbd mirroring.
    # rbd mirroring must be configured with "rbd mirror" from the rook toolbox.
    workers: 0
  resources:
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
      # encryptedDevice: "false" # the default value for this option is "false"
    directories:
    # By default create a osd in the dataDirHostPath directory. This should be removed for
    # environments where nodes have disks available for Rook to use.
    - path: "$PV_BASE_PATH"
---
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  failureDomain: host
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
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
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
              image: weaveworks/weave-kube:2.5.1
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
              image: weaveworks/weave-npc:2.5.1
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
{% include 'kubernetes/yaml/contour.yaml' %}
EOF
}

render_rek_operator_yaml() {
    cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rek-operator
  labels:
    app: rek-operator
spec:
  selector:
    matchLabels:
      app: rek-operator
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: rek-operator
    spec:
      containers:
      - name: rek
        image: "${REGISTRY_ADDRESS_OVERRIDE:-$REPLICATED_DOCKER_HOST}/replicated/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        command:
        - /usr/bin/rek
        - operator
        env:
        - name: NODE_UNREACHABLE_TOLERATION_MINUTES
          value: "30"
        - name: PURGE_DEAD_NODES
          value: "true"
        - name: MAINTAIN_ROOK_STORAGE_NODES
          value: "true"
        - name: CEPH_BLOCK_POOL
          value: replicapool
        - name: CEPH_FILESYSTEM
          value: shared_fs
        - name: MIN_CEPH_POOL_REPLICATION
          value: 1
        - name: MAX_CEPH_POOL_REPLICATION
          value: 3
        - name: COMPONENT_IMAGES_REGISTRY_ADDRESS_OVERRIDE
          value: $REGISTRY_ADDRESS_OVERRIDE
        - name: NAMESPACE
          value: default
        - name: RECONCILE_INTERVAL_MINUTES
          value: "1"
EOF
}

render_registry_yaml() {
    haSharedSecret=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    cat <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: docker-registry-config
  labels:
    app: docker-registry
data:
  config.yml: |-
    health:
      storagedriver:
        enabled: true
        interval: 10s
        threshold: 3
    http:
      addr: :5000
      headers:
        X-Content-Type-Options:
        - nosniff
    log:
      fields:
        service: registry
    storage:
      cache:
        blobdescriptor: inmemory
    version: 0.1
---
apiVersion: v1
kind: Secret
metadata:
  name: docker-registry-secret
  labels:
    app: docker-registry
type: Opaque
stringData:
  haSharedSecret: $haSharedSecret
---
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: docker-registry
spec:
  selector:
    matchLabels:
      app: docker-registry
  serviceName: "registry"
  replicas: 1
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: docker-registry
        image: registry:2
        imagePullPolicy: IfNotPresent
        command:
        - /bin/registry
        - serve
        - /etc/docker/registry/config.yml
        ports:
        - containerPort: 5000
          protocol: TCP
        volumeMounts:
        - name: registry-data
          mountPath: /var/lib/registry/
        - name: docker-registry-config
          mountPath: /etc/docker/registry
        env:
        - name: REGISTRY_HTTP_SECRET
          valueFrom:
            secretKeyRef:
              key: haSharedSecret
              name: docker-registry-secret
        - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
          value: /var/lib/registry
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /
            port: 5000
            scheme: HTTP
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /
            port: 5000
            scheme: HTTP
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
      volumes:
      - name: registry-data
        persistentVolumeClaim:
          claimName: docker-registry
      - name: docker-registry-config
        configMap:
          name: docker-registry-config
  volumeClaimTemplates:
  - metadata:
      name: registry-data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 20Gi
      storageClassName: "$STORAGE_CLASS"
---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  labels:
    app: docker-registry
spec:
  type: ClusterIP
  ports:
  - port: 5000
    name: registry
    targetPort: 5000
    protocol: TCP
  selector:
    app: docker-registry
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

if [ "$STORAGE_CLASS_YAML" = "1" ]; then
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
fi

if [ "$REGISTRY_YAML" = "1" ]; then
    render_registry_yaml
fi

if [ "$REK_OPERATOR_YAML" = "1" ]; then
    render_rek_operator_yaml
fi

if [ "$REPLICATED_YAML" = "1" ]; then
    if [ "$REPLICATED_PVC" != "0" ]; then
        render_replicated_pvc
    fi
    render_premkit_statsd_pvcs
    render_cluster_role_binding
    render_replicated_deployment
    render_replicated_service
    if [ "$AIRGAP" = "1" ]; then
        render_replicated_registry_service
    fi

    if [ "$HA_CLUSTER" = "1" ]; then
        render_replicated_api_service
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
