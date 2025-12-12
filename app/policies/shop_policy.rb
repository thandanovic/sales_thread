class ShopPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    system_admin? || user_is_member?
  end

  def create?
    # Only system admins can create new shops
    system_admin?
  end

  def update?
    system_admin? || user_is_manager?
  end

  def destroy?
    system_admin? || user_is_manager?
  end

  # OLX-related actions
  def test_olx_connection?
    system_admin? || user_is_manager?
  end

  def setup_olx_data?
    system_admin? || user_is_manager?
  end

  def sync_from_olx?
    system_admin? || user_is_manager?
  end

  # Member management
  def manage_members?
    system_admin? || user_is_manager?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if system_admin?
        scope.all
      elsif user.present?
        scope.joins(:memberships).where(memberships: { user_id: user.id })
      else
        scope.none
      end
    end
  end

  private

  def user_is_member?
    return false unless user && record
    record.users.include?(user)
  end

  def user_is_manager?
    return false unless user && record
    membership = record.memberships.find_by(user: user)
    membership&.manager?
  end
end
