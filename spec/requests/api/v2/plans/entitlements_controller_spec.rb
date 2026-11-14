# frozen_string_literal: true

require "rails_helper"

# The entitlements render in the v1 shape: no datetime to render to the microsecond.
RSpec.describe Api::V2::Plans::EntitlementsController, v2_timestamps: false do
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium") }
  let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: nil) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", name: nil, value_type: "integer") }

  describe "POST /api/v2/plans/:plan_code/entitlements" do
    subject(:request) { post_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements#{query}", request_params) }

    let(:plan_code) { catalog_plan.code }
    let(:query) { "" }
    let(:request_params) { {entitlements: {seats: {max: 50}}} }

    before do
      privilege
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
    end

    include_examples "requires API permission", "plan", "write"

    it "replaces the entitlements of the catalog plan" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(
        entitlements: [
          {
            code: "seats",
            name: "Seats",
            description: nil,
            privileges: [{code: "max", name: nil, value_type: "integer", value: 50, config: {}}]
          }
        ]
      )
      expect(catalog_plan.entitlements.sole.values.sole.value).to eq("50")
    end

    it "produces the plan.updated activity log once and no plan.updated webhook" do
      expect { request }.not_to have_enqueued_job(SendWebhookJob)

      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(catalog_plan)
      expect(Utils::ActivityLog).to have_received(:produce).with(catalog_plan, "plan.updated", after_commit: true).once
    end

    context "with an entitlement left out of the body" do
      let(:old_feature) { create(:feature, organization:, code: "sso") }
      let(:old_privilege) { create(:privilege, organization:, feature: old_feature, code: "provider") }
      let(:old_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: old_feature) }
      let(:old_value) { create(:entitlement_value, organization:, entitlement: old_entitlement, privilege: old_privilege, value: "okta") }

      before { old_value }

      it "discards it" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:entitlements].map { it[:code] }).to eq(["seats"])
        expect(old_entitlement.reload).to be_discarded
        expect(old_value.reload).to be_discarded
      end
    end

    context "with a value of each type" do
      let(:request_params) do
        {entitlements: {seats: {max: "25", provider: "okta", enabled: true, invitation: "phone"}}}
      end

      before do
        create(:privilege, organization:, feature:, code: "provider", name: "Provider", value_type: "string")
        create(:privilege, organization:, feature:, code: "enabled", name: nil, value_type: "boolean")
        create(:privilege, organization:, feature:, code: "invitation", name: nil, value_type: "select", config: {select_options: %w[email phone]})
      end

      it "saves and renders each value cast by type" do
        request

        expect(response).to have_http_status(:success)
        # `match` rather than `eq`, so that the privileges compose with match_array: the whole body is still compared.
        expect(json).to match(
          entitlements: [
            {
              code: "seats",
              name: "Seats",
              description: nil,
              privileges: match_array([
                {code: "max", name: nil, value_type: "integer", value: 25, config: {}},
                {code: "provider", name: "Provider", value_type: "string", value: "okta", config: {}},
                {code: "enabled", name: nil, value_type: "boolean", value: true, config: {}},
                {code: "invitation", name: nil, value_type: "select", value: "phone", config: {select_options: %w[email phone]}}
              ])
            }
          ]
        )
        expect(catalog_plan.entitlements.sole.values.to_h { [it.privilege.code, it.value] })
          .to eq("max" => "25", "provider" => "okta", "enabled" => "t", "invitation" => "phone")
      end
    end

    context "with an empty entitlements map" do
      let(:request_params) { {entitlements: {}} }
      let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:value) { create(:entitlement_value, organization:, entitlement:, privilege:, value: "10") }

      before { value }

      it "discards every entitlement and value of the plan" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(entitlements: [])
        expect(entitlement.reload).to be_discarded
        expect(value.reload).to be_discarded
      end
    end

    context "without the entitlements key" do
      let(:request_params) { {} }

      it "returns a missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "entitlements", meta: {}}])
      end
    end

    context "when entitlements is not a map" do
      let(:request_params) { {entitlements: "seats"} }

      it "returns a value_is_invalid error on entitlements" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "value_is_invalid", details: [{code: "value_is_invalid", field: "entitlements", meta: {}}])
      end
    end

    context "when a feature value is not a map" do
      let(:request_params) { {entitlements: {seats: [50]}} }

      it "returns a value_is_invalid error on the feature" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "value_is_invalid", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}])
      end
    end

    context "when a privilege value is an object" do
      let(:request_params) { {entitlements: {seats: {max: {value: 50}}}} }

      it "returns a value_is_invalid error on the privilege" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "value_is_invalid", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}])
        expect(catalog_plan.entitlements).to be_empty
      end
    end

    context "when a privilege value is an array" do
      let(:request_params) { {entitlements: {seats: {max: [50]}}} }

      it "returns a value_is_invalid error on the privilege" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "value_is_invalid", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}])
      end
    end

    context "with a false privilege value" do
      let(:request_params) { {entitlements: {seats: {enabled: false}}} }

      before { create(:privilege, organization:, feature:, code: "enabled", name: nil, value_type: "boolean") }

      it "saves it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          entitlements: [
            {
              code: "seats",
              name: "Seats",
              description: nil,
              privileges: [{code: "enabled", name: nil, value_type: "boolean", value: false, config: {}}]
            }
          ]
        )
      end
    end

    context "with an invalid privilege value after a valid feature" do
      let(:request_params) { {entitlements: {seats: {max: 50}, sso: {provider: "okta", domains: ["a"]}}} }

      it "returns a value_is_invalid error on the first invalid path" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "value_is_invalid", details: [{code: "value_is_invalid", field: "entitlements.sso.domains", meta: {}}])
        expect(catalog_plan.entitlements).to be_empty
      end
    end

    context "with expands" do
      let(:query) { "?expands[]=feature" }

      it "returns expand_not_supported" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "expand_not_supported",
          details: [{code: "not_expandable", field: "expands", meta: {invalid_values: ["feature"]}}]
        )
      end
    end

    [
      ["limit", "1"],
      ["page", "1"],
      ["after", "x"],
      ["include_total_count", "true"]
    ].each do |name, value|
      context "with the #{name} pagination parameter" do
        let(:query) { "?#{name}=#{value}" }

        it "returns a not_paginated error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}])
          expect(catalog_plan.entitlements).to be_empty
        end
      end
    end

    context "when the service refuses an entry" do
      let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:value) { create(:entitlement_value, organization:, entitlement:, privilege:, value: "10") }

      before { value }

      # The entries before the failing one are written, then rolled back.
      shared_examples "a refused replace" do |details|
        it "returns the error on the path of the entry and writes nothing" do
          expect { request }
            .to not_change(Entitlement::Entitlement.with_discarded, :count)
            .and not_change(Entitlement::EntitlementValue.with_discarded, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details:)
          expect(entitlement.reload).not_to be_discarded
          expect(value.reload).to have_attributes(value: "10", deleted_at: nil)
        end
      end

      context "with an unknown feature" do
        let(:request_params) { {entitlements: {seats: {max: 50}, unknown: {max: 50}}} }

        include_examples "a refused replace",
          [{code: "resource_not_found", field: "entitlements.unknown", meta: {resource: "feature"}}]
      end

      context "with an unknown privilege" do
        let(:request_params) { {entitlements: {seats: {max: 50, unknown: 1}}} }

        include_examples "a refused replace",
          [{code: "resource_not_found", field: "entitlements.seats.unknown", meta: {resource: "privilege"}}]
      end

      context "with an invalid integer value" do
        let(:request_params) { {entitlements: {seats: {max: "many"}}} }

        include_examples "a refused replace",
          [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}]
      end

      context "with a null privilege value" do
        let(:request_params) { {entitlements: {seats: {max: nil}}} }

        include_examples "a refused replace",
          [{code: "value_is_mandatory", field: "entitlements.seats.max", meta: {}}]
      end

      context "with a select value outside the options" do
        let(:request_params) { {entitlements: {seats: {max: 50, invitation: "fax"}}} }

        before { create(:privilege, organization:, feature:, code: "invitation", name: nil, value_type: "select", config: {select_options: %w[email phone]}) }

        include_examples "a refused replace",
          [{code: "value_not_in_select_options", field: "entitlements.seats.invitation", meta: {allowed_values: %w[email phone]}}]
      end

      context "with two features sharing a privilege code and an invalid value on the second" do
        let(:request_params) { {entitlements: {seats: {max: 50}, storage: {max: "many"}}} }

        before do
          storage = create(:feature, organization:, code: "storage")
          create(:privilege, organization:, feature: storage, code: "max", value_type: "integer")
        end

        include_examples "a refused replace",
          [{code: "value_is_invalid", field: "entitlements.storage.max", meta: {}}]
      end
    end

    context "when the service fails without a failing entry" do
      before do
        allow(Entitlement::PlanEntitlementsUpdateService).to receive(:call)
          .and_return(Entitlement::PlanEntitlementsUpdateService::Result.new.not_found_failure!(resource: "plan"))
      end

      it "renders the failure as it is" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "when the service fails on an entry with a field of its own" do
      let(:failure) do
        Entitlement::PlanEntitlementsUpdateService::Result.new.tap do
          it.failed_field = :"entitlements.seats.max"
          it.single_validation_failure!(field: :feature, error_code: "value_already_exist")
        end
      end

      before { allow(Entitlement::PlanEntitlementsUpdateService).to receive(:call).and_return(failure) }

      it "keeps the field" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "feature", meta: {}}])
      end
    end

    context "when the service fails on an entry with another failure" do
      let(:failure) do
        Entitlement::PlanEntitlementsUpdateService::Result.new.tap do
          it.failed_field = :"entitlements.seats"
          it.forbidden_failure!
        end
      end

      before { allow(Entitlement::PlanEntitlementsUpdateService).to receive(:call).and_return(failure) }

      it "renders the failure as it is" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end

    context "with an unknown plan code" do
      let(:plan_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "with the catalog plan of another organization" do
      let(:plan_code) { create(:catalog_plan, organization: create(:organization), code: "shared").code }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "with a legacy plan code" do
      let(:plan_code) { create(:plan, organization:, code: "legacy").code }

      before { allow(Entitlement::PlanEntitlementsUpdateService).to receive(:call).and_call_original }

      it "returns not found without calling the service" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(Entitlement::PlanEntitlementsUpdateService).not_to have_received(:call)
      end
    end

    context "with a deleted catalog plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium", deleted_at: Time.current) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "without the product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
