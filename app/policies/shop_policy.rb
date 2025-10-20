class ShopPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present? && user_is_member?
  end

  def create?
    user.present?
  end

  def update?
    user.present? && (user_is_owner? || user_is_admin?)
  end

  def destroy?
    user.present? && user_is_owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.present?
        scope.joins(:memberships).where(memberships: { user_id: user.id })
      else
        scope.none
      end
    end
  end

  private

  def user_is_member?
    record.users.include?(user)
  end

  def user_is_owner?
    membership = record.memberships.find_by(user: user)
    membership&.owner?
  end

  def user_is_admin?
    membership = record.memberships.find_by(user: user)
    membership&.admin?
  end
end
