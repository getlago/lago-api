# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyEntitlementsService do
  subject(:result) { described_class.call(migration:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:pro) { create(:plan, organization:, code: "pro") }
  let_it_be(:basic) { create(:plan, organization:, code: "basic") }
  let_it_be(:pro_catalog_plan) { create(:catalog_plan, organization: shadow_organization, code: "pro_v2") }
  let_it_be(:seats) { create(:feature, organization:, code: "seats") }
  let_it_be(:seats_max) { create(:privilege, feature: seats, code: "max", value_type: "integer") }
  let_it_be(:sso) { create(:feature, organization:, code: "sso") }

  let(:status) { "shadowing" }
  let(:plan_mapping) { {"pro" => "pro_v2", "basic" => "basic_v2", "gone" => "gone_v2"} }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping:) }

  before_all do
    create(:entitlement_value, entitlement: create(:entitlement, plan: pro, feature: seats), privilege: seats_max, value: "10")
    create(:entitlement, plan: pro, feature: sso)

    override = create(:plan, organization:, code: "pro", parent: pro)
    create(:entitlement_value, entitlement: create(:entitlement, plan: override, feature: seats), privilege: seats_max, value: "99")
  end

  def entitlements_of(owner_scope)
    Entitlement::Entitlement.where(owner_scope).includes(:feature, values: :privilege).to_h do |entitlement|
      [entitlement.feature.code, entitlement.values.to_h { [it.privilege.code, it.value] }]
    end
  end

  it "copies the features, then the entitlements of each mapped plan to its catalog plan" do
    expect(result).to be_success
    expect(result.created_features).to eq(%w[seats sso])
    expect(result.created_privileges).to eq(%w[seats.max])
    expect(result.catalog_plans.keys).to eq(%w[pro_v2])
    expect(result.catalog_plans["pro_v2"].created_entitlements).to eq(%w[seats sso])

    expect(entitlements_of(catalog_plan_id: pro_catalog_plan.id)).to eq(entitlements_of(plan_id: pro.id))
    expect(entitlements_of(catalog_plan_id: pro_catalog_plan.id)).to eq({"seats" => {"max" => "10"}, "sso" => {}})
  end

  it "reports the mappings whose plan or catalog plan is missing instead of failing" do
    expect(result).to be_success
    expect(result.missing_plan_codes).to eq(%w[gone])
    expect(result.missing_catalog_plan_codes).to eq(%w[basic_v2 gone_v2])
    expect(result.conflicting_catalog_plan_codes).to eq([])
  end

  it "creates nothing on a second run" do
    described_class.call(migration:)

    expect { result }
      .to not_change { Entitlement::Feature.unscoped.count }
      .and not_change { Entitlement::Entitlement.unscoped.count }
      .and not_change { Entitlement::EntitlementValue.unscoped.count }

    expect(result.created_features).to eq([])
    expect(result.catalog_plans["pro_v2"].created_entitlements).to eq([])
    expect(result.catalog_plans["pro_v2"].created_values).to eq([])
  end

  context "when two plans are mapped to the same catalog plan" do
    let(:plan_mapping) { {"pro" => "pro_v2", "basic" => "pro_v2"} }

    context "with different entitlements" do
      it "skips the catalog plan and reports it" do
        expect(result).to be_success
        expect(result.catalog_plans).to eq({})
        expect(result.conflicting_catalog_plan_codes).to eq(%w[pro_v2])
        expect(entitlements_of(catalog_plan_id: pro_catalog_plan.id)).to eq({})
      end
    end

    context "with the same entitlements" do
      before do
        create(:entitlement_value, entitlement: create(:entitlement, plan: basic, feature: seats), privilege: seats_max, value: "10")
        create(:entitlement, plan: basic, feature: sso)
      end

      it "copies them once" do
        expect(result.catalog_plans.keys).to eq(%w[pro_v2])
        expect(result.conflicting_catalog_plan_codes).to eq([])
        expect(entitlements_of(catalog_plan_id: pro_catalog_plan.id)).to eq({"seats" => {"max" => "10"}, "sso" => {}})
      end
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "fails without copying anything" do
      expect { result }.not_to change { Entitlement::Feature.unscoped.count }

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("migration_not_shadowing")
    end
  end

  context "when a shadow privilege has another value type" do
    before do
      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      create(:privilege, feature: shadow_seats, code: "max", value_type: "string")
    end

    it "fails without copying any entitlement" do
      expect { result }.not_to change { Entitlement::Entitlement.unscoped.count }

      expect(result).to be_failure
      expect(result.error.messages).to eq({"seats.max": ["value_type_mismatch"]})
    end
  end
end
