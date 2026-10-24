#!/usr/bin/env python3
"""Grafica replicas / CPU / p95 desde la API de Prometheus (port-forward a localhost:9090).
Uso: plot_timeline.py <inicio ISO> <fin ISO> <salida.png> [titulo]"""
import sys, json, urllib.request, urllib.parse, datetime as dt
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt

PROM = 'http://localhost:9090/api/v1/query_range'
def q(query, a, b):
    u = PROM + '?' + urllib.parse.urlencode({'query': query, 'start': a, 'end': b, 'step': '15'})
    r = json.load(urllib.request.urlopen(u))['data']['result']
    return [(dt.datetime.utcfromtimestamp(float(t)), float(v)) for t, v in (r[0]['values'] if r else [])]

a, b, out = sys.argv[1:4]; title = sys.argv[4] if len(sys.argv) > 4 else 'Propuestas'
ns = 'namespace="propuestas"'
series = {
 'Replicas ready (API)': 'kube_deployment_status_replicas_ready{%s,deployment="propuestas-api"}' % ns,
 'Replicas deseadas (HPA)': 'kube_horizontalpodautoscaler_status_desired_replicas{%s,horizontalpodautoscaler="propuestas-api"}' % ns,
}
cpu = 'sum(rate(container_cpu_usage_seconds_total{%s,pod=~"propuestas-api-.*",container="api"}[1m]))/sum(kube_pod_container_resource_requests{%s,pod=~"propuestas-api-.*",container="api",resource="cpu"})*100' % (ns, ns)
p95 = 'sum(rate(http_server_requests_seconds_sum{%s}[1m]))/sum(rate(http_server_requests_seconds_count{%s}[1m]))*1000' % (ns, ns)  # latencia media (no hay buckets de histograma; p95 real: resumen k6)
fig, ax = plt.subplots(3, 1, figsize=(11, 8), sharex=True)
for n, qq in series.items():
    d = q(qq, a, b)
    if d: ax[0].step(*zip(*d), where='post', label=n)
ax[0].set_ylabel('Replicas'); ax[0].legend(); ax[0].grid(alpha=.3)
d = q(cpu, a, b)
if d: ax[1].plot(*zip(*d)); ax[1].axhline(60, color='r', ls='--', label='objetivo HPA 60 %'); ax[1].legend()
ax[1].set_ylabel('CPU % del request'); ax[1].grid(alpha=.3)
d = q(p95, a, b)
if d: ax[2].plot(*zip(*d))
else: ax[2].text(.5, .5, 'sin datos de latencia', transform=ax[2].transAxes, ha='center')
ax[2].set_ylabel('Latencia media HTTP (ms)'); ax[2].grid(alpha=.3)
fig.suptitle(title + ' (UTC)'); fig.autofmt_xdate(); fig.tight_layout(); fig.savefig(out, dpi=110)
print('ok', out)
