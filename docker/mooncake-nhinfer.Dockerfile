FROM ubuntu:22.04@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip libibverbs1 librdmacm1 ibverbs-providers libnuma1 libcurl4 libgomp1 ca-certificates && rm -rf /var/lib/apt/lists/*
COPY vendor/*.whl /wheels/
COPY scripts/nhinfer/manifest.json /opt/mooncake-build/manifest.json
RUN python3 -c "import json,hashlib,pathlib; m=json.load(open('/opt/mooncake-build/manifest.json')); p=pathlib.Path('/wheels')/m['wheel']; assert hashlib.sha256(p.read_bytes()).hexdigest()==m['sha256']" && python3 -m pip install --no-deps --no-index /wheels/*.whl && rm -rf /wheels
RUN python3 -c "from mooncake.store import MooncakeDistributedStore; import importlib.metadata as m; assert m.version('mooncake-transfer-engine-non-cuda')=='0.3.7.post2'"
ENV PATH=/usr/local/lib/python3.10/dist-packages/mooncake:${PATH}
COPY scripts/nhinfer/runtime/ /opt/mooncake/bin/
COPY vendor/SOURCE /opt/mooncake-build/SOURCE
CMD ["/bin/bash"]
