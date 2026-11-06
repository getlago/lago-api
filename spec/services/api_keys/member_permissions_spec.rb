# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::MemberPermissions do
  describe "RULES" do
    it "only names API key resources" do
      expect(described_class::RULES.keys - ApiKey::RESOURCES).to be_empty
    end

    it "only names existing role permissions" do
      required = described_class::RULES.values.flat_map(&:values).flatten.uniq

      expect(required - Permission::DATA.keys).to be_empty
    end
  end

  describe ".for" do
    subject(:permissions) { described_class.for(membership) }

    let(:organization) { create(:organization) }
    let(:membership) { create(:membership, organization:, role:) }

    context "when the member is an admin" do
      let(:role) { create(:role, :admin) }

      it "grants every permission" do
        expect(permissions).to eq(ApiKey.default_permissions)
      end
    end

    context "when the member has a custom role" do
      let(:role) do
        create(
          :role,
          organization:,
          permissions: %w[invoices:view invoices:update customers:view customers:create customers:update customers:delete]
        )
      end

      it "grants read for a resource whose view permissions the member holds" do
        expect(permissions["invoice"]).to eq(["read"])
      end

      it "grants write only when the member holds every write permission of the resource" do
        expect(permissions["customer"]).to eq(%w[read write])
      end

      it "grants nothing on a resource the member cannot view" do
        expect(permissions["plan"]).to eq([])
      end

      it "leaves resources without a rule to admins" do
        expect(permissions["x402_connection"]).to eq([])
      end

      it "lists every resource, so that the key is valid" do
        expect(permissions.keys).to match_array(ApiKey::RESOURCES)
      end
    end
  end
end
