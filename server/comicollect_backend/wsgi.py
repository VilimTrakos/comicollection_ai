"""Small WSGI adapter for :class:`ProductionApi`.

The domain API knows nothing about web servers. Request parsing and response
formatting live in adjacent focused modules so this boundary stays auditable.
"""

from __future__ import annotations

from typing import Callable, Iterable, Mapping

from .production_api import ProductionApi
from .wsgi_request import (
    RequestBodyError,
    client_key,
    header,
    normalized_proxy_addresses,
    read_body,
    request_headers,
)
from .wsgi_response import error_response, status_line, with_content_length


class WsgiApplication:
    """Expose a ``ProductionApi`` through the WSGI 1.0 contract."""

    def __init__(
        self,
        api: ProductionApi,
        *,
        trusted_proxy_addresses: Iterable[str] = (),
    ):
        self.api = api
        self.trusted_proxy_addresses = normalized_proxy_addresses(
            trusted_proxy_addresses
        )

    def __call__(
        self,
        environ: Mapping[str, object],
        start_response: Callable,
    ) -> list[bytes]:
        path = str(environ.get("PATH_INFO") or "/")
        query = str(environ.get("QUERY_STRING") or "")
        target = f"{path}?{query}" if query else path
        headers = request_headers(environ)
        try:
            body = read_body(environ, path)
            status, response_headers, payload = self.api.handle(
                str(environ.get("REQUEST_METHOD") or "GET"),
                target,
                headers,
                body,
                client_key=client_key(
                    environ,
                    headers,
                    self.trusted_proxy_addresses,
                ),
            )
        except RequestBodyError as error:
            status, response_headers, payload = error_response(
                error.status,
                error.code,
                error.message,
                header(headers, "X-Request-ID"),
            )

        final_headers = with_content_length(response_headers, len(payload))
        start_response(status_line(status), list(final_headers.items()))
        return [payload]
