# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::SyncCatalogPlanEntitlementsService do
  subject(:result) { sync }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan, refind: true) { create(:catalog_plan, organization:) }
  let_it_be(:seats) { create(:feature, organization:, code: "seats") }
  let_it_be(:seats_max) { create(:privilege, feature: seats, code: "max", value_type: "integer") }
  let_it_be(:seats_tier) { create(:privilege, feature: seats, code: "tier", value_type: "string") }
  let_it_be(:sso) { create(:feature, organization:, code: "sso") }
  let_it_be(:api) { create(:feature, organization:, code: "api") }
  let_it_be(:api_calls) { create(:privilege, feature: api, code: "calls", value_type: "integer") }

  let(:features) { Entitlement::Feature.where(organization:).includes(:privileges).index_by(&:code) }
  let(:entitlements) { {"seats" => {"max" => "10", "tier" => "gold"}, "sso" => {}} }

  def sync
    current_entitlements = Entitlement::Entitlement.where(catalog_plan:).includes(:values).to_a
    described_class.call(catalog_plan:, entitlements:, current_entitlements:, features:)
  end

  def entitlements_of(owner)
    Entitlement::Entitlement.where(catalog_plan: owner).includes(:feature, values: :privilege).to_h do |entitlement|
      [entitlement.feature.code, entitlement.values.to_h { [it.privilege.code, it.value] }]
    end
  end

  it "creates the entitlements and values on the catalog plan" do
    expect(result).to be_success
    expect(result.created_entitlements).to eq(%w[seats sso])
    expect(result.created_values).to eq(%w[seats.max seats.tier])
    expect(result.removed_entitlements).to eq([])
    expect(result.updated_values).to eq([])
    expect(result.removed_values).to eq([])

    expect(entitlements_of(catalog_plan)).to eq(entitlements)
    expect(Entitlement::Entitlement.where(catalog_plan:).pluck(:organization_id, :plan_id).uniq).to eq([[organization.id, nil]])
    expect(Entitlement::EntitlementValue.where(organization:).count).to eq(2)
  end

  it "changes nothing on a second run" do
    sync

    expect { result }
      .to not_change { Entitlement::Entitlement.unscoped.count }
      .and not_change { Entitlement::EntitlementValue.unscoped.count }
      .and not_change { Entitlement::EntitlementValue.maximum(:updated_at) }

    changes = [
      result.created_entitlements,
      result.removed_entitlements,
      result.created_values,
      result.updated_values,
      result.removed_values
    ]
    expect(changes).to all(eq([]))
  end

  context "when the catalog plan already has entitlements" do
    let(:entitlements) { {"seats" => {"max" => "10"}, "sso" => {}} }

    let(:seats_entitlement) { create(:entitlement, :catalog_plan, catalog_plan:, feature: seats) }
    let(:api_entitlement) { create(:entitlement, :catalog_plan, catalog_plan:, feature: api) }
    let(:seats_max_value) { create(:entitlement_value, entitlement: seats_entitlement, privilege: seats_max, value: "5") }
    let(:seats_tier_value) { create(:entitlement_value, entitlement: seats_entitlement, privilege: seats_tier, value: "silver") }
    let(:api_calls_value) { create(:entitlement_value, entitlement: api_entitlement, privilege: api_calls, value: "100") }

    before do
      seats_max_value
      seats_tier_value
      api_calls_value
    end

    it "converges them to the given entitlements, discarding what is no longer there" do
      expect(result.created_entitlements).to eq(%w[sso])
      expect(result.removed_entitlements).to eq(%w[api])
      expect(result.created_values).to eq([])
      expect(result.updated_values).to eq(%w[seats.max])
      expect(result.removed_values).to eq(%w[seats.tier])

      expect(entitlements_of(catalog_plan)).to eq(entitlements)
      expect(seats_max_value.reload.value).to eq("10")
      expect(seats_entitlement.reload).not_to be_discarded
      expect(api_entitlement.reload).to be_discarded
      expect(Entitlement::EntitlementValue.with_discarded.where(id: [seats_tier_value.id, api_calls_value.id]))
        .to all(be_discarded)
    end
  end

  context "when the catalog plan has a value on a discarded privilege" do
    let(:entitlements) { {"seats" => {"max" => "10"}} }
    let(:seats_entitlement) { create(:entitlement, :catalog_plan, catalog_plan:, feature: seats) }
    let(:legacy_value) do
      legacy = create(:privilege, feature: seats, code: "legacy", value_type: "string")
      create(:entitlement_value, entitlement: seats_entitlement, privilege: legacy, value: "kept").tap { legacy.discard! }
    end

    before { legacy_value }

    it "leaves the value as it is" do
      expect(result).to be_success
      expect(result.created_values).to eq(%w[seats.max])
      expect(result.removed_values).to eq([])
      expect(legacy_value.reload).not_to be_discarded
    end
  end

  context "when another catalog plan has entitlements on the same features" do
    let(:other_catalog_plan) { create(:catalog_plan, organization:) }
    let(:other_entitlement) { create(:entitlement, :catalog_plan, catalog_plan: other_catalog_plan, feature: api) }

    before { create(:entitlement_value, entitlement: other_entitlement, privilege: api_calls, value: "100") }

    it "leaves them untouched" do
      expect(result.removed_entitlements).to eq([])
      expect(entitlements_of(other_catalog_plan)).to eq({"api" => {"calls" => "100"}})
    end
  end
end
