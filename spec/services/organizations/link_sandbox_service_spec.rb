# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::LinkSandboxService do
  subject(:result) { described_class.call(production_organization: production, sandbox_organization: target, actor:) }

  include_context "with self-serve enabled"
  include_context "with mocked security logger"

  let(:actor) { create(:user) }
  let(:production) { create(:organization, premium_integrations: %w[okta]) }
  let(:target) { create(:organization) }
  let(:member) { create(:user) }

  before { create(:membership, user: member, organization: production, roles: %i[admin]) }

  it "links the target as the sandbox and mirrors settings and members" do
    expect(result).to be_success
    expect(target.reload).to have_attributes(environment: "sandbox", production_organization_id: production.id,
      premium_integrations: %w[okta])
    expect(production.reload.sandbox_organization).to eq(target)
    expect(target.memberships.active.sole).to have_attributes(user: member, roles: [Role.find_by(code: "admin")])
  end

  it "returns the sandbox with the settings it mirrored" do
    expect(result.sandbox_organization).to have_attributes(environment: "sandbox", premium_integrations: %w[okta])
  end

  it "keeps the target's members that production also has, with production's roles" do
    create(:membership, user: member, organization: target, roles: %i[finance])

    expect(result).to be_success
    expect(target.memberships.active.sole.roles.map(&:code)).to eq(%w[admin])
  end

  context "when self-serve is off" do
    let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "false"} }

    it "refuses it" do
      expect(result.error.code).to eq("self_serve_disabled")
    end
  end

  context "with unknown organizations" do
    it "answers not found" do
      expect(described_class.call(production_organization: nil, sandbox_organization: target).error.resource)
        .to eq("production_organization")
      expect(described_class.call(production_organization: production, sandbox_organization: nil).error.resource)
        .to eq("sandbox_organization")
    end
  end

  context "with the same organization twice" do
    let(:target) { production }

    it "refuses it" do
      expect(result.error.messages).to eq(sandbox_organization_id: ["cannot_link_organization_to_itself"])
    end
  end

  describe "refusals" do
    def refusal
      result.error&.code
    end

    it "refuses a production that is a sandbox" do
      production.update!(environment: "sandbox", production_organization: create(:organization))

      expect(refusal).to eq("production_is_a_sandbox")
    end

    it "refuses a production that already has a sandbox" do
      create(:organization, :sandbox, production_organization: production)

      expect(refusal).to eq("production_already_has_sandbox")
    end

    it "refuses a target that is already a sandbox, of this production included" do
      target.update!(environment: "sandbox", production_organization: production)

      expect(refusal).to eq("sandbox_already_linked")
    end

    it "refuses a target that has a sandbox" do
      create(:organization, :sandbox, production_organization: target)

      expect(refusal).to eq("sandbox_has_sandbox")
    end

    it "refuses a self-serve target" do
      target.update!(self_serve: true)

      expect(refusal).to eq("sandbox_is_self_serve")
    end

    it "refuses a target with its own SSO integration" do
      create(:okta_integration, organization: target)

      expect(refusal).to eq("sandbox_has_sso_integration")
    end

    it "refuses a target with premium integrations production lacks" do
      target.update!(premium_integrations: %w[api_permissions])

      expect(refusal).to eq("sandbox_has_extra_premium_integrations")
    end

    it "refuses a target with feature flags production lacks" do
      target.update!(feature_flags: [FeatureFlag::DEFINITION.keys.first])

      expect(refusal).to eq("sandbox_has_extra_feature_flags")
    end

    it "refuses a target whose free login methods are stricter" do
      target.update!(authentication_methods: %w[google_oauth])

      expect(refusal).to eq("sandbox_has_stricter_authentication")
    end

    it "refuses a target with pending invites" do
      create(:invite, organization: target)

      expect(refusal).to eq("sandbox_has_pending_invites")
    end

    it "refuses a target with members production lacks" do
      create(:membership, organization: target)

      expect(refusal).to eq("sandbox_has_other_members")
    end

    it "refuses a target with a custom role production lacks" do
      create(:role, organization: target, code: "ops")

      expect(refusal).to eq("sandbox_has_other_roles")
    end

    it "refuses a target with a custom role production defines differently" do
      create(:role, organization: production, code: "ops", name: "Ops", permissions: %w[organization:view customers:view])
      create(:role, organization: target, code: "ops", name: "Ops", permissions: %w[organization:view])

      expect(refusal).to eq("sandbox_has_other_roles")
      expect(target.roles.sole.permissions).to eq(%w[organization:view])
    end

    it "refuses a target with a custom role production names differently" do
      create(:role, organization: production, code: "ops", name: "Ops", permissions: %w[organization:view])
      create(:role, organization: target, code: "ops", name: "Operations", permissions: %w[organization:view])

      expect(refusal).to eq("sandbox_has_other_roles")
    end

    it "writes nothing when it refuses" do
      create(:membership, organization: target)

      expect { result }.not_to change { target.reload.attributes }
    end
  end

  context "when the target has the custom roles of production" do
    before do
      create(:role, organization: production, code: "ops", name: "Ops", permissions: %w[organization:view customers:view])
      create(:role, organization: target, code: "ops", name: "Ops", permissions: %w[customers:view organization:view])
      create(:role, organization: create(:organization), code: "other", name: "Other")
      create(:role, organization: target, code: "old", name: "Old").discard!
    end

    it "links it" do
      expect(result).to be_success
      expect(target.reload).to be_sandbox
    end

    it "copies the custom roles of production that no member holds" do
      create(:role, organization: production, code: "unused", name: "Unused", permissions: %w[customers:view])

      expect(result).to be_success
      expect(target.roles.map { [it.code, it.name, it.permissions.sort] }).to match_array([
        ["ops", "Ops", %w[customers:view organization:view]],
        ["unused", "Unused", %w[customers:view]]
      ])
    end
  end

  context "when another sandbox of production is created during the link" do
    before do
      allow(target).to receive(:update!).and_wrap_original do |original, *args, **kwargs|
        create(:organization, :sandbox, production_organization: production)
        original.call(*args, **kwargs)
      end
    end

    it "answers as the uniqueness validation would" do
      expect(result.error.messages).to eq(production_organization_id: ["value_already_exist"])
      expect(target.reload).to have_attributes(environment: "production", production_organization_id: nil)
    end
  end

  context "when another link holds the lock" do
    before do
      allow(Organization).to receive(:with_advisory_lock!)
        .and_raise(WithAdvisoryLock::FailedToAcquireLock.new(described_class::LOCK_KEY))
    end

    it "fails with lock_acquisition_failed" do
      expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
      expect(result.error.code).to eq("lock_acquisition_failed")
      expect(target.reload).to be_production
    end
  end

  context "when a mirror fails" do
    before do
      allow(Memberships::SyncSandboxService).to receive(:call!)
        .and_raise(BaseResult.new.forbidden_failure!(code: "sandbox_managed_by_production").error)
    end

    it "rolls the link back" do
      expect(result).to be_failure
      expect(target.reload).to have_attributes(environment: "production", production_organization_id: nil)
    end
  end

  context "when the link holds its locks", transaction: false do
    it "lets production keep writing its own records" do
      syncing = Queue.new
      release = Queue.new
      allow(Memberships::SyncSandboxService).to receive(:call!) do
        syncing << true
        release.pop
      end

      link = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          described_class.call(production_organization: production, sandbox_organization: target, actor:)
        end
      end

      begin
        Timeout.timeout(10) { syncing.pop }
        # A child insert takes FOR KEY SHARE on its organization, which FOR UPDATE would block.
        customer = ApplicationRecord.transaction do
          ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '2s'")
          create(:customer, organization: production)
        end
      ensure
        release << true
      end

      expect(customer).to be_persisted
      expect(Timeout.timeout(10) { link.value }).to be_success
    end
  end
end
