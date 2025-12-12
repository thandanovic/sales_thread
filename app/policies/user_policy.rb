class UserPolicy < ApplicationPolicy
  # Only system admins can manage users
  def index?
    system_admin?
  end

  def show?
    system_admin?
  end

  def create?
    system_admin?
  end

  def update?
    system_admin?
  end

  def destroy?
    system_admin? && record != user # Can't delete yourself
  end

  # Impersonation - admin only, cannot impersonate yourself
  def impersonate?
    system_admin? && record != user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if system_admin?
        scope.all
      else
        scope.none
      end
    end
  end
end
