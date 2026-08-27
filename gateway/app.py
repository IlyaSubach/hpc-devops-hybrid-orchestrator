"""Slurm -> Prometheus metrics gateway.

A minimal push-style bridge: Slurm jobs PUT metric updates as JSON, and the
service re-exposes the latest values on /metrics in the Prometheus text
exposition format.
"""

import re
import sys
import threading

from flask import Flask, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Gauge,
    generate_latest,
)

METRIC_NAME_RE = re.compile(r"^[a-zA-Z_:][a-zA-Z0-9_:]*$")
LABEL_NAME_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")

app = Flask(__name__)
registry = CollectorRegistry()

# metric name -> (Gauge, tuple of sorted label names)
_gauges: dict[str, tuple[Gauge, tuple[str, ...]]] = {}
_lock = threading.Lock()


def _get_gauge(name: str, label_names: tuple[str, ...]) -> Gauge:
    """Return the gauge for *name*, creating it on first use.

    Prometheus requires a metric to keep a stable label set, so an update
    with different label names than the first one is rejected.
    """
    with _lock:
        if name not in _gauges:
            gauge = Gauge(
                name,
                "Metric pushed through the Slurm metrics gateway",
                labelnames=label_names,
                registry=registry,
            )
            _gauges[name] = (gauge, label_names)

        gauge, known_labels = _gauges[name]
        if known_labels != label_names:
            raise ValueError(
                f"metric {name!r} was registered with labels {list(known_labels)}, "
                f"got {list(label_names)}"
            )
        return gauge


@app.route("/update-metric", methods=["PUT"])
def update_metric():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="body must be a JSON object"), 400

    name = payload.get("name")
    value = payload.get("value")
    labels = payload.get("labels") or {}

    if not isinstance(name, str) or not METRIC_NAME_RE.match(name):
        return jsonify(error="'name' must be a valid Prometheus metric name"), 400
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return jsonify(error="'value' must be a number"), 400
    if not isinstance(labels, dict) or not all(
        isinstance(k, str) and LABEL_NAME_RE.match(k) and isinstance(v, str)
        for k, v in labels.items()
    ):
        return jsonify(error="'labels' must map valid label names to strings"), 400

    try:
        gauge = _get_gauge(name, tuple(sorted(labels)))
    except ValueError as exc:
        return jsonify(error=str(exc)), 400

    if labels:
        gauge.labels(**labels).set(value)
    else:
        gauge.set(value)

    return jsonify(status="ok", metric=name, value=value, labels=labels)


@app.route("/metrics")
def metrics():
    return generate_latest(registry), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/healthz")
def healthz():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
