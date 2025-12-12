class OlxCategoryTemplatePolicy < ApplicationPolicy
  # View actions - ALL members can view
  def index?
    system_admin? || user_is_member?
  end

  def show?
    system_admin? || user_is_member?
  end

  # Write actions - only managers can manage templates
  def create?
    system_admin? || user_is_manager?
  end

  def update?
    system_admin? || user_is_manager?
  end

  def destroy?
    system_admin? || user_is_manager?
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
