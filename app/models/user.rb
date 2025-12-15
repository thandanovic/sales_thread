class User < ApplicationRecord
  # Include default devise modules (registration disabled - admins create users)
  devise :database_authenticatable,
         :rememberable, :trackable, :validatable

  # Associations
  has_many :memberships, dependent: :destroy
  has_many :shops, through: :memberships
  has_many :impersonation_logs_as_admin, class_name: 'ImpersonationLog', foreign_key: :admin_user_id, dependent: :destroy
  has_many :impersonation_logs_as_target, class_name: 'ImpersonationLog', foreign_key: :impersonated_user_id, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # System admin check (uses admin boolean column)
  def system_admin?
    admin?
  end

  # Role checking methods for a specific shop
  def role_for_shop(shop)
    memberships.find_by(shop: shop)&.role
  end

  def manager_of?(shop)
    system_admin? || memberships.exists?(shop: shop, role: 'manager')
  end

  def agent_of?(shop)
    system_admin? || memberships.exists?(shop: shop, role: %w[manager agent])
  end

  def member_of?(shop)
    system_admin? || memberships.exists?(shop: shop)
  end

  # All accessible shops (for system admins, this is ALL shops)
  def accessible_shops
    if system_admin?
      Shop.all
    else
      shops
    end
  end

  # Check if user has access to only one shop (for auto-redirect)
  def single_shop_access?
    !system_admin? && shops.count == 1
  end

  def single_shop
    shops.first if single_shop_access?
  end
end
