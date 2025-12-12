require 'rails_helper'

RSpec.describe ProductPolicy, type: :policy do
  let(:shop) { create(:shop) }
  let(:product) { create(:product, shop: shop) }
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
    it 'permits system admin' do
      expect(subject.new(admin_user, product)).to permit_action(:index)
    end

    it 'permits shop members' do
      expect(subject.new(manager_user, product)).to permit_action(:index)
      expect(subject.new(agent_user, product)).to permit_action(:index)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, product)).to forbid_action(:index)
    end
  end

  describe '#show?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, product)).to permit_action(:show)
    end

    it 'permits shop members' do
      expect(subject.new(manager_user, product)).to permit_action(:show)
      expect(subject.new(agent_user, product)).to permit_action(:show)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, product)).to forbid_action(:show)
    end
  end

  describe '#create?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, product)).to permit_action(:create)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, product)).to permit_action(:create)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, product)).to forbid_action(:create)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, product)).to forbid_action(:create)
    end
  end

  describe '#update?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, product)).to permit_action(:update)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, product)).to permit_action(:update)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, product)).to forbid_action(:update)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, product)).to forbid_action(:update)
    end
  end

  describe '#destroy?' do
    it 'permits system admin' do
      expect(subject.new(admin_user, product)).to permit_action(:destroy)
    end

    it 'permits managers' do
      expect(subject.new(manager_user, product)).to permit_action(:destroy)
    end

    it 'forbids agents' do
      expect(subject.new(agent_user, product)).to forbid_action(:destroy)
    end

    it 'forbids non-members' do
      expect(subject.new(non_member_user, product)).to forbid_action(:destroy)
    end
  end

  describe 'OLX sync actions' do
    %w[publish_to_olx update_on_olx remove_from_olx].each do |action|
      describe "##{action}?" do
        it 'permits system admin' do
          expect(subject.new(admin_user, product)).to permit_action(action)
        end

        it 'permits managers' do
          expect(subject.new(manager_user, product)).to permit_action(action)
        end

        it 'permits agents (they can sync with OLX)' do
          expect(subject.new(agent_user, product)).to permit_action(action)
        end

        it 'forbids non-members' do
          expect(subject.new(non_member_user, product)).to forbid_action(action)
        end
      end
    end
  end

  describe 'bulk CRUD actions' do
    %w[bulk_update_margin bulk_destroy].each do |action|
      describe "##{action}?" do
        it 'permits system admin' do
          expect(subject.new(admin_user, product)).to permit_action(action)
        end

        it 'permits managers' do
          expect(subject.new(manager_user, product)).to permit_action(action)
        end

        it 'forbids agents' do
          expect(subject.new(agent_user, product)).to forbid_action(action)
        end
      end
    end
  end

  describe 'bulk OLX sync actions' do
    %w[bulk_publish_to_olx bulk_update_on_olx bulk_remove_from_olx].each do |action|
      describe "##{action}?" do
        it 'permits system admin' do
          expect(subject.new(admin_user, product)).to permit_action(action)
        end

        it 'permits managers' do
          expect(subject.new(manager_user, product)).to permit_action(action)
        end

        it 'permits agents (they can sync with OLX)' do
          expect(subject.new(agent_user, product)).to permit_action(action)
        end
      end
    end
  end

  describe 'Scope' do
    let!(:another_shop) { create(:shop) }
    let!(:another_product) { create(:product, shop: another_shop) }

    it 'returns all products for system admin' do
      scope = ProductPolicy::Scope.new(admin_user, Product).resolve
      expect(scope).to include(product, another_product)
    end

    it 'returns only products from member shops for regular users' do
      scope = ProductPolicy::Scope.new(manager_user, Product).resolve
      expect(scope).to include(product)
      expect(scope).not_to include(another_product)
    end
  end
end
