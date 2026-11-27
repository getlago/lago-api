# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillEntitlementBooleanValuesJob do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:entitlement) { create(:entitlement, organization:, feature:) }
  let(:enabled) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
  let(:beta) { create(:privilege, organization:, feature:, code: "beta", value_type: "boolean") }
  let(:label) { create(:privilege, organization:, feature:, code: "label", value_type: "string") }
  let(:enabled_value) { create(:entitlement_value, organization:, entitlement:, privilege: enabled, value: "t") }
  let(:beta_value) { create(:entitlement_value, organization:, entitlement:, privilege: beta, value: "f") }
  let(:label_value) { create(:entitlement_value, organization:, entitlement:, privilege: label, value: "t") }

  def stored_value(entitlement_value)
    Entitlement::EntitlementValue.unscoped.find(entitlement_value.id).read_attribute(:value)
  end

  before do
    enabled_value
    beta_value
    label_value
  end

  it "rewrites the boolean values stored as t and f" do
    perform_job

    expect(stored_value(enabled_value)).to eq("true")
    expect(stored_value(beta_value)).to eq("false")
  end

  it "leaves the values of other privileges" do
    perform_job

    expect(stored_value(label_value)).to eq("t")
  end

  it "does not enqueue another batch when the walk is over" do
    expect { perform_job }.not_to have_enqueued_job(described_class)
  end

  context "when the value is discarded" do
    before { beta_value.discard! }

    it "backfills it too" do
      perform_job

      expect(stored_value(beta_value)).to eq("false")
    end
  end

  context "when the batch is full" do
    before { stub_const("#{described_class}::BATCH_SIZE", 1) }

    it "chains to the next batch from the last id" do
      first_id = [enabled_value.id, beta_value.id].min

      expect { perform_job }.to have_enqueued_job(described_class).with(first_id)
    end
  end

  context "when values are still stored as t or f after the walk" do
    it "reports instead of finishing silently" do
      allow(Rails.logger).to receive(:error)

      described_class.perform_now([enabled_value.id, beta_value.id].max)

      expect(Rails.logger).to have_received(:error).with(/still stored as t or f/)
    end
  end
end
