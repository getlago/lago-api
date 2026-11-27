# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::ActivateService do
  subject(:result) { described_class.call(organization:) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }

  before { allow(ApiKeys::CacheService).to receive(:expire_all_cache) }

  it "opens the organization and clears its API key cache" do
    expect(result).to be_success
    expect(result.organization).to eq(organization)
    expect(result.activated).to be(true)
    expect(organization.reload.activation_status).to eq("active")
    expect(ApiKeys::CacheService).to have_received(:expire_all_cache).with(organization).once
  end

  it "produces one security log naming billing-accounts" do
    result

    expect(security_logger).to have_received(:produce).once.with(
      organization:,
      log_type: "organization",
      log_event: "organization.activated",
      user: nil,
      resources: {activated_by: "billing_accounts"}
    )
  end

  context "with a CS admin" do
    subject(:result) { described_class.call(organization:, actor:, reason: "Opened for a sales prospect") }

    let(:actor) { create(:user, cs_admin: true) }

    it "produces one security log naming the CS admin and the reason" do
      expect(result).to be_success

      expect(security_logger).to have_received(:produce).once.with(
        organization:,
        log_type: "organization",
        log_event: "organization.activated",
        user: actor,
        resources: {activated_by: "cs_admin", reason: "Opened for a sales prospect"}
      )
    end
  end

  it "reads the organization again under the lock, so a stale copy is not activated twice" do
    stale = Organization.find(organization.id)
    organization.update!(activation_status: "active")

    expect(described_class.call(organization: stale)).to have_attributes(success?: true, activated: false)
    expect(ApiKeys::CacheService).not_to have_received(:expire_all_cache)
    expect(security_logger).not_to have_received(:produce)
  end

  context "with an organization that no longer passes its validations" do
    before { organization.update_column(:invoice_footer, "a" * 601) } # rubocop:disable Rails/SkipsModelValidations

    it "opens it all the same and records the change", versioning: true do
      expect { result }.to change { organization.versions.count }.by(1)

      expect(result).to be_success
      expect(organization.reload.activation_status).to eq("active")
    end
  end

  context "with an active organization" do
    let(:organization) { create(:organization, :self_serve) }

    it "succeeds without changing anything" do
      expect { result }.not_to change { organization.reload.updated_at }

      expect(result).to be_success
      expect(result.activated).to be(false)
      expect(organization.reload.activation_status).to eq("active")
      expect(ApiKeys::CacheService).not_to have_received(:expire_all_cache)
    end

    it_behaves_like "does not produce a security log"
  end

  context "with an organization that is not self-serve" do
    let(:organization) { create(:organization) }

    it "refuses" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("organization_not_self_serve_production")
      expect(security_logger).not_to have_received(:produce)
    end
  end

  context "with a sandbox" do
    let(:organization) do
      create(:organization, :self_serve, :sandbox, production_organization: create(:organization, :self_serve))
    end

    it "refuses" do
      expect(result).to be_failure
      expect(result.error.code).to eq("organization_not_self_serve_production")
    end
  end

  context "with a stale copy of an organization that is no longer self-serve" do
    subject(:result) { described_class.call(organization: stale) }

    let(:stale) { Organization.find(organization.id) }

    before do
      stale
      organization.update_columns(self_serve: false, activation_status: "active") # rubocop:disable Rails/SkipsModelValidations
    end

    it "refuses from the row read under the lock" do
      expect(result).to be_failure
      expect(result.error.code).to eq("organization_not_self_serve_production")
    end
  end

  context "with two concurrent calls", transaction: false do
    it "activates the organization once" do
      organization_id = organization.id

      # The first call pauses after its checks, holding the row lock, so the second one starts while the first
      # activation is not committed yet.
      first_call = Queue.new
      first_call << true
      checked = Queue.new
      resume = Queue.new

      allow_any_instance_of(described_class).to receive(:activate).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        if first_call.pop(timeout: 0)
          checked << true
          resume.pop
        end

        original.call(*args)
      end

      activate = lambda do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(organization: Organization.find(organization_id))
          end
        end
      end

      first = activate.call
      checked.pop
      second = activate.call
      sleep 0.5
      resume << true

      expect([first.value, second.value]).to all(be_success)
      expect(organization.reload.activation_status).to eq("active")
      expect(ApiKeys::CacheService).to have_received(:expire_all_cache).once
      expect(security_logger).to have_received(:produce).once
    end
  end
end
