import json
import os
from typing import Any

import boto3
import pandas as pd
import requests
import streamlit as st
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

DEFAULT_QUERY = "SELECT * WHERE { ?s ?p ?o } LIMIT 25"


@st.cache_resource
def get_session() -> boto3.Session:
    return boto3.Session()


def signed_post(url: str, body: str, region: str, content_type: str, accept: str) -> requests.Response:
    session = get_session()
    creds = session.get_credentials()
    if creds is None:
        raise RuntimeError("No Amazon Web Services credentials available in the task role")

    frozen = creds.get_frozen_credentials()
    request = AWSRequest(
        method="POST",
        url=url,
        data=body,
        headers={"Content-Type": content_type, "Accept": accept},
    )
    SigV4Auth(frozen, "neptune-db", region).add_auth(request)

    headers = dict(request.headers.items())
    headers["Accept"] = accept
    return requests.post(url, headers=headers, data=body.encode("utf-8"), timeout=60)


def parse_bindings(payload: dict[str, Any]) -> pd.DataFrame:
    rows: list[dict[str, str]] = []
    bindings = payload.get("results", {}).get("bindings", [])
    for item in bindings:
        row: dict[str, str] = {}
        for key, value in item.items():
            row[key] = value.get("value", "")
        rows.append(row)
    return pd.DataFrame(rows)


def main() -> None:
    st.set_page_config(page_title="Chemistry Graph Interface", layout="wide")
    st.title("Chemistry Knowledge Graph Interface")

    region = os.getenv("AWS_REGION", "us-west-2")
    endpoint = os.getenv("NEPTUNE_ENDPOINT", "")

    st.caption(f"Region: {region}")
    st.caption(f"Neptune endpoint: {endpoint or 'not configured'}")

    if not endpoint:
        st.error("Set NEPTUNE_ENDPOINT in the container environment")
        st.stop()

    if "query" not in st.session_state:
        st.session_state["query"] = DEFAULT_QUERY

    st.text_area("SPARQL query", key="query", height=220)

    col1, col2 = st.columns(2)
    run = col1.button("Run query", type="primary")
    sample = col2.button("Load sample")

    if sample:
        st.session_state["query"] = DEFAULT_QUERY

    if run:
        try:
            url = f"https://{endpoint}:8182/sparql"
            response = signed_post(
                url=url,
                body=st.session_state["query"],
                region=region,
                content_type="application/sparql-query",
                accept="application/sparql-results+json",
            )
            st.write(f"HTTP status: {response.status_code}")

            if response.status_code != 200:
                st.error(response.text[:3000])
                st.stop()

            data = response.json()
            frame = parse_bindings(data)
            st.dataframe(frame, use_container_width=True)
            with st.expander("Raw JSON"):
                st.code(json.dumps(data, indent=2)[:6000], language="json")
        except Exception as exc:  # pragma: no cover - user-facing diagnostics
            st.exception(exc)


if __name__ == "__main__":
    main()
