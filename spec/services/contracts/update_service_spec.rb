# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::UpdateService do
  subject(:result) { described_class.call(contract:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:params) { {name: "Renamed", billing_time: "anniversary"} }

  it "updates the editable authoring fields" do
    expect(result).to be_success
    expect(contract.reload).to have_attributes(name: "Renamed", billing_time: "anniversary")
  end

  it "sets the window dates in the customer timezone" do
    result = described_class.call(contract:, params: {started_at: "2026-11-01T00:00:00", ended_at: "2026-12-01T00:00:00"})

    expect(result).to be_success
    expect(contract.reload.started_at).to eq(Time.zone.parse("2026-11-01T00:00:00"))
    expect(contract.ended_at).to eq(Time.zone.parse("2026-12-01T00:00:00"))
  end

  context "when the contract is active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:params) do
      {
        name: "Renamed",
        purchase_order_number: "PO-42",
        ended_at: "2027-01-01T00:00:00Z",
        billing_entity_id: billing_entity.id,
        consolidate_invoice: false,
        payment_method: {payment_method_type: "manual"}
      }
    end

    around { |example| travel_to(Time.zone.parse("2026-10-01T00:00:00Z")) { example.run } }

    it "updates the fields that stay editable" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(
        name: "Renamed",
        purchase_order_number: "PO-42",
        billing_entity:,
        consolidate_invoice: false
      )
      expect(contract).to be_payment_method_type_manual
      expect(contract.ended_at).to eq(Time.zone.parse("2027-01-01T00:00:00Z"))
    end

    context "when the form resends the locked fields unchanged" do
      let(:started_at) { Time.zone.parse("2026-09-01T03:30:00.123456Z") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
      let(:params) do
        {
          name: "Renamed",
          plan_code: catalog_plan.code,
          billing_time: "calendar",
          started_at: "2026-09-01T03:30:00Z",
          billing_anchor_date: contract.effective_billing_anchor_date.iso8601
        }
      end

      it "accepts the edit without writing the locked fields back" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(name: "Renamed", started_at:, billing_anchor_date: nil)
      end
    end

    context "without a plan" do
      let(:catalog_plan) { nil }

      [nil, ""].each do |plan_code|
        context "with #{plan_code.inspect} as the plan code" do
          let(:params) { {name: "Renamed", plan_code:} }

          it "accepts the edit" do
            expect(result).to be_success
            expect(contract.reload.name).to eq("Renamed")
          end
        end
      end
    end

    context "when the form resends the code of the plan it has since discarded" do
      let(:params) { {name: "Renamed", plan_code: catalog_plan.code} }

      before { catalog_plan.discard! }

      it "accepts the edit" do
        expect(result).to be_success
        expect(contract.reload.name).to eq("Renamed")
      end
    end

    describe "end date" do
      let(:ended_at) { Time.zone.parse("2027-01-01T00:00:00Z") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, ended_at:) }

      context "when bringing it forward" do
        let(:params) { {ended_at: "2026-12-01T00:00:00Z"} }

        it "updates it" do
          expect(result).to be_success
          expect(contract.reload.ended_at).to eq(Time.zone.parse("2026-12-01T00:00:00Z"))
        end
      end

      context "when resending it unchanged" do
        let(:params) { {name: "Renamed", ended_at: "2027-01-01T00:00:00Z"} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end

      context "when resending one that has already passed" do
        let(:ended_at) { Time.zone.parse("2026-09-30T00:00:00Z") }
        let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-09-01T00:00:00Z"), ended_at:) }
        let(:params) { {name: "Renamed", ended_at: "2026-09-30T00:00:00Z"} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end

      context "when setting one that has already passed" do
        let(:params) { {ended_at: "2026-09-15T00:00:00Z"} }

        it "rejects it" do
          expect(result).not_to be_success
          expect(result.error.messages[:ended_at]).to eq(["already_ended"])
          expect(contract.reload.ended_at).to eq(ended_at)
        end
      end

      context "when moving it later" do
        let(:params) { {ended_at: "2027-02-01T00:00:00Z"} }

        it "rejects it" do
          expect(result).not_to be_success
          expect(result.error.messages[:ended_at]).to eq(["cannot_be_extended"])
          expect(contract.reload.ended_at).to eq(ended_at)
        end
      end

      context "when clearing it" do
        let(:params) { {ended_at: nil} }

        it "rejects it" do
          expect(result).not_to be_success
          expect(result.error.messages[:ended_at]).to eq(["cannot_be_extended"])
          expect(contract.reload.ended_at).to eq(ended_at)
        end
      end
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:params) { {name: "Renamed", plan_code: other_plan.code} }

      it "rejects the edit as locked and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages[:contract]).to eq(["contract_locked"])
        expect(contract.reload).to have_attributes(name: nil, catalog_plan:)
      end
    end

    {
      billing_time: "anniversary",
      billing_anchor_date: "2026-03-01",
      started_at: "2026-03-01T00:00:00Z"
    }.each do |field, value|
      context "when changing #{field}" do
        let(:params) { {name: "Renamed"}.merge(field => value) }

        it "rejects the edit as locked and changes nothing" do
          expect(result).not_to be_success
          expect(result.error.messages[:contract]).to eq(["contract_locked"])
          expect(contract.reload.name).to be_nil
        end
      end
    end
  end

  %i[terminated canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }
      let(:params) { {name: "Renamed"} }

      it "rejects any edit as locked" do
        expect(result).not_to be_success
        expect(result.error.messages[:contract]).to eq(["contract_locked"])
        expect(contract.reload.name).to be_nil
      end
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when changing the plan" do
    let(:new_rate_card) { create(:rate_card, organization:) }
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:params) { {plan_code: other_plan.code} }
    let(:old_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:)) }
    let(:old_phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card: old_card) }

    let(:new_plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: new_rate_card, units: 3) }

    before do
      old_phase
      create(:rate_phase, organization:, plan_rate_card: new_plan_rate_card, code: "intro", position: 1)
    end

    it "re-materializes the rate cards from the new plan with their phases" do
      expect(result).to be_success
      expect(contract.reload.catalog_plan).to eq(other_plan)
      card = contract.applied_rate_cards.sole
      expect(card).to have_attributes(rate_card: new_rate_card, units: 3)
      expect(card.rate_phases.map(&:code)).to eq(["intro"])
    end

    it "discards the replaced cards along with their phases" do
      result

      expect(old_card.reload).to be_discarded
      expect(old_phase.reload).to be_discarded
    end
  end

  context "when resending the current plan code" do
    let(:params) { {name: "Renamed", plan_code: catalog_plan.code} }

    it "accepts the edit" do
      expect(result).to be_success
      expect(contract.reload.name).to eq("Renamed")
    end
  end

  context "without a plan" do
    let(:catalog_plan) { nil }

    [nil, ""].each do |plan_code|
      context "with #{plan_code.inspect} as the plan code" do
        let(:params) { {name: "Renamed", plan_code:} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end
    end
  end

  context "when the plan code is unknown" do
    let(:params) { {plan_code: "unknown"} }

    it "returns a not found plan failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "with a malformed date" do
    let(:params) { {started_at: "not-a-date"} }

    it "rejects the value" do
      expect(result).not_to be_success
      expect(result.error.messages[:started_at]).to eq(["value_is_invalid"])
    end
  end

  context "with a boolean date value" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, ended_at: 1.month.from_now) }
    let(:params) { {ended_at: false} }

    it "rejects it instead of silently clearing the end date" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["value_is_invalid"])
      expect(contract.reload.ended_at).to be_present
    end
  end

  context "when clearing a date with an explicit null" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, ended_at: 1.month.from_now) }
    let(:params) { {ended_at: nil} }

    it "clears the end date" do
      expect(result).to be_success
      expect(contract.reload.ended_at).to be_nil
    end
  end

  context "when the end date is already in the past" do
    let(:params) { {ended_at: 1.day.ago.iso8601} }

    it "rejects the ended_at" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["already_ended"])
    end
  end

  context "with billing, invoicing and payment settings" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:payment_method) { create(:payment_method, customer:) }
    let(:params) do
      {
        billing_entity_id: billing_entity.id,
        consolidate_invoice: false,
        purchase_order_number: "PO-42",
        payment_method: {payment_method_id: payment_method.id, payment_method_type: "provider"}
      }
    end

    it "updates the settings" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(
        billing_entity:,
        consolidate_invoice: false,
        purchase_order_number: "PO-42",
        payment_method:,
        payment_method_type: "provider"
      )
    end

    context "when a manual type is paired with a concrete payment method" do
      let(:params) { {payment_method: {payment_method_id: payment_method.id, payment_method_type: "manual"}} }

      it "rejects the contradictory combination" do
        expect(result).not_to be_success
        expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
      end
    end

    context "when the billing entity id is unknown" do
      let(:params) { {billing_entity_id: "00000000-0000-0000-0000-000000000000"} }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("billing_entity")
      end
    end

    context "when the payment method belongs to another customer" do
      let(:other_payment_method) { create(:payment_method, customer: create(:customer, organization:)) }
      let(:params) { {payment_method: {payment_method_id: other_payment_method.id}} }

      it "returns a not found failure, scoped to the contract's customer" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("payment_method")
      end
    end

    context "when consolidate_invoice is omitted" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, consolidate_invoice: false) }
      let(:params) { {name: "Renamed"} }

      it "leaves the stored value unchanged" do
        expect(result).to be_success
        expect(contract.reload.consolidate_invoice).to be(false)
      end
    end

    context "when payment_method_type is omitted" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, payment_method_type: "manual") }
      let(:params) { {name: "Renamed"} }

      it "leaves the stored payment_method_type unchanged" do
        expect(result).to be_success
        expect(contract.reload.payment_method_type).to eq("manual")
      end
    end

    context "when clearing the override fields with an explicit null" do
      let(:contract) do
        create(:contract, :pending, organization:, customer:, catalog_plan:,
          billing_entity:, purchase_order_number: "PO-1")
      end
      let(:params) { {billing_entity_id: nil, purchase_order_number: nil} }

      it "clears the billing entity override and the purchase order number" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(billing_entity: nil, purchase_order_number: nil)
      end
    end
  end
end
