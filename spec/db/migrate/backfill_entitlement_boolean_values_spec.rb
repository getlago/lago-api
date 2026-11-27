# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261127094934_backfill_entitlement_boolean_values")

RSpec.describe BackfillEntitlementBooleanValues do
  subject(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:entitlement) { create(:entitlement, organization:, feature:) }
  let(:enabled) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
  let(:beta) { create(:privilege, organization:, feature:, code: "beta", value_type: "boolean") }
  let(:label) { create(:privilege, organization:, feature:, code: "label", value_type: "string") }
  let(:enabled_value) { create(:entitlement_value, organization:, entitlement:, privilege: enabled, value: "t") }
  let(:beta_value) { create(:entitlement_value, organization:, entitlement:, privilege: beta, value: "f", deleted_at: 1.day.ago) }
  let(:label_value) { create(:entitlement_value, organization:, entitlement:, privilege: label, value: "t") }

  before do
    enabled_value
    beta_value
    label_value
  end

  it "rewrites the boolean values stored as t and f, deleted ones included" do
    migrate

    expect(enabled_value.reload.value).to eq("true")
    expect(Entitlement::EntitlementValue.with_discarded.find(beta_value.id).value).to eq("false")
  end

  it "leaves the values of other privileges" do
    migrate

    expect(label_value.reload.value).to eq("t")
  end
end
