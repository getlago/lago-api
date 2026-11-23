# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractLookup, type: :request do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, external_id: "shared-id", code: "renewal") }
  let(:sibling) { create(:contract, organization:, customer:, external_id: contract.external_id, code: "initial") }
  let(:rate_card) { create(:rate_card, organization:, code: "seats") }
  let(:new_rate_card) { create(:rate_card, organization:, code: "additional") }
  let(:applied_card) { create(:contract_rate_card, organization:, contract:, rate_card:, units: 10) }
  let(:sibling_card) { create(:contract_rate_card, organization:, contract: sibling, rate_card:, units: 5) }

  before do
    [applied_card, sibling_card].compact.each do |card|
      create(:rate_phase, :contract_level, organization:, contract_rate_card: card, code: "intro", position: 1, billing_interval_cycle_count: 1)
      create(:rate_phase, :contract_level, organization:, contract_rate_card: card, code: "default", position: 2)
    end
    new_rate_card
  end

  [
    [:get, "", {}],
    [:put, "", {contract: {name: "Renamed"}}],
    [:patch, "", {contract: {name: "Renamed"}}],
    [:delete, "", {}],
    [:get, "/current_usage", {}],
    [:get, "/applied_rate_cards", {}],
    [:post, "/applied_rate_cards", {applied_rate_card: {rate_card_code: "additional", units: "10"}}],
    [:get, "/applied_rate_cards/seats", {}],
    [:put, "/applied_rate_cards/seats", {applied_rate_card: {units: "20"}}],
    [:patch, "/applied_rate_cards/seats", {applied_rate_card: {units: "20"}}],
    [:delete, "/applied_rate_cards/seats", {}],
    [:get, "/applied_rate_cards/seats/rate_phases", {}],
    [:post, "/applied_rate_cards/seats/rate_phases", {rate_phase: {code: "ramp", position: 1, billing_interval_cycle_count: 2}}],
    [:put, "/applied_rate_cards/seats/rate_phases/intro", {rate_phase: {name: "Renamed"}}],
    [:patch, "/applied_rate_cards/seats/rate_phases/intro", {rate_phase: {name: "Renamed"}}],
    [:delete, "/applied_rate_cards/seats/rate_phases/intro", {}]
  ].each do |method, suffix, body|
    describe "#{method.upcase} /api/v2/contracts/:external_id#{suffix}" do
      subject(:request) { public_send(:"#{method}_with_token", organization, path, body) }

      let(:path) { "/api/v2/contracts/#{contract.external_id}#{suffix}?#{query.to_query}" }
      let(:query) { {contract_code: contract.code} }

      it "targets the specified contract without modifying its sibling" do
        expect { request }.not_to change {
          [sibling.reload.attributes, sibling_card.reload.attributes,
            sibling_card.terms.order(:id).map(&:attributes), sibling_card.rate_phases.order(:position).map(&:attributes)]
        }

        expect(response).to have_http_status(:success)
      end

      context "without contract_code" do
        let(:query) { {} }

        it "requires a code instead of choosing a contract by status" do
          request

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}])
          expect(contract.reload.status).to eq("pending")
          expect(sibling.reload.status).to eq("active")
          expect(applied_card.reload.terms.sole.units).to eq(10)
          expect(applied_card.rate_phases.pluck(:code)).to match_array(%w[intro default])
        end
      end

      context "when only one contract exists for the external id" do
        let(:sibling_card) { nil }
        let(:query) { {} }

        it "allows omitting contract_code" do
          request

          expect(response).to have_http_status(:success)
        end
      end

      context "with status but no contract_code" do
        let(:query) { {status: "pending"} }

        it "does not use status to disambiguate the external id" do
          request

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:details]).to eq([{code: "value_is_mandatory", field: "contract_code", meta: {}}])
        end
      end

      context "when the code belongs to another external id" do
        let(:other) { create(:contract, organization:, customer:, external_id: "other-id", code: "other") }
        let(:query) { {contract_code: other.code} }

        it "returns a not found error" do
          request

          expect(response).to have_http_status(:not_found)
        end
      end

      context "when the code belongs to another organization" do
        let(:foreign) { create(:contract, external_id: contract.external_id, code: "foreign") }
        let(:query) { {contract_code: foreign.code} }

        it "does not access the foreign contract" do
          request

          expect(response).to have_http_status(:not_found)
          expect(foreign.reload.status).to eq("active")
        end
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id" do
    subject(:request) { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", query) }

    let(:query) { {contract_code: contract.code} }

    context "when a historical contract shares the external id" do
      let(:sibling) { create(:contract, :terminated, organization:, customer:, external_id: contract.external_id) }
      let(:query) { {} }

      it "requires contract_code even when only one contract is live" do
        request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "value_is_mandatory", field: "contract_code", meta: {}}])
      end
    end

    context "when every matching contract is historical" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "shared-id") }
      let(:sibling) { create(:contract, :canceled, organization:, customer:, external_id: contract.external_id) }
      let(:query) { {} }

      it "requires a code instead of picking the latest record" do
        request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "value_is_mandatory", field: "contract_code", meta: {}}])
      end
    end

    ["", [], {nested: "value"}].each do |invalid_code|
      context "with contract_code=#{invalid_code.inspect}" do
        let(:query) { {contract_code: invalid_code} }

        it "returns a validation error" do
          request

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:details]).to eq([{code: "value_is_invalid", field: "contract_code", meta: {}}])
        end
      end
    end
  end
end
