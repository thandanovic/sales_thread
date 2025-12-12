class UpdateMembershipRoles < ActiveRecord::Migration[8.0]
  def up
    # Convert old roles to new simplified roles:
    # owner -> manager (shop owners become managers)
    # admin -> manager (shop admins become managers)
    # member -> agent (regular members become agents)
    execute <<-SQL
      UPDATE memberships SET role = 'manager' WHERE role IN ('owner', 'admin');
    SQL
    execute <<-SQL
      UPDATE memberships SET role = 'agent' WHERE role = 'member';
    SQL
  end

  def down
    # Reverse: manager -> owner (best guess), agent -> member
    execute <<-SQL
      UPDATE memberships SET role = 'owner' WHERE role = 'manager';
    SQL
    execute <<-SQL
      UPDATE memberships SET role = 'member' WHERE role = 'agent';
    SQL
  end
end
