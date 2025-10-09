# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Subscriptions::FixedChargesController, type: :request do
  let(:external_id) { "sub+1" }
  let(:external_id_query_param) { external_id }
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, external_id:, customer: create(:customer, organization:)) }
  let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan, organization:) }
  let(:deleted_fixed_charge) { create(:fixed_charge, :deleted, plan: subscription.plan, organization:) }

  before do
    subscription
    fixed_charge
    deleted_fixed_charge
  end

  describe "GET /api/v1/subscriptions/:external_id/fixed_charges" do
    subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/fixed_charges") }

    it_behaves_like "requires API permission", "subscription", "read"

    context "when there are fixed charges" do
      it "retrieves the list of fixed charges" do
        subject
        expect(json[:fixed_charges]).to be_present
        expect(json[:fixed_charges].first).to include({
          lago_id: fixed_charge.id,
          lago_add_on_id: fixed_charge.add_on_id,
          invoice_display_name: fixed_charge.invoice_display_name,
          add_on_code: fixed_charge.add_on.code,
          created_at: fixed_charge.created_at.iso8601,
          charge_model: fixed_charge.charge_model,
          pay_in_advance: fixed_charge.pay_in_advance,
          prorated: fixed_charge.prorated,
          properties: fixed_charge.properties.symbolize_keys,
          units: fixed_charge.units.to_s
        })
      end
    end

    context "when there is only deleted fixed charges" do
      let(:fixed_charge) { nil }

      it do
        subject
        expect(json[:fixed_charges]).to be_empty
      end
    end

    context "when fixed charges have applied taxes" do
      let(:fixed_charge) { create(:fixed_charge, :with_applied_taxes, plan: subscription.plan, organization:) }

      it "includes taxes in the response" do
        subject
        expect(json[:fixed_charges].first).to include(:taxes)
        expect(json[:fixed_charges].first[:taxes]).to be_an(Array)
        expect(json[:fixed_charges].first[:taxes].first).to include(
          lago_id: fixed_charge.applied_taxes.first.tax.id,
          name: fixed_charge.applied_taxes.first.tax.name,
          code: fixed_charge.applied_taxes.first.tax.code,
          rate: fixed_charge.applied_taxes.first.tax.rate
        )
      end
    end

    context "when subscription is not found" do
      let(:external_id_query_param) { "not-found-id" }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("subscription")
      end
    end
  end
end
