"""align user_devices with the mobile API contract

Revision ID: k7l8m9n0o1p2
Revises: j6k7l8m9n0o1
Create Date: 2026-11-05 00:00:00.000000

CoreStream-Mobile-Especificacion-API §4.1/§9.1: token FCM de hasta 4096
caracteres, device_name y app_version opcionales, y plataforma ANDROID|IOS.
"""
from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = 'k7l8m9n0o1p2'
down_revision: Union[str, None] = 'j6k7l8m9n0o1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column('user_devices', 'token', type_=sa.String(length=4096),
                    existing_type=sa.String(length=512), existing_nullable=False)
    op.add_column('user_devices', sa.Column('device_name', sa.String(length=120), nullable=True))
    op.add_column('user_devices', sa.Column('app_version', sa.String(length=20), nullable=True))
    op.execute("UPDATE user_devices SET platform = UPPER(platform)")


def downgrade() -> None:
    op.execute("UPDATE user_devices SET platform = LOWER(platform)")
    op.drop_column('user_devices', 'app_version')
    op.drop_column('user_devices', 'device_name')
    op.alter_column('user_devices', 'token', type_=sa.String(length=512),
                    existing_type=sa.String(length=4096), existing_nullable=False)
