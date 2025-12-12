require 'rails_helper'

RSpec.describe ShopPolicy, type: :policy do
  let(:shop) { create(:shop) }
  let(:admin_user) { create(:user, :admin) }
  let(:manager_user) { create(:user) }
  let(:agent_user) { create(:user) }
  let(:non_member_user) { create(:user) }

  before do
    create(:membership, :manager, user: manager_user, shop: shop)
    create(:membership, :agent, user: agent_user, shop: shop)
  end

  subject { described_class }

  describe '#index?' do
    it 'permits any authenticated user' do
      expect(subject.new(admin_user, Shop)).to permit_action(:index)
      expect(subject.new(manager_user, Shop)).to permit_action(:index)
      expect(subject.new(agent_user, Shop)).to permit_action(:index)
      expect(subject.new(non_member_user, Shop)).to permit_action(:index)
    end

    it 'forbids unauthenticated users' do
      expect(subject.new(nil, Shop)).to forbid_action(:index)
    end
  end

  describe '#show?' do
    context 'for system admin' do
      it 'permits access to any shop' do
        expect(subject.new(admin_user, shop)).to permit_action(:show)
      end
    end

    context 'for shop members' do
      it 'permits managers to view the shop' do
        expect(subject.new(manager_user, shop)).to permit_action(:show)
      end

      it 'permits agents to view the shop' do
        expect(subject.new(agent_user, shop)).to permit_action(:show)
      end
    end

    context 'for non-members' do
      it 'forbids access' do
        expect(subject.new(non_member_user, shop)).to forbid_action(:show)
      end
    end
  end

  describe '#create?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, Shop.new)).to permit_action(:create)
    end

    it 'forbids regular users' do
      expect(subject.new(manager_user, Shop.new)).to forbid_action(:create)
      expect(subject.new(agent_user, Shop.new)).to forbid_action(:create)
    end
  end

  describe '#update?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, shop)).to permit_action(:update)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, shop)).to permit_action(:update)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, shop)).to forbid_action(:update)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, shop)).to forbid_action(:update)
    end
  end

  describe '#destroy?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, shop)).to permit_action(:destroy)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, shop)).to permit_action(:destroy)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, shop)).to forbid_action(:destroy)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, shop)).to forbid_action(:destroy)
    end
  end

  describe '#test_olx_connection?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, shop)).to permit_action(:test_olx_connection)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, shop)).to permit_action(:test_olx_connection)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, shop)).to forbid_action(:test_olx_connection)
    end
  end

  describe '#setup_olx_data?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, shop)).to permit_action(:setup_olx_data)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, shop)).to permit_action(:setup_olx_data)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, shop)).to forbid_action(:setup_olx_data)
    end
  end

  describe '#sync_from_olx?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, shop)).to permit_action(:sync_from_olx)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, shop)).to permit_action(:sync_from_olx)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, shop)).to forbid_action(:sync_from_olx)
    end
  end

  describe 'Scope' do
    let!(:another_shop) { create(:shop) }

    it 'returns all shops for system admin' do
      scope = ShopPolicy::Scope.new(admin_user, Shop).resolve
      expect(scope).to include(shop, another_shop)
    end

    it 'returns only member shops for regular users' do
      scope = ShopPolicy::Scope.new(manager_user, Shop).resolve
      expect(scope).to include(shop)
      expect(scope).not_to include(another_shop)
    end

    it 'returns no shops for unauthenticated users' do
      scope = ShopPolicy::Scope.new(nil, Shop).resolve
      expect(scope).to be_empty
    end
  end
end
