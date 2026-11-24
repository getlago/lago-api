# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261101111004_merge_product_role_permissions")

RSpec.describe MergeProductRolePermissions do
  subject(:migration) { described_class.new }

  let(:organization) { create(:organization) }
  let(:legacy_permissions) do
    %w[
      product_categories:view product_categories:create product_categories:update product_categories:delete
      product_filters:view product_filters:create product_filters:update product_filters:delete
      products:view organizations:read product_categories_extra:view
    ]
  end
  let(:timestamp) { 2.days.ago.change(usec: 0) }
  let(:role_with_legacy_permissions) do
    create(:role, organization:, permissions: legacy_permissions, created_at: timestamp, updated_at: timestamp)
  end
  let(:role_without_legacy_permissions) do
    create(:role, organization:, permissions: ["organizations:view"], created_at: timestamp, updated_at: timestamp)
  end
  let(:discarded_role) do
    create(:role, organization:, permissions: ["product_filters:view", "organizations:read"], deleted_at: timestamp,
      created_at: timestamp, updated_at: timestamp)
  end
  let(:predefined_role) { create(:role, :finance, created_at: timestamp, updated_at: timestamp) }

  describe "#up" do
    it "merges exact legacy grants on custom roles, including discarded roles, without touching other roles" do
      changed_role = role_with_legacy_permissions
      unchanged_role = role_without_legacy_permissions
      deleted_role = discarded_role
      system_role = predefined_role
      system_role_updated_at = system_role.updated_at

      migration.up

      expect(changed_role.reload.permissions).to eq(%w[
        organizations:read product_categories_extra:view products:create products:delete products:update products:view
      ])
      expect(changed_role.updated_at).to be > timestamp
      expect(unchanged_role.reload).to have_attributes(permissions: ["organizations:view"], updated_at: timestamp)
      expect(deleted_role.reload.permissions).to eq(%w[organizations:read products:view])
      expect(deleted_role.updated_at).to be > timestamp
      expect(system_role.reload).to have_attributes(permissions: [], updated_at: system_role_updated_at)

      expect { migration.up }.not_to change { Role.unscoped.order(:id).pluck(:id, :permissions, :updated_at) }
    end
  end

  describe "#down" do
    it "raises because the original grants cannot be reconstructed" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
