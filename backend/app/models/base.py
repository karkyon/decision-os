from sqlalchemy.orm import DeclarativeBase
import uuid
from sqlalchemy import Column, String
from sqlalchemy.dialects.postgresql import UUID

class Base(DeclarativeBase):
    pass

def gen_uuid():
    return str(uuid.uuid4())
