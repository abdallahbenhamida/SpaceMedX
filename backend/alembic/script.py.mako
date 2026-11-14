# ${message}
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = ${repr(branch_labels)}
depends_on = ${repr(depends_on)}

from alembic import op
import sqlalchemy as sa
${imports.s if imports else ""}

def upgrade() -> None:
    ${upgrades}


def downgrade() -> None:
    ${downgrades}