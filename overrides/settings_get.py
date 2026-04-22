try:
    from helpers.api import ApiHandler, Request, Response
    from helpers import settings
except ImportError:  # compatibility with older base-image layout
    from python.helpers.api import ApiHandler, Request, Response
    from python.helpers import settings


class GetSettings(ApiHandler):
    async def process(self, input: dict, request: Request) -> dict | Response:
        backend = settings.get_settings()
        out = settings.convert_out(backend)

        token = out.get("settings", {}).get("mcp_server_token")
        if token:
            out["settings"]["mcp_server_token"] = settings.API_KEY_PLACEHOLDER

        return dict(out)

    @classmethod
    def get_methods(cls) -> list[str]:
        return ["GET", "POST"]
