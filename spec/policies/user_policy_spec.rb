require 'rails_helper'

RSpec.describe UserPolicy, type: :policy do
  let(:admin_user) { create(:user, :admin) }
  let(:regular_user) { create(:user) }
  let(:target_user) { create(:user) }

  subject { described_class }

  describe '#index?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, User)).to permit_action(:index)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, User)).to forbid_action(:index)
    end
  end

  describe '#show?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, target_user)).to permit_action(:show)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, target_user)).to forbid_action(:show)
    end
  end

  describe '#create?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, User.new)).to permit_action(:create)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, User.new)).to forbid_action(:create)
    end
  end

  describe '#update?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, target_user)).to permit_action(:update)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, target_user)).to forbid_action(:update)
    end
  end

  describe '#destroy?' do
    it 'permits system admin to delete other users' do
      expect(subject.new(admin_user, target_user)).to permit_action(:destroy)
    end

    it 'forbids system admin from deleting themselves' do
      expect(subject.new(admin_user, admin_user)).to forbid_action(:destroy)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, target_user)).to forbid_action(:destroy)
    end
  end

  describe '#impersonate?' do
    it 'permits system admin to impersonate other users' do
      expect(subject.new(admin_user, target_user)).to permit_action(:impersonate)
    end

    it 'forbids system admin from impersonating themselves' do
      expect(subject.new(admin_user, admin_user)).to forbid_action(:impersonate)
    end

    it 'forbids regular users' do
      expect(subject.new(regular_user, target_user)).to forbid_action(:impersonate)
    end
  end

  describe 'Scope' do
    it 'returns all users for system admin' do
      scope = UserPolicy::Scope.new(admin_user, User).resolve
      expect(scope).to include(admin_user, target_user)
    end

    it 'returns no users for regular users' do
      scope = UserPolicy::Scope.new(regular_user, User).resolve
      expect(scope).to be_empty
    end
  end
end
