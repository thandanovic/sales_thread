class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :shop

  # Enum for roles (simplified: manager and agent only)
  # manager = full shop control (imports, templates, products)
  # agent = read-only + OLX sync only
  enum :role, { manager: 'manager', agent: 'agent' }, default: :agent

  # Validations
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :shop_id, message: "is already a member of this shop" }

  # Scopes
  scope :managers, -> { where(role: 'manager') }
  scope :agents, -> { where(role: 'agent') }

  # Permission checks
  def can_manage_products?
    manager?
  end

  def can_run_imports?
    manager?
  end

  def can_manage_templates?
    manager?
  end

  def can_sync_olx?
    true # All roles can sync with OLX
  end

  def can_manage_shop_settings?
    manager?
  end

  def can_manage_members?
    manager?
  end
end
