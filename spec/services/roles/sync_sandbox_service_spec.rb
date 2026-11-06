# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::SyncSandboxService do
  subject(:result) { described_class.call(role:, actor:) }

  include_context "with mocked security logger"

  let(:production) { create(:organization, :with_sandbox) }
  let(:sandbox) { production.sandbox_organization }
  let(:actor) { create(:user) }
  let(:role) { create(:role, organization: production, code: "auditor", name: "Auditor", permissions: %w[organization:view]) }

  it "creates the sandbox copy" do
    expect(result.sandbox_role).to have_attributes(organization_id: sandbox.id, code: "auditor", name: "Auditor",
      permissions: %w[organization:view])
    expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "role",
      log_event: "role.created", user: actor, resources: {role_code: "auditor", permissions: %w[organization:view]})
  end

  context "when the copy exists" do
    let!(:copy) { create(:role, organization: sandbox, code: "auditor", name: "Old", permissions: %w[organization:view]) }

    it "updates it" do
      role.update!(name: "Auditor", permissions: %w[organization:view customers:view])

      expect(result.sandbox_role).to eq(copy)
      expect(copy.reload).to have_attributes(name: "Auditor", permissions: %w[customers:view organization:view])
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "role",
        log_event: "role.updated", user: actor, resources: {role_code: "auditor"})
    end

    it "discards it with the production role" do
      role.discard!

      expect(result.sandbox_role).to be_nil
      expect(copy.reload).to be_discarded
    end
  end

  context "with a predefined role" do
    let(:role) { create(:role, :admin) }

    it "returns the role itself" do
      expect(result.sandbox_role).to eq(role)
    end
  end

  context "without a sandbox" do
    let(:production) { create(:organization) }

    it "creates nothing" do
      expect { result }.to change(Role, :count).by(1) # the production role only
      expect(result.sandbox_role).to be_nil
    end
  end
end
