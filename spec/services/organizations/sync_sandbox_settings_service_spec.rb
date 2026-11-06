# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::SyncSandboxSettingsService do
  subject(:result) { described_class.call(organization: production, actor:) }

  include_context "with mocked security logger"

  let(:actor) { create(:user) }
  let(:feature_flag) { FeatureFlag::DEFINITION.keys.first }
  let(:production) do
    create(:organization, premium_integrations: %w[okta security_logs], feature_flags: [feature_flag],
      authentication_methods: %w[email_password okta])
  end
  let(:sandbox) do
    create(:organization, :sandbox, production_organization: production, premium_integrations: %w[netsuite],
      authentication_methods: %w[email_password google_oauth])
  end

  before { sandbox }

  it "copies the settings and lists what changed" do
    expect(result.sandbox_organization.reload).to have_attributes(premium_integrations: %w[okta security_logs],
      feature_flags: [feature_flag], authentication_methods: %w[email_password okta])
    expect(result.changes).to eq(
      premium_integrations: {added: %w[okta security_logs], removed: %w[netsuite]},
      feature_flags: {added: [feature_flag], removed: []},
      authentication_methods: {added: %w[okta], removed: %w[google_oauth]}
    )
  end

  it "logs the login methods change on the sandbox with the actor" do
    result

    expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "organization",
      log_event: "organization.authentication_methods_updated", user: actor,
      resources: {authentication_methods: {deleted: %w[google_oauth], added: %w[okta]}})
  end

  it "expires the sandbox API key cache" do
    allow(ApiKeys::CacheService).to receive(:expire_all_cache)

    result

    expect(ApiKeys::CacheService).to have_received(:expire_all_cache).with(sandbox)
  end

  it "reads production again under the lock, so a stale copy cannot undo a change" do
    stale = Organization.find(production.id)
    production.update!(premium_integrations: %w[okta])

    described_class.call!(organization: stale)

    expect(sandbox.reload.premium_integrations).to eq(%w[okta])
  end

  it "skips feature flags that are not defined anymore" do
    production.update_columns(feature_flags: [feature_flag, "removed_flag"]) # rubocop:disable Rails/SkipsModelValidations

    expect(result.sandbox_organization.reload.feature_flags).to eq([feature_flag])
  end

  context "when the sandbox is already in sync" do
    before { described_class.call!(organization: production) }

    it "changes nothing" do
      expect { result }.not_to change { sandbox.reload.updated_at }
      expect(result.changes).to eq({})
    end
  end

  context "without a sandbox" do
    let(:sandbox) { nil }

    it "does nothing" do
      expect(result.sandbox_organization).to be_nil
      expect(result.changes).to eq({})
    end
  end
end
