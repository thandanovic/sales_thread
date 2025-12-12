class ProductPolicy < ApplicationPolicy
  def index?
    system_admin? || user_is_member?
  end

  def show?
    system_admin? || user_is_member?
  end

  def create?
    system_admin? || user_is_manager?
  end

  def update?
    system_admin? || user_is_manager?
  end

  def destroy?
    system_admin? || user_is_manager?
  end

  # OLX sync actions - ALL members can sync (including agents)
  def publish_to_olx?
    system_admin? || user_is_member?
  end

  def update_on_olx?
    system_admin? || user_is_member?
  end

  def remove_from_olx?
    system_admin? || user_is_member?
  end

  # Bulk actions - only managers can do bulk CRUD operations
  def bulk_update_margin?
    system_admin? || user_is_manager?
  end

  def bulk_destroy?
    system_admin? || user_is_manager?
  end

  # Bulk OLX sync - ALL members can do
  def bulk_publish_to_olx?
    system_admin? || user_is_member?
  end

  def bulk_update_on_olx?
    system_admin? || user_is_member?
  end

  def bulk_remove_from_olx?
    system_admin? || user_is_member?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if system_admin?
        scope.all
      elsif user.present?
        shop_ids = user.shops.pluck(:id)
        scope.where(shop_id: shop_ids)
      else
        scope.none
      end
    end
  end

  private

  def shop
    record.shop
  end

  def user_is_member?
    return false unless user && shop
    system_admin? || shop.users.include?(user)
  end

  def user_is_manager?
    return false unless user && shop
    membership = shop.memberships.find_by(user: user)
    membership&.manager?
  end
end
