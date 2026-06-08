# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::FixedChargeSerializer do
  subject(:result) { JSON.parse(serializer.to_json) }

  let(:serializer) { described_class.new(fixed_charge, root_name: "fixed_charge", includes: %i[taxes]) }
  let(:fixed_charge) { create(:fixed_charge, properties:) }
  let(:properties) { {"amount" => "1000"} }

  it "serializes the object" do
    expect(result["fixed_charge"]["lago_id"]).to eq(fixed_charge.id)
    expect(result["fixed_charge"]["lago_add_on_id"]).to eq(fixed_charge.add_on_id)
    expect(result["fixed_charge"]["code"]).to eq(fixed_charge.code)
    expect(result["fixed_charge"]["invoice_display_name"]).to eq(fixed_charge.invoice_display_name)
    expect(result["fixed_charge"]["add_on_code"]).to eq(fixed_charge.add_on.code)
    expect(result["fixed_charge"]["created_at"]).to eq(fixed_charge.created_at.iso8601)
    expect(result["fixed_charge"]["charge_model"]).to eq(fixed_charge.charge_model)
    expect(result["fixed_charge"]["pay_in_advance"]).to eq(fixed_charge.pay_in_advance)
    expect(result["fixed_charge"]["prorated"]).to eq(fixed_charge.prorated)
    expect(result["fixed_charge"]["properties"]).to eq(fixed_charge.properties)
    expect(result["fixed_charge"]["taxes"]).to eq([])
    expect(result["fixed_charge"]["units"]).to eq(fixed_charge.units.to_s)
    expect(result["fixed_charge"]["lago_parent_id"]).to eq(fixed_charge.parent_id)
  end

  context "when fixed charge has taxes" do
    let(:fixed_charge) { create(:fixed_charge, :with_applied_taxes, properties:, taxes:) }
    let(:taxes) { create_pair(:tax) }

    it "serializes the object" do
      expect(result["fixed_charge"]["taxes"].map { |tax| tax["lago_id"] }).to match_array(taxes.map(&:id))
    end
  end

  context "when a subscription option is provided" do
    let(:serializer) { described_class.new(fixed_charge, root_name: "fixed_charge", subscription:) }
    let(:fixed_charge) { create(:fixed_charge, units: 10, properties:) }
    let(:plan) { fixed_charge.plan }
    let(:customer) { create(:customer, organization: plan.organization) }
    let(:subscription) { create(:subscription, plan:, customer:) }

    context "when there is no per-subscription units override" do
      it "serializes the plan-level units" do
        expect(result["fixed_charge"]["units"]).to eq("10.0")
      end
    end

    context "when a per-subscription units override exists" do
      before do
        create(:subscription_fixed_charge_units_override,
          subscription:,
          fixed_charge:,
          organization: plan.organization,
          units: 25)
      end

      it "serializes the overridden units" do
        expect(result["fixed_charge"]["units"]).to eq("25.0")
      end
    end
  end
end
