# frozen_string_literal: true

require "rails_helper"

# The entitlements render in the v1 shape: no datetime to render to the microsecond.
RSpec.describe Api::V2::Plans::EntitlementsController do
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
      expect(json).to eq(plan_entitlements: [plan_entitlement_json(catalog_plan.entitlements.sole, [{privilege_code: "max", value: 50}])])
      expect(catalog_plan.entitlements.sole.values.sole.value).to eq("50")
    end

    context "with the entitlement_events flag" do
      before { organization.enable_feature_flag!(:entitlement_events) }

      it "writes one plan_entitlement.created activity log and webhook, and no plan.updated event" do
        expect { request }.to have_enqueued_job(SendWebhookJob).exactly(:once)

        entitlement = catalog_plan.entitlements.sole
        expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.created", entitlement)
        expect(Utils::ActivityLog).to have_received(:produce).with(
          entitlement, "plan_entitlement.created", after_commit: true,
          changes: {"values" => [nil, [{privilege_code: "max", value: 50}]]},
          activity_object: hash_including(lago_id: entitlement.id, values: [{privilege_code: "max", value: 50}])
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).once
      end

      it "writes no activity log and sends no webhook when the same call runs again" do
        post_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements", request_params)
        expect(Utils::ActivityLog).to have_received(:produce).once

        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(:success)
        expect(Utils::ActivityLog).to have_received(:produce).once
      end
    end

    it "logs nothing and sends no webhook without the entitlement_events flag" do
      expect { request }.not_to have_enqueued_job(SendWebhookJob)

      expect(response).to have_http_status(:success)
      expect(Utils::ActivityLog).not_to have_received(:produce)
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
        expect(json[:plan_entitlements].map { it[:feature_code] }).to eq(["seats"])
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
        # `match` rather than `eq`, so that the values compose with match_array: the whole body is still compared.
        expect(json).to match(
          plan_entitlements: [
            plan_entitlement_json(
              catalog_plan.entitlements.sole,
              match_array([
                {privilege_code: "max", value: 25},
                {privilege_code: "provider", value: "okta"},
                {privilege_code: "enabled", value: true},
                {privilege_code: "invitation", value: "phone"}
              ])
            )
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
        expect(json).to eq(plan_entitlements: [])
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

      it "returns a missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "entitlements", meta: {}}])
      end
    end

    context "when a feature value is not a map" do
      let(:request_params) { {entitlements: {seats: [50]}} }

      it "returns a value_is_invalid error on the feature" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}])
      end
    end

    [nil, "", []].each do |blank_value|
      context "when a feature value is #{blank_value.inspect}" do
        let(:request_params) { {entitlements: {seats: blank_value}} }
        let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }

        before { create(:entitlement_value, organization:, entitlement:, privilege:, value: "10") }

        it "returns a value_is_invalid error on the feature and keeps the stored values" do
          request

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}])
          expect(catalog_plan.entitlements.sole.values.sole.value).to eq("10")
        end
      end
    end

    context "when an unknown feature value is not a map" do
      let(:request_params) { {entitlements: {nope: [1]}} }

      it "returns a resource_not_found error on the feature" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "resource_not_found", field: "entitlements.nope", meta: {resource: "feature"}}])
      end
    end

    context "when a privilege value is an object" do
      let(:request_params) { {entitlements: {seats: {max: {value: 50}}}} }

      it "returns a value_is_invalid error on the privilege" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}])
        expect(catalog_plan.entitlements).to be_empty
      end
    end

    context "when a privilege value is an array" do
      let(:request_params) { {entitlements: {seats: {max: [50]}}} }

      it "returns a value_is_invalid error on the privilege" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}])
      end
    end

    context "with a false privilege value" do
      let(:request_params) { {entitlements: {seats: {enabled: false}}} }

      before { create(:privilege, organization:, feature:, code: "enabled", name: nil, value_type: "boolean") }

      it "saves it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [plan_entitlement_json(catalog_plan.entitlements.sole, [{privilege_code: "enabled", value: false}])])
      end
    end

    context "with an invalid privilege value after a valid feature" do
      let(:request_params) { {entitlements: {seats: {max: 50}, sso: {provider: "okta", domains: ["a"]}}} }
      let(:sso) { create(:feature, organization:, code: "sso") }

      before do
        create(:privilege, organization:, feature: sso, code: "provider", value_type: "string")
        create(:privilege, organization:, feature: sso, code: "domains", value_type: "string")
      end

      it "returns a value_is_invalid error on the first invalid path" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.sso.domains", meta: {}}])
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
      ["after", "x"]
    ].each do |name, value|
      context "with the #{name} pagination parameter" do
        let(:query) { "?#{name}=#{value}" }

        it "returns a not_paginated error and writes nothing" do
          expect { request }.not_to change(Entitlement::Entitlement, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}])
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

    context "with more entitlements or values than a catalog plan holds" do
      let(:feature_count) { 0 }
      let(:value_count) { 1 }
      let(:feature_codes) { bulk_create_features(organization, feature_count).keys }
      # max and 50 more integer privileges: 51 privileges on seats.
      let(:seats_privileges) { [privilege, *create_list(:privilege, 50, organization:, feature:, value_type: "integer")] }
      let(:request_params) do
        {entitlements: feature_codes.index_with { {} }.merge("seats" => seats_privileges.first(value_count).to_h { [it.code, 1] })}
      end
      let(:old_feature) { create(:feature, organization:, code: "sso") }
      let(:old_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: old_feature) }
      let(:old_value) do
        create(:entitlement_value, organization:, entitlement: old_entitlement, privilege: create(:privilege, organization:, feature: old_feature), value: "okta")
      end

      before do
        feature_codes
        seats_privileges
        old_value
      end

      shared_examples "a refused write" do |details|
        it "returns every crossed limit and writes nothing" do
          expect { request }
            .to not_change(Entitlement::Entitlement.with_discarded, :count)
            .and not_change(Entitlement::EntitlementValue.with_discarded, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details:)
          expect(old_entitlement.reload).not_to be_discarded
          expect(old_value.reload).to have_attributes(value: "okta", deleted_at: nil)
        end
      end

      context "with 200 entitlements" do
        let(:feature_count) { 199 }

        it "accepts them" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:plan_entitlements].size).to eq(200) # 199 bulk features + seats, sso dropped
          expect(catalog_plan.entitlements.count).to eq(200)
        end
      end

      context "with 201 entitlements" do
        let(:feature_count) { 200 }

        include_examples "a refused write",
          [{code: "too_many_entitlements", field: "base", meta: {max_items: 200}}]
      end

      context "with 50 values on an entitlement" do
        let(:value_count) { 50 }

        it "accepts them" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:plan_entitlements].sole[:values].size).to eq(50)
        end
      end

      context "with 51 values on an entitlement" do
        let(:value_count) { 51 }

        include_examples "a refused write",
          [{code: "too_many_values", field: "entitlements.seats", meta: {max_items: 50}}]
      end

      context "with both limits crossed" do
        let(:feature_count) { 200 }
        let(:value_count) { 51 }

        # The oversized replace is refused before the values are written.
        include_examples "a refused write",
          [{code: "too_many_entitlements", field: "base", meta: {max_items: 200}}]
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

  describe "PATCH /api/v2/plans/:plan_code/entitlements" do
    subject(:request) { patch_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements#{query}", request_params) }

    let(:plan_code) { catalog_plan.code }
    let(:query) { "" }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:value) { create(:entitlement_value, organization:, entitlement:, privilege:, value: "50") }
    let(:sso) { create(:feature, organization:, code: "sso", name: "SSO", description: nil) }
    let(:provider) { create(:privilege, organization:, feature: sso, code: "provider", name: "Provider", value_type: "string") }
    let(:request_params) { {entitlements: {sso: {provider: "okta"}}} }

    before do
      value
      provider
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      # The per-entitlement events are behind the entitlement_events flag, see "without the entitlement_events flag".
      organization.enable_feature_flag!(:entitlement_events)
    end

    include_examples "requires API permission", "plan", "write"

    it "adds the features of the body and keeps the others, newest first" do
      expect { request }.not_to change { Entitlement::Entitlement.with_discarded.where.not(deleted_at: nil).count }

      expect(response).to have_http_status(:success)
      expect(json).to eq(
        plan_entitlements: [
          plan_entitlement_json(catalog_plan.entitlements.find_by!(feature: sso), [{privilege_code: "provider", value: "okta"}]),
          plan_entitlement_json(entitlement, [{privilege_code: "max", value: 50}])
        ]
      )
      expect(entitlement.reload).not_to be_discarded
      expect(value.reload).to have_attributes(value: "50", deleted_at: nil)
    end

    it "writes one plan_entitlement.created activity log and webhook for the added feature only" do
      expect { request }.to have_enqueued_job(SendWebhookJob).exactly(:once)

      sso_entitlement = catalog_plan.entitlements.find_by!(feature: sso)
      expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.created", sso_entitlement)
      expect(Utils::ActivityLog).to have_received(:produce).with(
        sso_entitlement, "plan_entitlement.created", after_commit: true,
        changes: {"values" => [nil, [{privilege_code: "provider", value: "okta"}]]},
        activity_object: hash_including(lago_id: sso_entitlement.id, values: [{privilege_code: "provider", value: "okta"}])
      ).once
      expect(Utils::ActivityLog).to have_received(:produce).once
    end

    context "without the entitlement_events flag" do
      before { organization.disable_feature_flag!(:entitlement_events) }

      it "logs nothing and sends no webhook" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(:success)
        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    it "writes no activity log and sends no webhook when the same call runs again" do
      patch_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements", request_params)
      expect(Utils::ActivityLog).to have_received(:produce).once

      expect { request }.not_to have_enqueued_job(SendWebhookJob)

      expect(response).to have_http_status(:success)
      expect(Utils::ActivityLog).to have_received(:produce).once
    end

    context "with a value of an existing feature" do
      let(:request_params) { {entitlements: {seats: {max: 60}}} }
      let(:storage) { create(:privilege, organization:, feature:, code: "storage", name: nil, value_type: "integer") }
      let(:storage_value) { create(:entitlement_value, organization:, entitlement:, privilege: storage, value: "10") }

      before { storage_value }

      it "updates the value of the body and keeps the other values" do
        request

        expect(response).to have_http_status(:success)
        # `match` rather than `eq`, so that the values compose with match_array: the whole body is still compared.
        expect(json).to match(
          plan_entitlements: [
            plan_entitlement_json(entitlement, match_array([{privilege_code: "max", value: 60}, {privilege_code: "storage", value: 10}]))
          ]
        )
        expect(value.reload).to have_attributes(value: "60", deleted_at: nil)
        expect(storage_value.reload).to have_attributes(value: "10", deleted_at: nil)
      end
    end

    context "with several features" do
      let(:request_params) { {entitlements: {seats: {max: 60}, sso: {provider: "okta"}}} }

      it "writes one event per changed entitlement: updated for seats, created for sso" do
        expect { request }.to have_enqueued_job(SendWebhookJob).exactly(:twice)

        expect(response).to have_http_status(:success)
        expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.updated", entitlement)
        expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.created", catalog_plan.entitlements.find_by!(feature: sso))
        expect(Utils::ActivityLog).to have_received(:produce).with(
          entitlement, "plan_entitlement.updated", after_commit: true,
          changes: {"values" => [[{privilege_code: "max", value: 50}], [{privilege_code: "max", value: 60}]]},
          activity_object: hash_including(lago_id: entitlement.id, values: [{privilege_code: "max", value: 60}])
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).twice
      end
    end

    context "with an empty entitlements map" do
      let(:request_params) { {entitlements: {}} }

      it "keeps every entitlement and value of the plan" do
        expect { request }
          .to not_change(Entitlement::Entitlement.with_discarded, :count)
          .and not_change(Entitlement::EntitlementValue.with_discarded, :count)

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [plan_entitlement_json(entitlement, [{privilege_code: "max", value: 50}])])
        expect(entitlement.reload).not_to be_discarded
        expect(value.reload).to have_attributes(value: "50", deleted_at: nil)
      end

      it "writes no activity log and sends no webhook, as nothing changes" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    # Each refused request leaves the entitlements of the plan as they were.
    shared_examples "a refused merge" do |status, body|
      it "returns the error and writes nothing" do
        expect { request }
          .to not_change(Entitlement::Entitlement.with_discarded, :count)
          .and not_change(Entitlement::EntitlementValue.with_discarded, :count)

        expect(response).to have_http_status(status)
        expect(json).to eq(body)
        expect(entitlement.reload).not_to be_discarded
        expect(value.reload).to have_attributes(value: "50", deleted_at: nil)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "without the entitlements key" do
      let(:request_params) { {} }

      include_examples "a refused merge", :bad_request,
        {code: "missing_parameter", details: [{code: "missing", field: "entitlements", meta: {}}]}
    end

    context "when entitlements is not a map" do
      let(:request_params) { {entitlements: "seats"} }

      include_examples "a refused merge", :bad_request,
        {code: "missing_parameter", details: [{code: "missing", field: "entitlements", meta: {}}]}
    end

    context "when a feature value is not a map" do
      let(:request_params) { {entitlements: {seats: [60]}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}]}
    end

    context "when a privilege value is an object" do
      let(:request_params) { {entitlements: {seats: {max: {value: 60}}}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}]}
    end

    # PATCH cannot remove a feature: a null feature value is refused, where {} is a feature with no values.
    context "when a feature value is null" do
      let(:request_params) { {entitlements: {sso: {provider: "okta"}, seats: nil}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats", meta: {}}]}

      it "sends no activity log" do
        request

        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    context "when a feature value is null and the feature is unknown" do
      let(:request_params) { {entitlements: {unknown: nil}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "resource_not_found", field: "entitlements.unknown", meta: {resource: "feature"}}]}
    end

    context "when a feature value is an empty map" do
      let(:request_params) { {entitlements: {sso: {}}} }

      it "adds the feature with no values" do
        request

        expect(response).to have_http_status(:success)
        expect(catalog_plan.entitlements.find_by(feature: sso).values).to be_empty
      end
    end

    context "with expands" do
      let(:query) { "?expands[]=feature" }

      include_examples "a refused merge", :bad_request,
        {code: "expand_not_supported", details: [{code: "not_expandable", field: "expands", meta: {invalid_values: ["feature"]}}]}
    end

    [
      ["limit", "1"],
      ["page", "1"],
      ["after", "x"],
      ["include_total_count", "true"]
    ].each do |name, param_value|
      context "with the #{name} pagination parameter" do
        let(:query) { "?#{name}=#{param_value}" }

        include_examples "a refused merge", :bad_request,
          {code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}]}
      end
    end

    context "with an unknown feature" do
      let(:request_params) { {entitlements: {sso: {provider: "okta"}, unknown: {max: 60}}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "resource_not_found", field: "entitlements.unknown", meta: {resource: "feature"}}]}
    end

    context "with an unknown privilege" do
      let(:request_params) { {entitlements: {seats: {max: 60, unknown: 1}}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "resource_not_found", field: "entitlements.seats.unknown", meta: {resource: "privilege"}}]}
    end

    context "with an invalid integer value" do
      let(:request_params) { {entitlements: {seats: {max: "many"}}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_invalid", field: "entitlements.seats.max", meta: {}}]}
    end

    # PATCH cannot delete: a null value is refused, not a removal.
    context "with a null value on an existing privilege" do
      let(:request_params) { {entitlements: {seats: {max: nil}}} }

      include_examples "a refused merge", :unprocessable_content,
        {code: "validation_errors", details: [{code: "value_is_mandatory", field: "entitlements.seats.max", meta: {}}]}
    end

    context "with a select value outside the options" do
      let(:request_params) { {entitlements: {seats: {invitation: "fax"}}} }

      before { create(:privilege, organization:, feature:, code: "invitation", name: nil, value_type: "select", config: {select_options: %w[email phone]}) }

      include_examples "a refused merge", :unprocessable_content,
        {
          code: "validation_errors",
          details: [{code: "value_not_in_select_options", field: "entitlements.seats.invitation", meta: {allowed_values: %w[email phone]}}]
        }
    end

    context "with more entitlements or values than a catalog plan holds" do
      let(:bulk_count) { 0 }
      let(:extra_value_count) { 0 }
      # rubocop:disable Rails/SkipsModelValidations
      let(:bulk_entitlements) do
        next if bulk_count.zero?

        now = Time.current
        feature_ids = bulk_create_features(organization, bulk_count).values
        Entitlement::Entitlement.insert_all!(
          feature_ids.map { {organization_id: organization.id, entitlement_feature_id: it, catalog_plan_id: catalog_plan.id, created_at: now, updated_at: now} }
        )
      end
      let(:extra_values) do
        next if extra_value_count.zero?

        now = Time.current
        privileges = create_list(:privilege, extra_value_count, organization:, feature:, value_type: "integer")
        Entitlement::EntitlementValue.insert_all!(
          privileges.map do
            {organization_id: organization.id, entitlement_entitlement_id: entitlement.id, entitlement_privilege_id: it.id, value: "1", created_at: now, updated_at: now}
          end
        )
      end
      # rubocop:enable Rails/SkipsModelValidations
      let(:new_privilege) { create(:privilege, organization:, feature:, code: "new", value_type: "integer") }

      before do
        bulk_entitlements
        extra_values
        new_privilege
      end

      context "with 199 entitlements on the plan" do
        let(:bulk_count) { 198 }

        it "accepts one more" do
          request

          expect(response).to have_http_status(:success)
          expect(catalog_plan.entitlements.count).to eq(200) # 198 bulk + seats + sso
        end
      end

      context "with 200 entitlements on the plan" do
        let(:bulk_count) { 199 } # 199 bulk + seats

        include_examples "a refused merge", :unprocessable_content,
          {code: "validation_errors", details: [{code: "too_many_entitlements", field: "base", meta: {max_items: 200}}]}

        context "with a value of an existing feature" do
          let(:request_params) { {entitlements: {seats: {max: 60}}} }

          it "accepts it" do
            request

            expect(response).to have_http_status(:success)
            expect(catalog_plan.entitlements.count).to eq(200)
            expect(value.reload.value).to eq("60")
          end
        end
      end

      context "with 49 values on an entitlement" do
        let(:extra_value_count) { 48 } # max + 48 bulk values
        let(:request_params) { {entitlements: {seats: {new: 1}}} }

        it "accepts one more" do
          request

          expect(response).to have_http_status(:success)
          expect(entitlement.values.count).to eq(50) # max + 48 bulk values + new
        end
      end

      context "with 50 values on an entitlement" do
        let(:extra_value_count) { 49 } # max + 49 bulk values
        let(:request_params) { {entitlements: {seats: {new: 1}}} }

        include_examples "a refused merge", :unprocessable_content,
          {code: "validation_errors", details: [{code: "too_many_values", field: "entitlements.seats", meta: {max_items: 50}}]}
      end
    end

    context "with an unknown plan code" do
      let(:plan_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(SendWebhookJob).not_to have_been_enqueued
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

  describe "GET /api/v2/plans/:plan_code/entitlements" do
    subject(:request) { get_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements#{query}") }

    let(:plan_code) { catalog_plan.code }
    let(:query) { "" }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:sso) { create(:feature, organization:, code: "sso", name: "SSO", description: "Single sign-on") }
    let(:sso_privilege) { create(:privilege, organization:, feature: sso, code: "enabled", name: "Enabled", value_type: "boolean") }
    let(:sso_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso, created_at: 1.day.ago) }
    let(:seats_body) { plan_entitlement_json(entitlement, [{privilege_code: "max", value: 50}]) }
    let(:sso_body) { plan_entitlement_json(sso_entitlement, [{privilege_code: "enabled", value: true}]) }

    before do
      create(:entitlement_value, organization:, entitlement:, privilege:, value: "50")
      create(:entitlement_value, organization:, entitlement: sso_entitlement, privilege: sso_privilege, value: "true")
    end

    include_examples "requires API permission", "plan", "read"

    it "lists every entitlement of the catalog plan, newest first, without pagination", :bullet do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(plan_entitlements: [seats_body, sso_body])
    end

    context "with two values on an entitlement" do
      let(:admins) do
        create(:privilege, organization:, feature:, code: "admins", name: "Admins", value_type: "integer", created_at: 1.day.ago)
      end

      before do
        # Its value is written after the max one, but its privilege is older: the order comes from the privileges.
        create(:entitlement_value, organization:, entitlement:, privilege: admins, value: "5")
      end

      it "lists its privileges newest privilege first" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:plan_entitlements].first[:values].pluck(:privilege_code)).to eq(%w[max admins])
      end
    end

    context "with two entitlements created at the same time" do
      let(:sso_entitlement) do
        create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso, created_at: entitlement.created_at)
      end

      it "orders them by id" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:plan_entitlements]).to eq([[entitlement.id, seats_body], [sso_entitlement.id, sso_body]].sort_by(&:first).map(&:last))
      end
    end

    context "with a discarded entitlement" do
      before { sso_entitlement.discard! }

      it "does not list it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [seats_body])
      end
    end

    context "with an entitlement of a discarded feature" do
      before { sso.discard! }

      it "does not list it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [seats_body])
        expect(sso_entitlement.reload).not_to be_discarded
      end
    end

    context "with a discarded privilege and a discarded value" do
      let(:min_privilege) { create(:privilege, organization:, feature:, code: "min", value_type: "integer") }
      let(:burst_privilege) { create(:privilege, organization:, feature:, code: "burst", value_type: "integer") }

      before do
        create(:entitlement_value, organization:, entitlement:, privilege: min_privilege, value: "10")
        create(:entitlement_value, organization:, entitlement:, privilege: burst_privilege, value: "5").discard!
        min_privilege.discard!
      end

      it "lists only the kept values of kept privileges", :bullet do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [seats_body, sso_body])
      end
    end

    context "with an entitlement of another catalog plan" do
      let(:sso_entitlement) do
        create(:entitlement, :catalog_plan, organization:, catalog_plan: create(:catalog_plan, organization:, code: "other"), feature: sso)
      end

      it "does not list it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [seats_body])
      end
    end

    context "without entitlements" do
      let(:plan_code) { create(:catalog_plan, organization:, code: "empty").code }

      it "returns an empty list" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlements: [])
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
      ["per_page", "1"],
      ["after", "x"],
      ["before", "x"],
      ["include_total_count", "true"]
    ].each do |name, value|
      context "with the #{name} pagination parameter" do
        let(:query) { "?#{name}=#{value}" }

        it "returns a not_paginated error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}])
        end
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
      let(:legacy_plan) { create(:plan, organization:, code: "legacy") }
      let(:plan_code) { legacy_plan.code }

      before do
        legacy_entitlement = create(:entitlement, organization:, plan: legacy_plan, feature:)
        create(:entitlement_value, organization:, entitlement: legacy_entitlement, privilege:, value: "30")
      end

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
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
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  describe "GET /api/v2/plans/:plan_code/entitlements/:code" do
    subject(:request) { get_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements/#{feature_code}#{query}") }

    let(:plan_code) { catalog_plan.code }
    let(:feature_code) { feature.code }
    let(:query) { "" }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:sso) { create(:feature, organization:, code: "sso", name: "SSO", description: "Single sign-on") }

    before do
      create(:entitlement_value, organization:, entitlement:, privilege:, value: "50")
      create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso)
    end

    include_examples "requires API permission", "plan", "read"

    it "returns the entitlement of the catalog plan", :bullet do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(plan_entitlement: plan_entitlement_json(entitlement, [{privilege_code: "max", value: 50}]))
    end

    context "with a feature code containing a dot" do
      let(:feature) { create(:feature, organization:, code: "seats.v2", name: "Seats", description: nil) }

      it "returns the entitlement" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlement: plan_entitlement_json(entitlement, [{privilege_code: "max", value: 50}]))
      end
    end

    context "with an unknown feature code" do
      let(:feature_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "with a feature the catalog plan does not grant" do
      let(:feature_code) { create(:feature, organization:, code: "api").code }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "with a feature granted by another catalog plan" do
      let(:feature_code) { "api" }

      before do
        api = create(:feature, organization:, code: "api")
        create(:entitlement, :catalog_plan, organization:, catalog_plan: create(:catalog_plan, organization:, code: "other"), feature: api)
      end

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "with a discarded entitlement" do
      before { entitlement.discard! }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "with an entitlement of a discarded feature" do
      before { feature.discard! }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
        expect(entitlement.reload).not_to be_discarded
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
      ["per_page", "1"],
      ["after", "x"],
      ["before", "x"],
      ["include_total_count", "true"]
    ].each do |name, value|
      context "with the #{name} pagination parameter" do
        let(:query) { "?#{name}=#{value}" }

        it "returns a not_paginated error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: name, meta: {}}])
        end
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
      let(:plan_code) { "shared" }

      before do
        other_organization = create(:organization)
        other_plan = create(:catalog_plan, organization: other_organization, code: "shared")
        other_feature = create(:feature, organization: other_organization, code: "seats")
        create(:entitlement, :catalog_plan, organization: other_organization, catalog_plan: other_plan, feature: other_feature)
      end

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
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
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  describe "DELETE /api/v2/plans/:plan_code/entitlements/:code" do
    subject(:request) { delete_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements/#{feature_code}#{query}") }

    let(:plan_code) { catalog_plan.code }
    let(:feature_code) { feature.code }
    let(:query) { "" }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:value) { create(:entitlement_value, organization:, entitlement:, privilege:, value: "30") }
    let(:other_plan) { create(:catalog_plan, organization:, code: "other") }
    let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_plan, feature:) }
    let(:other_value) { create(:entitlement_value, organization:, entitlement: other_entitlement, privilege:, value: "40") }

    before do
      value
      other_value
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      # The per-entitlement events are behind the entitlement_events flag, see "without the entitlement_events flag".
      organization.enable_feature_flag!(:entitlement_events)
    end

    shared_examples "a refused remove" do
      it "discards nothing" do
        request

        expect(entitlement.reload).not_to be_discarded
        expect(value.reload).to have_attributes(value: "30", deleted_at: nil)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    include_examples "requires API permission", "plan", "write"

    # In a context of its own: the :bullet hook registers on the group of the example, so it would reach
    # the examples that run after it, such as the one whose stubbed service leaves the preload unused.
    context "with an entitlement granted by the catalog plan" do
      # Two values, so that a query per value would be caught.
      let(:min_privilege) { create(:privilege, organization:, feature:, code: "min", name: nil, value_type: "integer") }

      before { create(:entitlement_value, organization:, entitlement:, privilege: min_privilege, value: "5") }

      it "removes it and renders it with its last values and its deletion time", :bullet do
        request

        expect(response).to have_http_status(:success)
        # `match` rather than `eq`, so that the values compose with match_array: the whole body is still compared.
        expect(json).to match(
          plan_entitlement: plan_entitlement_json(entitlement, match_array([{privilege_code: "max", value: 30}, {privilege_code: "min", value: 5}]))
        )
        expect(json[:plan_entitlement][:deleted_at]).to be_present
        expect(entitlement.reload).to be_discarded
        expect(value.reload).to be_discarded
      end
    end

    context "without the entitlement_events flag" do
      before { organization.disable_feature_flag!(:entitlement_events) }

      it "removes the entitlement, logs nothing and sends no webhook" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(:success)
        expect(entitlement.reload).to be_discarded
        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    it "no longer lists the entitlement and keeps it on another catalog plan" do
      request
      get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}/entitlements")

      expect(json).to eq(plan_entitlements: [])
      expect(other_entitlement.reload).not_to be_discarded
      expect(other_value.reload).to have_attributes(value: "40", deleted_at: nil)
    end

    it "sends one plan_entitlement.deleted webhook after commit, with the values it held, and no plan.updated webhook" do
      expect { request }.to have_enqueued_job_after_commit(SendWebhookJob)
        .with("plan_entitlement.deleted", entitlement, {values: [{privilege_code: "max", value: 30}]}).exactly(:once)

      expect(response).to have_http_status(:success)
      expect(SendWebhookJob).to have_been_enqueued.exactly(:once)
    end

    it "produces one plan_entitlement.deleted activity log and no plan.updated" do
      request

      expect(Utils::ActivityLog).to have_received(:produce)
        .with(
          entitlement, "plan_entitlement.deleted", after_commit: true,
          changes: {"values" => [[{privilege_code: "max", value: 30}], nil]},
          activity_object: hash_including(lago_id: entitlement.id, values: [{privilege_code: "max", value: 30}])
        ).once
      expect(Utils::ActivityLog).to have_received(:produce).once
    end

    context "with a feature code containing a dot" do
      let(:feature) { create(:feature, organization:, code: "seats.v2", name: "Seats", description: nil) }

      it "removes the entitlement" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:plan_entitlement][:feature_code]).to eq("seats.v2")
        expect(entitlement.reload).to be_discarded
      end
    end

    context "with an unknown feature code" do
      let(:feature_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end

      include_examples "a refused remove"
    end

    context "with a feature the catalog plan does not grant" do
      let(:feature_code) { "api" }
      let(:api_entitlement) do
        create(:entitlement, :catalog_plan, organization:, catalog_plan: other_plan, feature: create(:feature, organization:, code: "api"))
      end

      before { api_entitlement }

      it "returns not found and keeps the entitlement of the other catalog plan" do
        request

        expect(response).to be_v2_not_found_error("feature")
        expect(api_entitlement.reload).not_to be_discarded
      end

      include_examples "a refused remove"
    end

    context "when the service fails" do
      before do
        allow(Entitlement::PlanEntitlementDestroyService).to receive(:call)
          .and_return(Entitlement::PlanEntitlementDestroyService::Result.new.not_found_failure!(resource: "plan"))
      end

      it "renders the failure" do
        request

        expect(response).to be_v2_not_found_error("plan")
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

      include_examples "a refused remove"
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
        end

        include_examples "a refused remove"
      end
    end

    context "with an unknown plan code" do
      let(:plan_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end

      include_examples "a refused remove"
    end

    context "with the catalog plan of another organization" do
      let(:plan_code) { "shared" }
      let(:other_organization) { create(:organization) }
      let(:foreign_entitlement) do
        create(
          :entitlement, :catalog_plan,
          organization: other_organization,
          catalog_plan: create(:catalog_plan, organization: other_organization, code: "shared"),
          feature: create(:feature, organization: other_organization, code: "seats")
        )
      end

      before { foreign_entitlement }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(foreign_entitlement.reload).not_to be_discarded
      end

      include_examples "a refused remove"
    end

    context "with a legacy plan code" do
      let(:plan_code) { "legacy" }
      let(:legacy_entitlement) { create(:entitlement, organization:, plan: create(:plan, organization:, code: "legacy"), feature:) }

      before { legacy_entitlement }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(legacy_entitlement.reload).not_to be_discarded
      end

      include_examples "a refused remove"
    end

    context "with a deleted catalog plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium", deleted_at: Time.current) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end

      include_examples "a refused remove"
    end

    context "without the product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end

      include_examples "a refused remove"
    end
  end

  describe "DELETE /api/v2/plans/:plan_code/entitlements/:code/privileges/:privilege_code" do
    subject(:request) do
      delete_with_token(organization, "/api/v2/plans/#{plan_code}/entitlements/#{feature_code}/privileges/#{privilege_code}#{query}")
    end

    let(:plan_code) { catalog_plan.code }
    let(:feature_code) { feature.code }
    let(:privilege_code) { privilege.code }
    let(:query) { "" }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:value) { create(:entitlement_value, organization:, entitlement:, privilege:, value: "30") }
    let(:other_privilege) { create(:privilege, organization:, feature:, code: "min", name: nil, value_type: "integer") }
    let(:kept_value) { create(:entitlement_value, organization:, entitlement:, privilege: other_privilege, value: "5") }
    let(:other_plan) { create(:catalog_plan, organization:, code: "other") }
    let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_plan, feature:) }
    let(:other_value) { create(:entitlement_value, organization:, entitlement: other_entitlement, privilege:, value: "40") }

    before do
      value
      kept_value
      other_value
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      # The per-entitlement events are behind the entitlement_events flag, see "without the entitlement_events flag".
      organization.enable_feature_flag!(:entitlement_events)
    end

    shared_examples "a refused value remove" do
      it "discards nothing" do
        request

        expect(entitlement.reload).not_to be_discarded
        expect(value.reload).to have_attributes(value: "30", deleted_at: nil)
        expect(kept_value.reload).to have_attributes(value: "5", deleted_at: nil)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    include_examples "requires API permission", "plan", "write"

    it "removes the value and renders the entitlement with its other values" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(plan_entitlement: plan_entitlement_json(entitlement, [{privilege_code: "min", value: 5}]))
      expect(value.reload).to be_discarded
      expect(entitlement.reload).not_to be_discarded
      expect(kept_value.reload).to have_attributes(value: "5", deleted_at: nil)
    end

    context "without the entitlement_events flag" do
      before { organization.disable_feature_flag!(:entitlement_events) }

      it "removes the value, logs nothing and sends no webhook" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(:success)
        expect(value.reload).to be_discarded
        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    it "touches the entitlement" do
      entitlement.update_columns(updated_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

      freeze_time do
        request

        expect(entitlement.reload.updated_at).to eq(Time.current)
      end
    end

    it "keeps the same value on another catalog plan" do
      request

      expect(other_entitlement.reload).not_to be_discarded
      expect(other_value.reload).to have_attributes(value: "40", deleted_at: nil)
    end

    it "sends one plan_entitlement.updated webhook after commit and no plan.updated webhook" do
      expect { request }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_entitlement.updated", entitlement).exactly(:once)

      expect(response).to have_http_status(:success)
      expect(SendWebhookJob).to have_been_enqueued.exactly(:once)
    end

    it "produces one plan_entitlement.updated activity log and no plan.updated" do
      request

      expect(Utils::ActivityLog).to have_received(:produce).with(
        entitlement, "plan_entitlement.updated", after_commit: true,
        changes: {"values" => [[{privilege_code: "min", value: 5}, {privilege_code: "max", value: 30}], [{privilege_code: "min", value: 5}]]},
        activity_object: hash_including(lago_id: entitlement.id, values: [{privilege_code: "min", value: 5}])
      ).once
      expect(Utils::ActivityLog).to have_received(:produce).once
    end

    context "with the last value of the entitlement" do
      let(:kept_value) { nil }

      it "renders the entitlement without privileges and keeps it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(plan_entitlement: plan_entitlement_json(entitlement, []))
        expect(value.reload).to be_discarded
        expect(entitlement.reload).not_to be_discarded
      end
    end

    context "with feature and privilege codes containing a dot" do
      let(:feature) { create(:feature, organization:, code: "seats.v2", name: "Seats", description: nil) }
      let(:privilege) { create(:privilege, organization:, feature:, code: "max.v1", name: nil, value_type: "integer") }

      it "removes the value" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:plan_entitlement]).to include(feature_code: "seats.v2", values: [{privilege_code: "min", value: 5}])
        expect(value.reload).to be_discarded
      end
    end

    context "with an unknown feature code" do
      let(:feature_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end

      include_examples "a refused value remove"
    end

    context "with a feature the catalog plan does not grant" do
      let(:feature_code) { "api" }
      let(:api_feature) { create(:feature, organization:, code: "api") }
      let(:api_privilege) { create(:privilege, organization:, feature: api_feature, code: "max", value_type: "integer") }
      let(:api_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_plan, feature: api_feature) }
      let(:api_value) { create(:entitlement_value, organization:, entitlement: api_entitlement, privilege: api_privilege, value: "10") }

      before { api_value }

      it "returns not found and keeps the value of the other catalog plan" do
        request

        expect(response).to be_v2_not_found_error("feature")
        expect(api_value.reload).to have_attributes(value: "10", deleted_at: nil)
      end

      include_examples "a refused value remove"
    end

    context "with a privilege the entitlement has no value for" do
      let(:privilege_code) { "unset" }

      before { create(:privilege, organization:, feature:, code: "unset", value_type: "integer") }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end

      include_examples "a refused value remove"
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

      include_examples "a refused value remove"
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
        end

        include_examples "a refused value remove"
      end
    end

    context "with an unknown plan code" do
      let(:plan_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end

      include_examples "a refused value remove"
    end

    context "with the catalog plan of another organization" do
      let(:plan_code) { "shared" }
      let(:other_organization) { create(:organization) }
      let(:foreign_feature) { create(:feature, organization: other_organization, code: "seats") }
      let(:foreign_entitlement) do
        create(
          :entitlement, :catalog_plan,
          organization: other_organization,
          catalog_plan: create(:catalog_plan, organization: other_organization, code: "shared"),
          feature: foreign_feature
        )
      end
      let(:foreign_value) do
        create(
          :entitlement_value,
          organization: other_organization,
          entitlement: foreign_entitlement,
          privilege: create(:privilege, organization: other_organization, feature: foreign_feature, code: "max", value_type: "integer"),
          value: "50"
        )
      end

      before { foreign_value }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(foreign_value.reload).to have_attributes(value: "50", deleted_at: nil)
      end

      include_examples "a refused value remove"
    end

    context "with a legacy plan code" do
      let(:plan_code) { "legacy" }
      let(:legacy_entitlement) { create(:entitlement, organization:, plan: create(:plan, organization:, code: "legacy"), feature:) }
      let(:legacy_value) { create(:entitlement_value, organization:, entitlement: legacy_entitlement, privilege:, value: "20") }

      before { legacy_value }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
        expect(legacy_value.reload).to have_attributes(value: "20", deleted_at: nil)
      end

      include_examples "a refused value remove"
    end

    context "with a deleted catalog plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium", deleted_at: Time.current) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end

      include_examples "a refused value remove"
    end

    context "without the product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end

      include_examples "a refused value remove"
    end
  end

  # The v2 render of a plan entitlement, with its datetimes to the microsecond as native v2 renders them.
  def plan_entitlement_json(entitlement, values)
    entitlement = Entitlement::Entitlement.with_discarded.find(entitlement.id)

    {
      lago_id: entitlement.id,
      plan_code: entitlement.catalog_plan&.code,
      feature_code: entitlement.feature.code,
      values:,
      created_at: entitlement.created_at.iso8601(6),
      updated_at: entitlement.updated_at.iso8601(6),
      deleted_at: entitlement.deleted_at&.iso8601(6)
    }
  end
end
