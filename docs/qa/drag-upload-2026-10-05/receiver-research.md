# Drag-upload diagnosis: sender and receiver evidence

## Confirmed DaBin defect

The isolated baseline reproduced failed delayed file reads in eight transfer lanes after capture organization moved the managed original. Outgoing writers and providers had retained its former URL. This establishes a DaBin file-lifetime defect independently of the reported error. A stable outgoing snapshot, retained through deferred file and image reads, addresses that demonstrated failure.

It does **not** establish which app received the user's drop, reproduce the user's `OD_PROTOCOL_PROXY_FAILED` error, or prove that the stale path caused that error.

## Public receiver source

Research used the public `nexu-io/open-design` revision `53231d40b778d88eba23f35547bf99485d3ae9fc`; this is not evidence of the user's installed receiver or version.

- Open Design explicitly creates JSON `OD_PROTOCOL_PROXY_FAILED` with HTTP **502** when its `od://` proxy fetch throws. The response carries the underlying message, optional error code, and target URL. [Proxy error construction and handler](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/packaged/src/protocol.ts#L395-L460).
- Its composer receives actual browser `dataTransfer.files`; the upload client posts those `File` objects as multipart `FormData` to `/api/projects/:id/upload`. It exposes a non-success JSON response's `error` field as an upload failure. This path does not send a separate sender-filesystem-path parameter. [Drop handling](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/web/src/components/ChatComposer.tsx#L2699-L2713), [upload client](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/web/src/providers/registry.ts#L3205-L3287).
- Ordinary upstream **400/404/5xx responses are forwarded unchanged**. The proxy token identifies a thrown fetch failure rather than one specific cause. Because the request body is streamed, a sender-file read failure could also fail the fetch; that possibility is an inference, not a reproduced receiver result. [Request streaming and response forwarding](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/packaged/src/protocol.ts#L182-L255).

The exact prefix `Attachment upload failed for` was absent from 1,838 public `src` JavaScript/TypeScript files and 196 additional production JavaScript/TypeScript files scanned at this revision, with no fetch errors. It may come from an older release or another receiver; its origin remains unverified.

## Conditional receiver recovery

If the receiving app is confirmed as Open Design, `ERR_CONNECTION_REFUSED` plus a localhost target supports a failed local sidecar. An original public issue reports recovery after a full app restart; it does not establish the user's cause. Preserve the prompt, restart the confirmed receiver, and retry one attachment. Current source retains failed files for explicit retry and avoids automatically replaying upload POSTs. [Original receiver report](https://github.com/nexu-io/open-design/issues/7010), [retained-file retry](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/web/src/components/ChatComposer.tsx#L2235-L2296), [non-idempotent retry policy](https://github.com/nexu-io/open-design/blob/53231d40b778d88eba23f35547bf99485d3ae9fc/apps/packaged/src/protocol.ts#L349-L390).

No receiving app was launched, no private logs or credentials were inspected, and no receiver error was reproduced during this research.
