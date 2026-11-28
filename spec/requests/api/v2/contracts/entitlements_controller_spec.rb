# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Contracts::EntitlementsController do
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let_it_be(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: "Users") }
  let_it_be(:privilege) { create(:privilege, organization:, feature:, code: "max", name: "Max", value_type: "integer", created_at: 3.days.ago) }
  let_it_be(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:, created_at: 3.days.ago) }

  let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract-1") }

  before_all { create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: 50) }

  # An entitlement of the contract, in the v2 contract entitlement shape.
  def contract_entitlement_render(feature_code:, source:, values:, owner: contract)
    {lago_contract_id: owner.id, feature_code:, source:, values:}
  end

  # The seats entitlement of the contract, in the v2 contract entitlement shape.
  def seats(value:, source:, owner: contract)
    contract_entitlement_render(feature_code: "seats", source: "plan", values: [{privilege_code: "max", value:, plan_value: 50, source:}], owner:)
  end

  describe "GET /api/v2/contracts/:external_id/entitlements", :bullet do
    subject(:request) { get_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements", params) }

    let(:external_id) { contract.external_id }
    let(:params) { {} }

    include_examples "requires API permission", "contract", "read"

    it "returns the entitlements of the catalog plan" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(entitlements: [seats(value: 50, source: "plan")])
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
        expect(json).to eq(entitlements: [seats(value: 80, source: "contract")])
      end
    end

    context "with a feature that only the contract grants and several privileges" do
      before do
        newer_privilege = create(:privilege, organization:, feature:, code: "admins", name: "Admins", value_type: "integer", created_at: 1.day.ago)
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: newer_privilege, value: 3)
        storage = create(:feature, organization:, code: "storage", name: "Storage", description: nil)
        limit = create(:privilege, organization:, feature: storage, code: "limit", name: "Limit", value_type: "integer")
        contract_entitlement = create(:entitlement, :contract, organization:, contract:, feature: storage, created_at: 1.day.ago)
        create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: limit, value: 10)
      end

      it "lists the newest entitlement first, and the newest privilege first" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:entitlements].map { it[:feature_code] }).to eq(%w[storage seats])
        expect(json[:entitlements].last[:values].map { it[:privilege_code] }).to eq(%w[admins max])
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
                lago_contract_id: contract.id,
                feature_code: "seats",
                source: "contract",
                values: [{privilege_code: "max", value: 80, plan_value: nil, source: "contract"}]
              }
            ]
          )
        end
      end
    end

    context "with contracts sharing the external id" do
      let(:pending_contract) do
        create(:contract, :pending, organization:, customer:, catalog_plan: nil, external_id: "contract-1", code: "renewal")
      end

      before { pending_contract }

      it "returns a value_is_mandatory error on the contract code" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}]
        )
      end

      context "with the code of one of them" do
        let(:params) { {contract_code: "renewal"} }

        it "reads that one" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(entitlements: [])
        end
      end

      context "with an unknown code" do
        let(:params) { {contract_code: "unknown"} }

        it "returns not found" do
          request

          expect(response).to be_v2_not_found_error("contract")
        end
      end
    end

    context "with an override written with PATCH" do
      before do
        patch_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements", {entitlements: {seats: {max: 60}}})
      end

      it "returns it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 60, source: "contract")])
      end
    end

    context "with an external id containing a dot" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract.1") }

      it "finds the contract" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 50, source: "plan")])
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

    %w[page per_page limit after].each do |name|
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

  describe "PATCH /api/v2/contracts/:external_id/entitlements" do
    subject(:request) do
      patch_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements#{query}", request_params)
    end

    let(:external_id) { contract.external_id }
    let(:query) { "" }
    let(:request_params) { {entitlements: {seats: {max: 60}}} }

    shared_examples "a refused write" do |status, body|
      it "refuses the write" do
        request

        expect(response).to have_http_status(status)
        expect(json).to eq(body)
        expect(Entitlement::Entitlement.where(contract_id: contract.id)).to be_empty
      end
    end

    include_examples "requires API permission", "contract", "write"

    it "merges the value as an override and returns every entitlement" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(entitlements: [seats(value: 60, source: "contract")])
      expect(plan_entitlement.values.reload.map(&:value)).to eq(["50"])
    end

    context "with a pagination parameter" do
      let(:query) { "?limit=1" }

      it "returns a not_paginated error and writes nothing" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: "limit", meta: {}}])
        expect(Entitlement::Entitlement.where(contract_id: contract.id)).to be_empty
      end
    end

    context "with a feature that only the contract grants" do
      let(:request_params) { {entitlements: {sso: {domains: "lago.com"}}} }

      before do
        sso = create(:feature, organization:, code: "sso", name: "SSO", description: nil)
        create(:privilege, organization:, feature: sso, code: "domains", name: nil, value_type: "string")
      end

      it "adds it before the older catalog plan entitlements" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          entitlements: [
            {
              lago_contract_id: contract.id,
              feature_code: "sso",
              source: "contract",
              values: [{privilege_code: "domains", value: "lago.com", plan_value: nil, source: "contract"}]
            },
            seats(value: 50, source: "plan")
          ]
        )
      end
    end

    context "with an empty map" do
      let(:request_params) { {entitlements: {}} }

      it "changes nothing" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 50, source: "plan")])
      end
    end

    context "with a pending and an active contract sharing the external id" do
      let(:pending_contract) do
        create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: "contract-1", code: "renewal")
      end

      before { pending_contract }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}]}

      context "with the code of the pending one" do
        let(:query) { "?contract_code=renewal" }

        it "writes on the pending one" do
          request

          expect(response).to have_http_status(:success)
          expect(pending_contract.entitlements.count).to eq(1)
          expect(contract.entitlements).to be_empty
        end
      end

      context "with an unknown code" do
        let(:query) { "?contract_code=unknown" }

        it "returns a not found error" do
          request

          expect(response).to be_v2_not_found_error("contract")
        end
      end
    end

    context "with a terminated contract" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:, external_id: "contract-1") }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "contract_not_editable", field: "base", meta: {}}]}
    end

    context "with an external id containing a dot" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract.1") }

      it "finds the contract" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [seats(value: 60, source: "contract")])
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
      let(:other_organization) { create(:organization) }
      let(:contract) { create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization)) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("contract")
        expect(contract.entitlements).to be_empty
      end
    end

    context "without entitlements" do
      let(:request_params) { {} }

      include_examples "a refused write", :bad_request,
        {code: "missing_parameter", details: [{code: "missing", field: "entitlements", meta: {}}]}
    end

    context "with an invalid value" do
      let(:request_params) { {entitlements: {seats: {max: "many"}}} }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}]}
    end

    context "with a null feature value" do
      let(:request_params) { {entitlements: {seats: nil}} }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}]}
    end

    context "with a blank feature value" do
      let(:request_params) { {entitlements: {seats: ""}} }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}]}
    end

    context "with an unknown privilege" do
      let(:request_params) { {entitlements: {seats: {max: 60, unknown: 1}}} }

      include_examples "a refused write", :unprocessable_content,
        {code: "validation_errors", details: [{code: "resource_not_found", field: "entitlements.seats.unknown", meta: {resource: "privilege"}}]}
    end

    context "with a select value outside the options" do
      let(:request_params) { {entitlements: {seats: {invitation: "fax"}}} }

      before { create(:privilege, organization:, feature:, code: "invitation", name: nil, value_type: "select", config: {select_options: %w[email phone]}) }

      include_examples "a refused write", :unprocessable_content,
        {
          code: "validation_errors",
          details: [{code: "value_not_in_select_options", field: "entitlements.seats.invitation", meta: {allowed_values: %w[email phone]}}]
        }
    end

    context "without the product catalog", product_catalog: false do
      include_examples "a refused write", :forbidden, {code: "feature_unavailable", details: []}
    end
  end

  describe "DELETE /api/v2/contracts/:external_id/entitlements/:code" do
    subject(:request) { delete_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements/#{code}#{query}") }

    let(:external_id) { contract.external_id }
    let(:code) { "seats" }
    let(:query) { "" }
    let(:sso) { create(:privilege, organization:, feature:, code: "sso", name: "SSO", value_type: "boolean", created_at: 2.days.ago) }
    let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }
    let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: 80) }
    let(:privilege_removal) { create(:subscription_feature_removal, :contract, organization:, contract:, privilege: sso) }
    let(:not_found_feature) do
      {code: "resource_not_found", details: [{code: "resource_not_found", field: "base", meta: {resource: "feature"}}]}
    end

    before do
      create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: true)
      contract_value
      privilege_removal
    end

    shared_examples "a refused removal" do |status, body|
      it "refuses the removal" do
        request

        expect(response).to have_http_status(status)
        expect(json).to eq(body || not_found_feature)
        expect(contract.entitlement_removals.reload).to eq([privilege_removal])
        expect(contract_entitlement.reload).not_to be_discarded
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    include_examples "requires API permission", "contract", "write"

    it "removes the feature and returns it as it applied before the removal" do
      request

      # sso is removed from the contract, so only max applies, with the contract value.
      expect(response).to have_http_status(:success)
      expect(json).to eq(entitlement: seats(value: 80, source: "contract"))
      expect(contract_entitlement.reload).to be_discarded
      expect(contract_value.reload).to be_discarded
      expect(privilege_removal.reload).to be_discarded
      expect(contract.entitlement_removals.reload.map(&:entitlement_feature_id)).to eq([feature.id])
      expect(plan_entitlement.reload).not_to be_discarded
      expect(Entitlement::SubscriptionEntitlement.for_contract(contract)).to be_empty
    end

    it "sends no event without the entitlement_events feature flag" do
      request

      expect(response).to have_http_status(:success)
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
    end

    context "with the entitlement_events feature flag" do
      before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

      it "sends one contract_entitlement.deleted webhook and activity log with the entitlement before the removal" do
        render = seats(value: 80, source: "contract")

        expect { request }.to have_enqueued_job_after_commit(SendWebhookJob)
          .with("contract_entitlement.deleted", contract, {contract_entitlement: render})

        expect(SendWebhookJob).to have_been_enqueued.once
        expect(Utils::ActivityLog).to have_received(:produce).with(
          contract, "contract_entitlement.deleted", after_commit: true,
          activity_object: render,
          changes: {"values" => [render[:values], nil]}
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args).once
      end
    end

    context "when a PATCH grants the feature again" do
      it "lists it again" do
        request
        patch_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements", {entitlements: {seats: {max: 60}}})

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          entitlements: [
            contract_entitlement_render(
              feature_code: "seats",
              source: "plan",
              values: [
                {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
                {privilege_code: "max", value: 60, plan_value: 50, source: "contract"}
              ]
            )
          ]
        )
        expect(contract.entitlement_removals.reload).to be_empty
      end
    end

    context "with a feature that only the contract grants" do
      let(:storage) { create(:feature, organization:, code: "storage") }
      let(:limit) { create(:privilege, organization:, feature: storage, code: "limit", value_type: "integer") }
      let(:storage_entitlement) { create(:entitlement, :contract, organization:, contract:, feature: storage) }
      let(:code) { "storage" }

      before { create(:entitlement_value, organization:, entitlement: storage_entitlement, privilege: limit, value: 10) }

      it "discards it and stores no removal" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          entitlement: contract_entitlement_render(
            feature_code: "storage",
            source: "contract",
            values: [{privilege_code: "limit", value: 10, plan_value: nil, source: "contract"}]
          )
        )
        expect(storage_entitlement.reload).to be_discarded
        expect(contract.entitlement_removals.reload).to eq([privilege_removal])
        expect(Entitlement::SubscriptionEntitlement.for_contract(contract).map(&:code)).to eq(["seats"])
      end
    end

    context "with an unknown feature" do
      let(:code) { "unknown" }

      include_examples "a refused removal", :not_found
    end

    context "with a feature that does not apply to the contract" do
      let(:code) { "storage" }

      before { create(:feature, organization:, code: "storage") }

      include_examples "a refused removal", :not_found
    end

    context "with a feature of another organization" do
      let(:code) { "storage" }

      before { create(:feature, organization: create(:organization), code: "storage") }

      include_examples "a refused removal", :not_found
    end

    context "with a feature already removed" do
      before { delete_with_token(organization, "/api/v2/contracts/#{external_id}/entitlements/seats") }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
        expect(contract.entitlement_removals.reload.map(&:entitlement_feature_id)).to eq([feature.id])
      end
    end

    context "with a feature code containing a dot" do
      let(:code) { "storage.v2" }

      before { create(:entitlement, :contract, organization:, contract:, feature: create(:feature, organization:, code: "storage.v2")) }

      it "removes it" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:entitlement]).to include(feature_code: "storage.v2", source: "contract")
      end
    end

    context "with a pending and an active contract sharing the external id" do
      let(:pending_contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: "contract-1", code: "renewal") }

      before { pending_contract }

      include_examples "a refused removal", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}]}

      context "with the code of the pending one" do
        let(:query) { "?contract_code=renewal" }

        it "removes it from the pending one" do
          request

          # Nothing was removed from the pending contract: sso, the newer privilege, comes first.
          expect(response).to have_http_status(:success)
          expect(json).to eq(
            entitlement: contract_entitlement_render(
              feature_code: "seats",
              source: "plan",
              owner: pending_contract,
              values: [
                {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
                {privilege_code: "max", value: 50, plan_value: 50, source: "plan"}
              ]
            )
          )
          expect(pending_contract.entitlement_removals.map(&:entitlement_feature_id)).to eq([feature.id])
          expect(contract.entitlement_removals.reload).to eq([privilege_removal])
          expect(contract_entitlement.reload).not_to be_discarded
        end
      end

      context "with the code of the active one" do
        let(:query) { "?contract_code=#{contract.code}" }

        it "removes it from the active one" do
          request

          expect(response).to have_http_status(:success)
          expect(contract_entitlement.reload).to be_discarded
          expect(pending_contract.entitlement_removals).to be_empty
        end
      end
    end

    context "with a terminated contract" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:, external_id: "contract-1") }

      include_examples "a refused removal", :unprocessable_content,
        {code: "validation_errors", details: [{code: "contract_not_editable", field: "base", meta: {}}]}
    end

    context "with an unknown external id" do
      let(:external_id) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    context "with a contract of another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_contract) { create(:contract, organization: other_organization, customer: other_customer) }
      let(:external_id) { other_contract.external_id }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("contract")
        expect(other_contract.entitlement_removals).to be_empty
      end
    end

    context "with a pagination parameter" do
      let(:query) { "?page=1" }

      include_examples "a refused removal", :bad_request,
        {code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: "page", meta: {}}]}
    end

    context "with an expansion" do
      let(:query) { "?expands[]=contract" }

      include_examples "a refused removal", :bad_request,
        {code: "expand_not_supported", details: [{code: "not_expandable", field: "expands", meta: {invalid_values: ["contract"]}}]}
    end

    context "without the product catalog", product_catalog: false do
      include_examples "a refused removal", :forbidden, {code: "feature_unavailable", details: []}
    end
  end
end
