# frozen_string_literal: true

require "rails_helper"

# The entitlements render in the v1 subscription shape: no datetime to render to the microsecond.
RSpec.describe Api::V2::Contracts::EntitlementsController, v2_timestamps: false do
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let_it_be(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: "Users") }
  let_it_be(:privilege) { create(:privilege, organization:, feature:, code: "max", name: "Max", value_type: "integer") }
  let_it_be(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }

  let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract-1") }

  before_all { create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: 50) }

  describe "GET /api/v2/contracts/:external_id/entitlements", :bullet do
    subject(:request) { get_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements", params) }

    let(:external_id) { contract.external_id }
    let(:params) { {} }

    def seats(value:, override_value:, overrides:)
      {
        code: "seats",
        name: "Seats",
        description: "Users",
        privileges: [
          {code: "max", name: "Max", value_type: "integer", value:, plan_value: 50, override_value:, config: {}}
        ],
        overrides:
      }
    end

    include_examples "requires API permission", "contract", "read"

    it "returns the entitlements of the catalog plan" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(entitlements: [seats(value: 50, override_value: nil, overrides: {})])
    end

    context "with an override and a removal on the contract" do
      let(:sso) { create(:feature, organization:, code: "sso", name: "SSO", description: nil) }
      let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }

      before do
        create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: 80)
        create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso)
        create(:subscription_feature_removal, :contract, organization:, contract:, feature: sso)
      end

      it "merges them as the subscription read does" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 80, override_value: 80, overrides: {max: 80})])
      end
    end

    context "with a contract without a catalog plan" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan: nil) }

      it "returns an empty list" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [])
      end

      context "when the contract has its own entitlements" do
        let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }

        before { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: 80) }

        it "returns only them" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(
            entitlements: [
              {
                code: "seats",
                name: "Seats",
                description: "Users",
                privileges: [
                  {code: "max", name: "Max", value_type: "integer", value: 80, plan_value: nil, override_value: 80, config: {}}
                ],
                overrides: {max: 80}
              }
            ]
          )
        end
      end
    end

    context "with a pending and an active contract sharing the external id" do
      let(:pending_contract) { create(:contract, :pending, organization:, customer:, catalog_plan: nil, external_id: "contract-1") }

      before { pending_contract }

      it "reads the pending one" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [])
      end

      context "with an empty status" do
        let(:params) { {status: ""} }

        it "reads the pending one" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(entitlements: [])
        end
      end

      context "with the active status" do
        let(:params) { {status: "active"} }

        it "reads the active one" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(entitlements: [seats(value: 50, override_value: nil, overrides: {})])
        end
      end
    end

    context "with a status" do
      let(:params) { {status: "terminated"} }
      let(:older) { create(:contract, :terminated, organization:, customer:, catalog_plan:, external_id: "contract-1", started_at: 2.months.ago) }
      let(:latest) { create(:contract, :terminated, organization:, customer:, catalog_plan: nil, external_id: "contract-1", started_at: 1.month.ago) }

      before do
        older
        latest
      end

      it "reads the latest contract of that status by started_at" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [])
      end

      context "when the latest one has the catalog plan" do
        let(:older) { create(:contract, :terminated, organization:, customer:, catalog_plan: nil, external_id: "contract-1", started_at: 2.months.ago) }
        let(:latest) { create(:contract, :terminated, organization:, customer:, catalog_plan:, external_id: "contract-1", started_at: 1.month.ago) }

        it "reads it" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(entitlements: [seats(value: 50, override_value: nil, overrides: {})])
        end
      end

      context "when no contract has that status" do
        let(:params) { {status: "canceled"} }

        it "returns not found" do
          request

          expect(response).to be_v2_not_found_error("contract")
        end
      end
    end

    context "with an unknown status" do
      let(:params) { {status: "foo"} }

      it "returns a value_is_invalid error with the allowed values" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "value_is_invalid",
          details: [
            {code: "value_is_invalid", field: "status", meta: {allowed_values: %w[pending active terminated canceled]}}
          ]
        )
      end
    end

    context "with an external id containing a dot" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract.1") }

      it "finds the contract" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 50, override_value: nil, overrides: {})])
      end
    end

    context "with an unknown external id" do
      let(:external_id) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    context "with a contract of another organization" do
      let(:contract) { create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization)) }
      let(:other_organization) { create(:organization) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    %w[page per_page].each do |name|
      context "with the #{name} pagination parameter" do
        let(:params) { {name => "1"} }

        it "returns a not_paginated error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}])
        end
      end
    end

    context "without the product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end
end
