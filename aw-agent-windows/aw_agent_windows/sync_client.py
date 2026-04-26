import json
from typing import Any, Dict, List

import requests


class FleetSyncClient:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        protocol: str = "http",
        timeout: float = 30.0,
    ) -> None:
        self.base_url = f"{protocol}://{host}:{port}/api/0"
        self.timeout = timeout

    def _post(self, endpoint: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        response = requests.post(
            f"{self.base_url}/{endpoint}",
            data=json.dumps(payload),
            headers={"Content-Type": "application/json", "charset": "utf-8"},
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()

    def handshake(self, agent: Dict[str, str], streams: List[Dict[str, Any]]) -> Dict[str, Any]:
        return self._post(
            "fleet/sync/handshake",
            {
                "protocol_version": 1,
                "agent": agent,
                "streams": [
                    {
                        "stream_id": stream["stream_id"],
                        "bucket_id": stream["bucket_id"],
                        "bucket_type": stream["bucket_type"],
                        "bucket_metadata": stream["bucket_metadata"],
                        "next_seq": stream["next_seq"],
                    }
                    for stream in streams
                ],
            },
        )

    def upload_batch(
        self,
        *,
        agent_id: str,
        stream_id: str,
        from_seq: int,
        to_seq: int,
        ops: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        return self._post(
            "fleet/sync/batch",
            {
                "protocol_version": 1,
                "agent_id": agent_id,
                "stream_id": stream_id,
                "from_seq": from_seq,
                "to_seq": to_seq,
                "ops": ops,
            },
        )
