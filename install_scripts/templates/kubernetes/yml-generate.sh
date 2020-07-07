#!/bin/bash

set -e

LOG_LEVEL="{{ log_level }}"
RELEASE_SEQUENCE="{{ release_sequence }}"
RELEASE_PATCH_SEQUENCE="{{ release_patch_sequence }}"
UI_BIND_PORT="{{ ui_bind_port }}"
KUBERNETES_NAMESPACE="{{ kubernetes_namespace }}"
PV_BASE_PATH="{{ pv_base_path }}"
STORAGE_PROVISIONER="{{ storage_provisioner }}"
STORAGE_CLASS="{{ storage_class }}"
SERVICE_TYPE="{{ service_type }}"
PROXY_ADDRESS="{{ proxy_address }}"
NO_PROXY_ADDRESSES="{{ no_proxy_addresses }}"
# replicated components registry
REGISTRY_ADDRESS_OVERRIDE="{{ registry_address_override }}"
APP_REGISTRY_ADVERTISE_HOST="{{ app_registry_advertise_host }}"
IP_ALLOC_RANGE="10.32.0.0/12" # default for weave
REGISTRY_CLUSTER_IP=
REPLICATED_REGISTRY_CLUSTER_IP=
CEPH_DASHBOARD_URL=
CEPH_DASHBOARD_USER=
CEPH_DASHBOARD_PASSWORD=
OBJECT_STORE_ACCESS_KEY=
OBJECT_STORE_SECRET_KEY=
OBJECT_STORE_CLUSTER_IP=
# booleans
AIRGAP="{{ airgap }}"
ENCRYPT_NETWORK="{{ encrypt_network }}"
WEAVE_SECRET=1
REPLICATED_YAML=1
REPLICATED_PVC=1
ROOK_106_SYSTEM_YAML=0
ROOK_103_SYSTEM_YAML=0
ROOK_08_SYSTEM_YAML=0
ROOK_106_CLUSTER_YAML=0
ROOK_103_CLUSTER_YAML=0
ROOK_08_CLUSTER_YAML=0
ROOK_103_OBJECT_STORE_YAML=0
ROOK_106_OBJECT_STORE_YAML=0
ROOK_OBJECT_STORE_USER_YAML=0
STORAGE_CLASS_YAML=0
HOSTPATH_PROVISIONER_YAML=0
WEAVE_YAML=0
CONTOUR_YAML=0
DEPLOYMENT_YAML=0
REGISTRY_YAML=0
REK_OPERATOR_YAML=0
REPLICATED_REGISTRY_YAML=0
CLUSTER_ROLE_BINDING_YAML=0
NODELOCALDNS_YAML=0
BIND_DAEMON_TO_MASTERS=0
BIND_DAEMON_HOSTNAME=
API_SERVICE_ADDRESS="{{ api_service_address }}"
HA_CLUSTER="{{ ha_cluster }}"
PURGE_DEAD_NODES="{{ purge_dead_nodes }}"
CLEAR_DEAD_NODES="{{ clear_dead_nodes }}"
NODE_UNREACHABLE_TOLERATION=5m
MAINTAIN_ROOK_STORAGE_NODES="{{ maintain_rook_storage_nodes }}"
USE_ROOK_NODES_LABEL="{{ '1' if use_rook_nodes_label else '0' }}"
ROOK_STORAGE_NODES_LABEL="node-role.kubernetes.io/rook=true"
REPLICATED_REGISTRY_PREFIX=
REPLICATED_VERSION="{{ replicated_version }}"

{% include 'common/common.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/kubernetes.sh' %}

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            ;;
        bind-daemon-to-masters|bind_daemon_to_masters)
            BIND_DAEMON_TO_MASTERS=1
            ;;
        bind-daemon-hostname|bind_daemon_hostname)
            BIND_DAEMON_HOSTNAME="$_value"
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        release-patch-sequence|release_patch_sequence)
            RELEASE_PATCH_SEQUENCE="$_value"
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
        purge-dead-nodes|purge_dead_nodes)
            PURGE_DEAD_NODES=1
            ;;
        clear-dead-nodes|clear_dead_nodes)
            CLEAR_DEAD_NODES=1
            ;;
        maintain-rook-storage-nodes|maintain_rook_storage_nodes)
            MAINTAIN_ROOK_STORAGE_NODES=1
            ;;
        use-rook-nodes-label|use_rook_nodes_label)
            USE_ROOK_NODES_LABEL=1
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
        rook-106-system-yaml|rook_106_system_yaml)
            ROOK_106_SYSTEM_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-103-system-yaml|rook_103_system_yaml)
            ROOK_103_SYSTEM_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-08-system-yaml|rook_08_system_yaml)
            ROOK_08_SYSTEM_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-106-cluster-yaml|rook_106_cluster_yaml)
            ROOK_106_CLUSTER_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-103-cluster-yaml|rook_103_cluster_yaml)
            ROOK_103_CLUSTER_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-08-cluster-yaml|rook_08_cluster_yaml)
            ROOK_08_CLUSTER_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-103-object-store-yaml|rook_103_object_store_yaml)
            ROOK_103_OBJECT_STORE_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-106-object-store-yaml|rook_106_object_store_yaml)
            ROOK_106_OBJECT_STORE_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        rook-object-store-user-yaml|rook_object_store_user_yaml)
            ROOK_OBJECT_STORE_USER_YAML="$_value"
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
        replicated-registry-yaml|replicated_registry_yaml)
            REPLICATED_REGISTRY_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        registry-cluster-ip|registry_cluster_ip)
            REGISTRY_CLUSTER_IP="$_value"
            ;;
        replicated-registry-cluster-ip|replicated_registry_cluster_ip)
            REPLICATED_REGISTRY_CLUSTER_IP="$_value"
            ;;
        cluster-role-binding-yaml|cluster_role_binding_yaml)
            CLUSTER_ROLE_BINDING_YAML="$_value"
            REPLICATED_YAML=0
            ;;
        nodelocaldns-yaml|nodelocaldns_yaml)
            NODELOCALDNS_YAML="$_value"
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
        object-store-access-key|object_store_access_key)
            OBJECT_STORE_ACCESS_KEY="$_value"
            ;;
        object-store-secret-key|object_store_secret_key)
            OBJECT_STORE_SECRET_KEY="$_value"
            ;;
        object-store-cluster-ip|object_store_cluster_ip)
            OBJECT_STORE_CLUSTER_IP="$_value"
            ;;
        replicated-registry-prefix|replicated_registry_prefix)
            REPLICATED_REGISTRY_PREFIX="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

render_replicated_deployment() {
    NODE_SELECTOR=
    if [ -n "$BIND_DAEMON_HOSTNAME" ]; then
        NODE_SELECTOR=$(cat <<-EOF
      nodeSelector:
        kubernetes.io/hostname: "$BIND_DAEMON_HOSTNAME"
EOF
        )
    elif [ "$BIND_DAEMON_TO_MASTERS" = "1" ]; then
        NODE_SELECTOR=$(cat <<-EOF
      nodeSelector:
        node-role.kubernetes.io/master: ""
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
    CEPH_DASHBOARD_CREDS_ENV=
    if [ -n "$CEPH_DASHBOARD_USER" ] && [ -n "$CEPH_DASHBOARD_PASSWORD" ]; then
        CEPH_DASHBOARD_CREDS_ENV=$(cat <<-EOF
        - name: CEPH_DASHBOARD_USER
          value: "$CEPH_DASHBOARD_USER"
        - name: CEPH_DASHBOARD_PASSWORD
          value: "$CEPH_DASHBOARD_PASSWORD"
EOF
        )
    fi

    DOCKER_REGISTRY_PREFIX="$REPLICATED_REGISTRY_PREFIX"
    if [ -n "$REGISTRY_ADDRESS_OVERRIDE" ]; then
      DOCKER_REGISTRY_PREFIX="$REGISTRY_ADDRESS_OVERRIDE/replicated"
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
$NODE_SELECTOR
      containers:
      - name: replicated
        image: "${DOCKER_REGISTRY_PREFIX}/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        env:
        - name: SCHEDULER_ENGINE
          value: kubernetes
        - name: RELEASE_CHANNEL
          value: "{{ channel_name }}"
        - name: RELEASE_SEQUENCE
          value: "$RELEASE_SEQUENCE"
        - name: RELEASE_PATCH_SEQUENCE
          value: "$RELEASE_PATCH_SEQUENCE"
        - name: COMPONENT_IMAGES_REGISTRY_ADDRESS_OVERRIDE
          value: "$REGISTRY_ADDRESS_OVERRIDE"
        - name: REPLICATED_TMP_PATH
          value: /var/lib/replicated-tmp
        - name: SUPPORT_BUNDLES_PATH
          value: /var/lib/replicated-support-bundles
        - name: SUPPORT_BUNDLES_HOST_PATH
          value: /var/lib/replicated/support-bundles{% if customer_base_url_override %}
        - name: MARKET_BASE_URL
          value: "{{customer_base_url_override}}"
{%- endif %}{% if replicated_env == "staging" %}
        - name: MARKET_BASE_URL
          value: {{ customer_base_url_override|default('https://api.staging.replicated.com/market', true) }}
        - name: DATA_BASE_URL
          value: https://data.staging.replicated.com/market
        - name: VENDOR_REGISTRY
          value: registry.staging.replicated.com
        - name: REPLICATED_IMAGE_TAG_SUFFIX
          value: .staging
{%- endif %}{% if replicated_install_url != "https://get.replicated.com" %}
        - name: INSTALLER_URL
          value: {{ replicated_install_url }}
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
        - name: MAINTAIN_ROOK_STORAGE_NODES
          value: "$MAINTAIN_ROOK_STORAGE_NODES"
$PROXY_ENVS
        ports:
        - containerPort: 9874
        - containerPort: 9876
        - containerPort: 9877
        - containerPort: 9878
        volumeMounts:
        - name: replicated-persistent
          mountPath: /var/lib/replicated
        - name: replicated-tmp
          mountPath: /var/lib/replicated-tmp
        - name: replicated-support-bundles
          mountPath: /var/lib/replicated-support-bundles
        - name: replicated-socket
          mountPath: /var/run/replicated
        - name: docker-socket
          mountPath: /host/var/run/docker.sock
        - name: replicated-conf
          mountPath: /host/etc/replicated.conf
        - name: proc
          mountPath: /host/proc
          readOnly: true
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
      - name: replicated-ui
        image: "${DOCKER_REGISTRY_PREFIX}/replicated-ui:{{ replicated_ui_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        env:
        - name: RELEASE_CHANNEL
          value: "{{ channel_name }}"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
$CEPH_DASHBOARD_ENV
$CEPH_DASHBOARD_CREDS_ENV
        ports:
        - containerPort: 8800
        volumeMounts:
        - name: replicated-socket
          mountPath: /var/run/replicated
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
        operator: Exists
      volumes:
      - name: replicated-persistent
        persistentVolumeClaim:
          claimName: replicated-pv-claim
      - name: replicated-tmp
        hostPath:
          path: /var/lib/replicated/tmp
          type: DirectoryOrCreate
      - name: replicated-support-bundles
        hostPath:
          path: /var/lib/replicated/support-bundles
          type: DirectoryOrCreate
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
  - name: replicated-api
    port: 9876
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
  type: ClusterIP
EOF
    if [ -n "$REPLICATED_REGISTRY_CLUSTER_IP" ]; then
      cat <<EOF
  clusterIP: ${REPLICATED_REGISTRY_CLUSTER_IP}
EOF
    fi
    cat <<EOF
  selector:
    app: replicated
    tier: master
  ports:
  - name: replicated-registry
    port: 9874
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

render_nodelocaldns_yaml() {
  cat <<EOF
{% include 'kubernetes/yaml/nodelocaldns.yml' %}
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

render_rook106_system_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-6-system.yml' %}
EOF
}

render_rook103_system_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-3-system.yml' %}
EOF
}

render_rook08_system_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-0-8-system.yml' %}
EOF
}

render_rook103_cluster_yaml() {
    PV_BASE_PATH="${PV_BASE_PATH:-"/opt/replicated/rook"}"

    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-3-cluster.yml' %}
EOF
}

render_rook106_cluster_yaml() {
    PV_BASE_PATH="${PV_BASE_PATH:-"/opt/replicated/rook"}"

    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-6-cluster.yml' %}
EOF
}

render_rook08_cluster_yaml() {
    PV_BASE_PATH="${PV_BASE_PATH:-"/opt/replicated/rook"}"

    cat <<EOF
{% include 'kubernetes/yaml/rook-0-8-cluster.yml' %}
EOF
}

render_rook_103_object_store_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-3-object-store.yml' %}
EOF
}

render_rook_106_object_store_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-6-object-store.yml' %}
EOF
}

render_rook_object_store_user_yaml() {
    cat <<EOF
{% include 'kubernetes/yaml/rook-1-0-object-store-user.yml' %}
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
                - name: EXTRA_ARGS
                  value: "--log-level=info" # default log level is debug
                - name: EXEC_IMAGE
                  value: replicated/weaveexec:2.5.2-20200512
$weave_passwd_env
              image: replicated/weave-kube:2.5.2-20200505
              livenessProbe:
                httpGet:
                  host: 127.0.0.1
                  path: /status
                  port: 6784
                initialDelaySeconds: 30
              # https://www.weave.works/docs/net/latest/kubernetes/kube-addon/#cpu-and-memory-requirements
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
              args: ["--log-level", "info"] # default log level is debug
              env:
                - name: HOSTNAME
                  valueFrom:
                    fieldRef:
                      apiVersion: v1
                      fieldPath: spec.nodeName
                - name: EXEC_IMAGE
                  value: replicated/weaveexec:2.5.2-20200512
              image: replicated/weave-npc:2.5.2-20200507
              # https://www.weave.works/docs/net/latest/kubernetes/kube-addon/#cpu-and-memory-requirements
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
            - key: node.kubernetes.io/not-ready
              operator: Exists
            - key: node-role.kubernetes.io/master
              effect: NoSchedule
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
    DOCKER_REGISTRY_PREFIX="$REPLICATED_REGISTRY_PREFIX"
    if [ -n "$REGISTRY_ADDRESS_OVERRIDE" ]; then
      DOCKER_REGISTRY_PREFIX="$REGISTRY_ADDRESS_OVERRIDE/replicated"
    fi

    rook_label=
    if [ "$USE_ROOK_NODES_LABEL" = "1" ]; then
      rook_label="$ROOK_STORAGE_NODES_LABEL"
    fi

    if [ "$PURGE_DEAD_NODES" = "1" ]; then
        NODE_UNREACHABLE_TOLERATION=1h
    fi

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
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - docker-registry
              topologyKey: "kubernetes.io/hostname"
            weight: 100
      containers:
      - name: rek
        image: "${DOCKER_REGISTRY_PREFIX}/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}"
        imagePullPolicy: IfNotPresent
        command:
        - /usr/bin/rek
        - operator
        env:
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: NODE_UNREACHABLE_TOLERATION
          value: $NODE_UNREACHABLE_TOLERATION
        - name: PURGE_DEAD_NODES
          value: "$PURGE_DEAD_NODES"
        - name: CLEAR_DEAD_NODES
          value: "$CLEAR_DEAD_NODES"
        - name: MIN_READY_MASTER_NODES
          value: "2"
        - name: MIN_READY_WORKER_NODES
          value: "0"
        - name: MAINTAIN_ROOK_STORAGE_NODES
          value: "$MAINTAIN_ROOK_STORAGE_NODES"
        - name: ROOK_STORAGE_NODES_LABEL
          value: "$rook_label"
        - name: CEPH_BLOCK_POOL
          value: replicapool
        - name: CEPH_FILESYSTEM
          value: rook-shared-fs
        - name: CEPH_OBJECT_STORE
          value: replicated
        - name: MIN_CEPH_POOL_REPLICATION
          value: "1"
        - name: MAX_CEPH_POOL_REPLICATION
          value: "3"
        - name: COMPONENT_IMAGES_REGISTRY_ADDRESS_OVERRIDE
          value: $REGISTRY_ADDRESS_OVERRIDE
        - name: NAMESPACE
          value: default
        - name: RECONCILE_INTERVAL
          value: 1m
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
        operator: Exists
EOF
}

render_registry_object_store() {
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
    http:
      addr: :5000
      headers:
        X-Content-Type-Options:
        - nosniff
    log:
      fields:
        service: registry
    storage:
      redirect:
        disable: true
      cache:
        blobdescriptor: inmemory
      s3:
        region: "us-east-1"
        regionendpoint: http://$OBJECT_STORE_CLUSTER_IP
        bucket: docker-registry
    version: 0.1
---
apiVersion: v1
kind: Secret
metadata:
  name: docker-registry-s3-secret
  labels:
    app: docker-registry
type: Opaque
stringData:
  access-key-id: $OBJECT_STORE_ACCESS_KEY
  secret-access-key: $OBJECT_STORE_SECRET_KEY
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
spec:
  selector:
    matchLabels:
      app: docker-registry
  replicas: 2
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: docker-registry
        image: replicated/docker-registry:2.6.2-20200512
        imagePullPolicy: IfNotPresent
        command:
        - /bin/registry
        - serve
        - /etc/docker/registry/config.yml
        ports:
        - containerPort: 5000
          protocol: TCP
        volumeMounts:
        - name: docker-registry-config
          mountPath: /etc/docker/registry
        env:
        - name: REGISTRY_HTTP_SECRET
          valueFrom:
            secretKeyRef:
              key: haSharedSecret
              name: docker-registry-secret
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              key: access-key-id
              name: docker-registry-s3-secret
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              key: secret-access-key
              name: docker-registry-s3-secret
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
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
        operator: Exists
      volumes:
      - name: docker-registry-config
        configMap:
          name: docker-registry-config
EOF
}

render_registry_pvc() {
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
        image: replicated/docker-registry:2.6.2-20200512
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
          mountPath: /var/lib/registry
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
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
        operator: Exists
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
EOF
}

render_registry_yaml() {
    haSharedSecret=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    if [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        render_registry_object_store
    else
        render_registry_pvc
    fi

    cat <<EOF
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
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  labels:
    app: docker-registry
spec:
  type: ClusterIP
EOF
    if [ -n "$REGISTRY_CLUSTER_IP" ]; then
      cat <<EOF
  clusterIP: ${REGISTRY_CLUSTER_IP}
EOF
    fi
    cat <<EOF
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

if [ -z "$REPLICATED_REGISTRY_PREFIX" ]; then
    getReplicatedRegistryPrefix "$REPLICATED_VERSION"
fi

if [ "$WEAVE_YAML" = "1" ]; then
    render_weave_yaml
fi

if [ "$CONTOUR_YAML" = "1" ]; then
    render_contour_yaml
fi

if [ "$ROOK_106_CLUSTER_YAML" = "1" ]; then
    render_rook106_cluster_yaml
fi

if [ "$ROOK_103_CLUSTER_YAML" = "1" ]; then
    render_rook103_cluster_yaml
fi

if [ "$ROOK_08_CLUSTER_YAML" = "1" ]; then
    render_rook08_cluster_yaml
fi

if [ "$ROOK_103_OBJECT_STORE_YAML" = "1" ]; then
    render_rook_103_object_store_yaml
fi

if [ "$ROOK_106_OBJECT_STORE_YAML" = "1" ]; then
    render_rook_106_object_store_yaml
fi

if [ "$ROOK_OBJECT_STORE_USER_YAML" = "1" ]; then
    render_rook_object_store_user_yaml
fi

if [ "$ROOK_106_SYSTEM_YAML" = "1" ]; then
    render_rook106_system_yaml
fi

if [ "$ROOK_103_SYSTEM_YAML" = "1" ]; then
    render_rook103_system_yaml
fi

if [ "$ROOK_08_SYSTEM_YAML" = "1" ]; then
    render_rook08_system_yaml
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

if [ "$REPLICATED_REGISTRY_YAML" = "1" ]; then
    render_replicated_registry_service
fi

if [ "$CLUSTER_ROLE_BINDING_YAML" = "1" ]; then
  render_cluster_role_binding
fi

if [ "$NODELOCALDNS_YAML" = "1" ]; then
  render_nodelocaldns_yaml
fi

if [ "$REPLICATED_YAML" = "1" ]; then
    if [ "$REPLICATED_PVC" != "0" ]; then
        render_replicated_pvc
    fi
    render_premkit_statsd_pvcs
    render_cluster_role_binding
    render_replicated_deployment
    render_replicated_service

    if [ "$HA_CLUSTER" = "1" ]; then
        render_replicated_api_service
    fi

    if [ "$SERVICE_TYPE" = "NodePort" ]; then
        render_replicated_ui_node_port_service
    else
        render_replicated_ui_service
    fi
fi

# autoupgrades
if [ "$DEPLOYMENT_YAML" = "1" ]; then
    render_replicated_deployment
fi
