from fastapi import APIRouter
from .routers import auth, invite, inputs, analyze, items, actions, issues, trace, projects, ws, labels
from .routers.dashboard import router as dashboard_router
from .routers.conversations import router as conversations_router
from .routers.search import router as search_router
from .routers.decisions import router as decisions_router
from .routers.users import router as users_router
from .routers.dictionary import router as dictionary_router
from .tenants import router as tenants_router
from app.api.v1.routers import sso

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(invite.router)
api_router.include_router(projects.router)
api_router.include_router(inputs.router)
api_router.include_router(analyze.router)
api_router.include_router(items.router)
api_router.include_router(actions.router)
api_router.include_router(issues.router)
api_router.include_router(trace.router)
api_router.include_router(dashboard_router)
api_router.include_router(conversations_router)
api_router.include_router(search_router)
api_router.include_router(decisions_router)
api_router.include_router(ws.router)
api_router.include_router(labels.router)
api_router.include_router(users_router)
api_router.include_router(dictionary_router)
api_router.include_router(tenants_router, tags=["tenants"])
api_router.include_router(sso.router)
