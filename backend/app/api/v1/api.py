from fastapi import APIRouter
from .routers import auth, inputs, analyze, items, actions, issues, trace, projects

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(projects.router)
api_router.include_router(inputs.router)
api_router.include_router(analyze.router)
api_router.include_router(items.router)
api_router.include_router(actions.router)
api_router.include_router(issues.router)
api_router.include_router(trace.router)
