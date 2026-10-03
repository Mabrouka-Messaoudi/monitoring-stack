# monitoring-stack – Stack d'observabilité de NexShop (Helm)

Ce dépôt installe la couche d'observabilité de mon PFE : *plateforme Kubernetes hybride avec supervision
par IA/ML (AIOps)*. Il fournit les trois signaux dont dépendent à la fois la supervision classique et les
modèles de ML : les **métriques** (Prometheus), les **logs** (Loki) et les **traces** (Tempo), réunis dans
Grafana.

Il s'intègre aux autres dépôts du projet :

| Dépôt | Rôle |
|-------|------|
| [`cluster-k8s`](https://github.com/Mabrouka-Messaoudi/cluster-k8s) | Cluster Kubernetes hybride (Vagrant + Ansible) |
| **`monitoring-stack`** (ce dépôt) | Prometheus, Grafana, Alertmanager, Loki, Promtail, Tempo |
| [`microservices-java-k8s-monitoring`](https://github.com/Mabrouka-Messaoudi/microservices-java-k8s-monitoring) | Microservices NexShop instrumentés |

## Composants

| Composant | Chart Helm | Rôle |
|-----------|-----------|------|
| Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics | `prometheus-community/kube-prometheus-stack` | Métriques du cluster et des microservices, alertes, tableaux de bord |
| Loki (mode SingleBinary) | `grafana/loki` | Stockage et requêtage des logs (LogQL) |
| Promtail | `grafana/promtail` | Collecte des logs des conteneurs sur tous les nœuds |
| Tempo | `grafana/tempo` | Stockage des traces distribuées (réception Zipkin, OTLP, Jaeger) |

Grafana est livré avec les sources de données Loki et Tempo préconfigurées et trois tableaux de bord
communautaires (cluster, node-exporter, pods).

Les métriques des microservices sont collectées par le ServiceMonitor `nexshop-java-services`
(`manifests/`). Celui-ci interroge `/actuator/prometheus` toutes les 15 secondes, au même rythme que le
collecteur de données AIOps.

## Placement des pods

Tous les composants de stockage et de requêtage tournent sur un **nœud dédié au monitoring**
(label `monitoring=true`, taint `dedicated=monitoring:NoSchedule`). Les nœuds applicatifs n'ont que 1 Go
de RAM, cette séparation évite donc que la supervision entre en concurrence avec les microservices qu'elle
observe. node-exporter et Promtail, qui doivent tourner sur chaque nœud, tolèrent tous les taints.
`install.sh` pose le label et le taint lui-même.

## Prérequis

- Un cluster fonctionnel, créé avec [`cluster-k8s`](https://github.com/Mabrouka-Messaoudi/cluster-k8s), et `kubectl` configuré
- Helm 3
- La StorageClass `local-path` ([local-path-provisioner](https://github.com/rancher/local-path-provisioner)) pour les volumes persistants

## Installation

Les versions des charts sont figées dans `versions.env`, pour que deux installations donnent le même
résultat. Ce fichier est généré à partir du cluster de référence par `pin-versions.sh`.

```bash
bash pin-versions.sh                       # une seule fois, sur le cluster de référence

export MONITORING_NODE=k8s2-worker1
export GRAFANA_ADMIN_PASSWORD='<mot de passe>'
bash install.sh
```

Le mot de passe Grafana n'est stocké nulle part dans le dépôt. `install.sh` le place dans le Secret
`grafana-admin`, que lit le chart.

Ordre recommandé : `cluster-k8s`, puis `monitoring-stack`, puis `microservices-java-k8s-monitoring`.

## Accès

| Service | URL | Utilisé par |
|---------|-----|-------------|
| Grafana | `http://<IP du nœud de monitoring>:32000` | Visualisation |
| Prometheus | `http://<IP d'un nœud>:30090` | Collecteur AIOps (PromQL) |
| Loki | `http://<IP d'un nœud>:30003` | Collecteur AIOps (LogQL) |
| Tempo | `http://<IP d'un nœud>:30622` | Collecteur AIOps (TraceQL) |

Depuis le cluster, les microservices envoient leurs logs à `http://loki.monitoring:3100` et leurs traces à
`http://tempo.monitoring:9411` (Zipkin).

## Choix techniques et limites

- **Loki en SingleBinary avec stockage sur disque.** C'est suffisant pour un banc d'essai mono-nœud. En
  production, il faudrait passer en mode distribué avec un stockage objet.
- **Control plane non supervisé.** Avec kubeadm, etcd, kube-scheduler, kube-controller-manager et
  kube-proxy écoutent sur `127.0.0.1`. Leurs cibles seraient toujours en échec et déclencheraient des
  alertes permanentes. Leur supervision est donc désactivée.
- **Logs collectés deux fois.** Les microservices envoient leurs logs directement à Loki (appender
  `loki4j`), et Promtail collecte aussi les logs de tous les conteneurs. Les deux flux se distinguent par
  leurs labels.
- **Promtail** est en fin de vie chez Grafana, au profit de Grafana Alloy. Une migration vers Alloy serait
  la suite naturelle.
- **Pas de haute disponibilité** : une seule réplique de Prometheus, Loki et Tempo.

## Désinstallation

```bash
bash uninstall.sh                  # conserve les données (PVC)
DELETE_DATA=true bash uninstall.sh # supprime aussi les données
```
