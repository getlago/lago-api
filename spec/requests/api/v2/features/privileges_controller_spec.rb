# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Features::PrivilegesController do
  let(:organization) { create(:organization) }

  describe "POST /api/v2/features/:feature_code/privileges" do
    subject(:request) { post_with_token(organization, "/api/v2/features/#{feature_code}/privileges", params) }

    let(:feature_code) { "seats" }
    let(:privilege_params) { {code: "max_admins", name: "Maximum admins", value_type: "integer"} }
    let(:params) { {privilege: privilege_params} }
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats") }

    before { feature }

    include_examples "requires API permission", "feature", "write"

    shared_examples "a refused create" do |status|
      it "creates nothing and sends no webhook" do
        expect { request }
          .to not_change(Entitlement::Privilege, :count)
          .and not_have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(status)
      end
    end

    [
      ["integer", {value_type: "integer"}, "integer", nil],
      ["string", {value_type: "string"}, "string", nil],
      ["boolean", {value_type: "boolean"}, "boolean", nil],
      ["select", {value_type: "select", select_options: %w[a b]}, "select", %w[a b]],
      ["no value_type", {}, "string", nil]
    ].each do |label, type_params, value_type, select_options|
      context "with #{label}" do
        let(:privilege_params) { {code: "max_admins", name: "Maximum admins"}.merge(type_params) }

        it "creates the privilege, renders the v2 body and sends feature.updated" do
          travel_to(Time.zone.parse("2026-11-14T10:00:00.123456Z"), with_usec: true) do
            expect { request }
              .to change(feature.privileges, :count).by(1)
              .and have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", instance_of(Entitlement::Feature)) # exactly once by default
          end

          privilege = feature.privileges.sole
          expect(response).to have_http_status(:success)
          expect(json[:privilege]).to eq(
            lago_id: privilege.id,
            feature_code: "seats",
            code: "max_admins",
            name: "Maximum admins",
            value_type:,
            select_options:,
            created_at: "2026-11-14T10:00:00.123456Z",
            updated_at: "2026-11-14T10:00:00.123456Z",
            deleted_at: nil
          )
          expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
        end
      end
    end

    context "with unpermitted keys" do
      let(:privilege_params) { {code: "max_admins", value_type: "string", config: {select_options: ["a"]}, lago_id: SecureRandom.uuid} }

      it "ignores them" do
        request

        expect(response).to have_http_status(:success)
        expect(feature.privileges.sole).to have_attributes(code: "max_admins", config: {})
      end
    end

    [
      ["absent", {}],
      ["null", {select_options: nil}],
      ["empty", {select_options: []}],
      ["a string", {select_options: "foo"}],
      ["an object", {select_options: {a: "b"}}],
      ["a list of objects", {select_options: [{a: 1}]}],
      ["a list of numbers", {select_options: [1, 2]}]
    ].each do |label, options_params|
      context "with select and select_options #{label}" do
        let(:privilege_params) { {code: "tier", value_type: "select"}.merge(options_params) }

        include_examples "a refused create", :unprocessable_content

        it "returns invalid_format on select_options" do
          request

          expect(json).to eq(code: "validation_errors", details: [{code: "invalid_format", field: "select_options", meta: {}}])
        end
      end
    end

    context "with select_options on a string privilege" do
      let(:privilege_params) { {code: "tier", value_type: "string", select_options: ["a"]} }

      it "ignores them" do
        expect { request }.to change(feature.privileges, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(value_type: "string", select_options: nil)
      end
    end

    context "when the feature has 49 privileges" do
      before { create_list(:privilege, 49, feature:, organization:) }

      it "accepts the 50th" do
        expect { request }.to change(feature.privileges, :count).from(49).to(50)

        expect(response).to have_http_status(:success)
      end
    end

    context "when the feature has 50 kept privileges" do
      before { create_list(:privilege, 50, feature:, organization:) }

      include_examples "a refused create", :unprocessable_content

      it "returns too_many_privileges with the limit" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code: "too_many_privileges", field: "base", meta: {max_items: 50}}])
      end
    end

    context "when the feature has 49 kept privileges and discarded ones" do
      before do
        create_list(:privilege, 49, feature:, organization:)
        create(:privilege, feature:, organization:, deleted_at: Time.current)
      end

      it "does not count the discarded ones" do
        request

        expect(response).to have_http_status(:success)
      end
    end

    context "when the privilege root is missing" do
      let(:params) { privilege_params }

      include_examples "a refused create", :bad_request

      it "returns the v2 missing parameter error" do
        request

        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "privilege", meta: {}}])
      end
    end

    context "when the privilege root is a string" do
      let(:params) { {privilege: "max_admins"} }

      include_examples "a refused create", :bad_request

      it "returns the v2 missing parameter error" do
        request

        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "privilege", meta: {}}])
      end
    end

    context "with a blank code" do
      let(:privilege_params) { {code: "", value_type: "integer"} }

      include_examples "a refused create", :unprocessable_content

      it "returns value_is_mandatory on code" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "code", meta: {}}])
      end
    end

    context "with a code over 255 characters" do
      let(:privilege_params) { {code: "a" * 256, value_type: "integer"} }

      include_examples "a refused create", :unprocessable_content

      it "returns value_is_too_long on code" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_too_long", field: "code", meta: {max_length: 255}}])
      end
    end

    context "with a name over 255 characters" do
      let(:privilege_params) { {code: "max_admins", name: "a" * 256, value_type: "integer"} }

      include_examples "a refused create", :unprocessable_content

      it "returns value_is_too_long on name" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_too_long", field: "name", meta: {max_length: 255}}])
      end
    end

    context "with a code already used by a kept privilege of the feature" do
      before { create(:privilege, feature:, organization:, code: "max_admins") }

      include_examples "a refused create", :unprocessable_content

      it "returns value_already_exist on code" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "code", meta: {}}])
      end
    end

    context "with a code used on another feature or by a discarded privilege" do
      before do
        create(:privilege, organization:, feature: create(:feature, organization:), code: "max_admins")
        create(:privilege, feature:, organization:, code: "max_admins", deleted_at: Time.current)
      end

      it "creates the privilege" do
        expect { request }.to change(feature.privileges, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end

    [
      ["an unknown value_type", {code: "max_admins", value_type: "float"}, "value_type"],
      ["value_type as a number", {code: "max_admins", value_type: 1}, "value_type"],
      ["value_type as false", {code: "max_admins", value_type: false}, "value_type"]
    ].each do |label, input, field|
      context "with #{label}" do
        let(:privilege_params) { input }

        include_examples "a refused create", :unprocessable_content

        it "returns value_is_invalid on #{field}" do
          request

          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field:, meta: {}}])
        end
      end
    end

    [
      ["value_type as an array", {code: "max_admins", value_type: ["select"]}],
      ["value_type as an object", {code: "max_admins", value_type: {a: 1}}],
      ["name as an object", {code: "max_admins", name: {a: 1}}]
    ].each do |label, input|
      context "with #{label}" do
        let(:privilege_params) { input }

        it "ignores the value and creates a string privilege without a name" do
          expect { request }.to change(feature.privileges, :count).by(1)

          expect(response).to have_http_status(:success)
          expect(feature.privileges.sole).to have_attributes(value_type: "string", name: nil)
        end
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, code|
      context "with code as #{label}" do
        let(:privilege_params) { {code:} }

        include_examples "a refused create", :unprocessable_content

        it "returns value_is_invalid on code" do
          request

          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "code", meta: {}}])
        end
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, name|
      context "with name as #{label}" do
        let(:privilege_params) { {code: "max_admins", name:} }

        include_examples "a refused create", :unprocessable_content

        it "returns value_is_invalid on name" do
          request

          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "name", meta: {}}])
        end
      end
    end

    [["an array", ["max_admins"]], ["an object", {a: 1}]].each do |label, code|
      context "with code as #{label}" do
        let(:privilege_params) { {code:, name: "Maximum admins"} }

        include_examples "a refused create", :unprocessable_content

        it "returns value_is_mandatory on code" do
          request

          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "code", meta: {}}])
        end
      end
    end

    context "when the feature does not exist" do
      let(:feature_code) { "unknown" }

      include_examples "a refused create", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is discarded" do
      let(:feature) { create(:feature, organization:, code: "seats", deleted_at: Time.current) }

      include_examples "a refused create", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature belongs to another organization" do
      let(:feature) { create(:feature, organization: create(:organization), code: "seats") }

      include_examples "a refused create", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "without product catalog", product_catalog: false do
      include_examples "a refused create", :forbidden

      it "returns feature_unavailable" do
        request

        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the feature code contains a slash" do
      let(:feature) { create(:feature, organization:, code: "seats/eu") }
      let(:feature_code) { "seats/eu" }

      it "creates the privilege on that feature" do
        expect { request }.to change(feature.privileges, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:privilege][:feature_code]).to eq("seats/eu")
      end
    end
  end

  describe "GET /api/v2/features/:feature_code/privileges" do
    subject(:request) { get_with_token(organization, "/api/v2/features/#{feature_code}/privileges", params) }

    let(:feature_code) { "seats" }
    let(:params) { {} }
    let(:feature) { create(:feature, organization:, code: "seats") }

    before { feature }

    include_examples "requires API permission", "feature", "read"

    context "with privileges on the feature and on others" do
      let(:newer) do
        create(:privilege, feature:, organization:, code: "tier", name: "Tier", value_type: "select", config: {select_options: %w[a b]},
          created_at: Time.zone.parse("2026-11-14T11:00:00.654321Z"), updated_at: Time.zone.parse("2026-11-14T12:00:00.111111Z"))
      end
      let(:older) do
        create(:privilege, feature:, organization:, code: "max_admins", name: "Maximum admins", value_type: "integer",
          created_at: Time.zone.parse("2026-11-14T10:00:00.123456Z"), updated_at: Time.zone.parse("2026-11-14T10:00:00.123456Z"))
      end

      before do
        newer
        older
        create(:privilege, feature:, organization:, code: "gone", deleted_at: Time.current)
        create(:privilege, organization:, feature: create(:feature, organization:, code: "storage"))
        create(:privilege, feature: create(:feature, organization: create(:organization), code: "seats"))
      end

      it "returns the kept privileges of the feature, newest first, without meta", :bullet do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          privileges: [
            {
              lago_id: newer.id,
              feature_code: "seats",
              code: "tier",
              name: "Tier",
              value_type: "select",
              select_options: %w[a b],
              created_at: "2026-11-14T11:00:00.654321Z",
              updated_at: "2026-11-14T12:00:00.111111Z",
              deleted_at: nil
            },
            {
              lago_id: older.id,
              feature_code: "seats",
              code: "max_admins",
              name: "Maximum admins",
              value_type: "integer",
              select_options: nil,
              created_at: "2026-11-14T10:00:00.123456Z",
              updated_at: "2026-11-14T10:00:00.123456Z",
              deleted_at: nil
            }
          ]
        )
      end
    end

    context "with privileges created at the same time" do
      let(:created_at) { Time.zone.parse("2026-11-14T10:00:00.123456Z") }
      let(:second) { create(:privilege, feature:, organization:, id: "ffffffff-ffff-4fff-bfff-ffffffffffff", created_at:) }
      let(:first) { create(:privilege, feature:, organization:, id: "00000000-0000-4000-8000-000000000000", created_at:) }

      before do
        second
        first
      end

      it "orders them by id" do
        request

        expect(json[:privileges].pluck(:lago_id)).to eq([first.id, second.id])
      end
    end

    context "when the feature has no privileges" do
      it "returns an empty list" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(privileges: [])
      end
    end

    context "with limit" do
      let(:params) { {limit: 1} }

      it "returns not_paginated on limit" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: "limit", meta: {}}])
      end
    end

    context "with every pagination param" do
      let(:params) { {include_total_count: true, before: "x", after: "y", limit: 1, per_page: 10, page: 2} }

      it "returns not_paginated on each of them" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "invalid_pagination_parameter",
          details: %w[page per_page limit after before include_total_count].map { {code: "not_paginated", field: it, meta: {}} }
        )
      end
    end

    context "with a pagination param on an unknown feature" do
      let(:feature_code) { "unknown" }
      let(:params) { {page: 2} }

      it "refuses the param before the lookup" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "invalid_pagination_parameter", details: [{code: "not_paginated", field: "page", meta: {}}])
      end
    end

    context "when the feature does not exist" do
      let(:feature_code) { "unknown" }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is discarded" do
      let(:feature) { create(:feature, organization:, code: "seats", deleted_at: Time.current) }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature belongs to another organization" do
      let(:feature) { create(:feature, organization: create(:organization), code: "seats") }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the feature code contains a slash" do
      let(:feature) { create(:feature, organization:, code: "seats/eu") }
      let(:feature_code) { "seats/eu" }
      let(:privilege) { create(:privilege, feature:, organization:) }

      before { privilege }

      it "lists the privileges of that feature" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privileges]).to contain_exactly(include(lago_id: privilege.id, feature_code: "seats/eu"))
      end
    end
  end

  describe "GET /api/v2/features/:feature_code/privileges/:code" do
    subject(:request) { get_with_token(organization, "/api/v2/features/#{feature_code}/privileges/#{privilege_code}", params) }

    let(:feature_code) { "seats" }
    let(:privilege_code) { "max" }
    let(:params) { {} }
    let(:feature) { create(:feature, organization:, code: "seats") }
    let(:privilege) do
      create(:privilege, feature:, organization:, code: "max", name: "Maximum", value_type: "integer",
        created_at: Time.zone.parse("2026-11-14T10:00:00.123456Z"), updated_at: Time.zone.parse("2026-11-14T11:00:00.654321Z"))
    end

    before { privilege }

    include_examples "requires API permission", "feature", "read"

    it "returns the privilege" do
      request

      expect(response).to have_http_status(:success)
      expect(json).to eq(
        privilege: {
          lago_id: privilege.id,
          feature_code: "seats",
          code: "max",
          name: "Maximum",
          value_type: "integer",
          select_options: nil,
          created_at: "2026-11-14T10:00:00.123456Z",
          updated_at: "2026-11-14T11:00:00.654321Z",
          deleted_at: nil
        }
      )
    end

    context "with a select privilege" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "max", value_type: "select", config: {select_options: %w[a b]}) }

      it "returns its options" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, value_type: "select", select_options: %w[a b])
      end
    end

    context "when the feature code contains a slash" do
      let(:feature) { create(:feature, organization:, code: "seats/eu") }
      let(:feature_code) { "seats/eu" }

      before { create(:privilege, organization:, code: "max", feature: create(:feature, organization:, code: "seats")) }

      it "returns the privilege of that feature" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "seats/eu", code: "max")
      end
    end

    context "when the feature and privilege codes contain percent-encoded slashes" do
      let(:feature) { create(:feature, organization:, code: "seats/eu") }
      let(:privilege) { create(:privilege, feature:, organization:, code: "a/b") }
      let(:feature_code) { "seats%2Feu" }
      let(:privilege_code) { "a%2Fb" }

      it "returns the privilege" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "seats/eu", code: "a/b")
      end
    end

    ["privileges", "eu/privileges"].each do |code|
      context "when the privilege code is #{code}" do
        let(:privilege) { create(:privilege, feature:, organization:, code:) }
        let(:privilege_code) { code }

        it "returns the privilege, not the privileges of a feature coded seats/privileges" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "seats", code:)
        end
      end
    end

    context "when the privilege code contains a slash" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "a/b") }
      let(:privilege_code) { "a/b" }

      it "returns the privilege" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "seats", code: "a/b")
      end
    end

    context "when the feature does not exist" do
      let(:feature_code) { "unknown" }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is discarded" do
      let(:feature) { create(:feature, organization:, code: "seats", deleted_at: Time.current) }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature belongs to another organization" do
      let(:feature) { create(:feature, organization: create(:organization), code: "seats") }
      let(:privilege) { create(:privilege, feature:, code: "max") }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the privilege does not exist" do
      let(:privilege_code) { "unknown" }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege is discarded" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "max", deleted_at: Time.current) }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege belongs to another feature" do
      let(:privilege) { create(:privilege, organization:, code: "max", feature: create(:feature, organization:, code: "storage")) }

      before { feature }

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "with expands" do
      let(:params) { {expands: ["anything"]} }

      it "rejects the expansion" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "expand_not_supported",
          details: [{code: "not_expandable", field: "expands", meta: {invalid_values: ["anything"]}}]
        )
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature_unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "PUT /api/v2/features/:feature_code/privileges/:code" do
    subject(:request) do
      send("#{verb}_with_token", organization, "/api/v2/features/#{feature_code}/privileges/#{privilege_code}", params)
    end

    let(:verb) { :put }
    let(:feature_code) { "sso" }
    let(:privilege_code) { "provider" }
    let(:privilege_params) { {name: "SSO provider", select_options: %w[okta google entra_id onelogin]} }
    let(:params) { {privilege: privilege_params} }
    let(:feature) { create(:feature, organization:, code: "sso", name: "SSO") }
    let(:privilege) do
      travel_to(Time.zone.parse("2026-11-01T08:00:00.654321Z"), with_usec: true) do
        create(:privilege, feature:, organization:, code: "provider", name: "Provider", value_type: "select",
          config: {select_options: %w[okta google entra_id]})
      end
    end

    before { privilege }

    include_examples "requires API permission", "feature", "write"

    shared_examples "a refused update" do |status|
      it "changes nothing and sends no webhook" do
        expect { request }
          .to not_have_enqueued_job(SendWebhookJob)
          .and not_change { privilege.reload.attributes }

        expect(response).to have_http_status(status)
      end
    end

    shared_examples "a refused update on" do |code, field|
      include_examples "a refused update", :unprocessable_content

      it "returns #{code} on #{field}" do
        request

        expect(json).to eq(code: "validation_errors", details: [{code:, field:, meta: {}}])
      end
    end

    %i[put patch].each do |http_verb|
      context "with #{http_verb.upcase}, a new name and an added option" do
        let(:verb) { http_verb }

        it "updates the privilege, renders the v2 body and sends feature.updated" do
          travel_to(Time.zone.parse("2026-11-14T10:00:00.123456Z"), with_usec: true) do
            expect { request }
              .to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature) # exactly once by default
          end

          expect(response).to have_http_status(:success)
          expect(json[:privilege]).to eq(
            lago_id: privilege.id,
            feature_code: "sso",
            code: "provider",
            name: "SSO provider",
            value_type: "select",
            select_options: %w[okta google entra_id onelogin],
            created_at: "2026-11-01T08:00:00.654321Z",
            updated_at: "2026-11-14T10:00:00.123456Z",
            deleted_at: nil
          )
          expect(privilege.reload).to have_attributes(name: "SSO provider", config: {"select_options" => %w[okta google entra_id onelogin]})
          expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
        end
      end

      context "with #{http_verb.upcase} and only the name" do
        let(:verb) { http_verb }
        let(:privilege_params) { {name: "SSO provider"} }

        it "updates the name and keeps the options" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:privilege]).to include(name: "SSO provider", select_options: %w[okta google entra_id])
          expect(privilege.reload).to have_attributes(name: "SSO provider", config: {"select_options" => %w[okta google entra_id]})
        end
      end

      context "with #{http_verb.upcase} and options omitting a current one" do
        let(:verb) { http_verb }
        let(:privilege_params) { {select_options: %w[okta google]} }

        include_examples "a refused update on", "select_option_removal_not_allowed", "select_options"
      end
    end

    context "when plans grant the feature" do
      let(:plan) { create(:plan, organization:) }
      let(:other_plan) { create(:plan, organization:) }

      before do
        create(:entitlement, feature:, organization:, plan:)
        create(:entitlement, feature:, organization:, plan: other_plan)
      end

      it "sends plan.updated once for each plan" do
        expect { request }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan) # exactly once by default

        expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", other_plan).once
        expect(response).to have_http_status(:success)
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(other_plan)
      end

      context "with options omitting a current one" do
        let(:privilege_params) { {select_options: %w[okta google]} }

        it "sends no plan.updated" do
          expect { request }.not_to have_enqueued_job(SendWebhookJob).with("plan.updated", anything)

          expect(response).to have_http_status(:unprocessable_content)
        end
      end
    end

    context "with the same options and name" do
      let(:privilege_params) { {name: "Provider", select_options: %w[okta google entra_id]} }

      it "still sends feature.updated" do
        expect { request }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)

        expect(response).to have_http_status(:success)
      end
    end

    context "with the current code and value_type" do
      let(:privilege_params) { {code: "provider", value_type: "select", name: "SSO provider"} }

      it "accepts them" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(code: "provider", value_type: "select", name: "SSO provider")
      end
    end

    context "with a null name" do
      let(:privilege_params) { {name: nil} }

      it "clears the name" do
        request

        expect(response).to have_http_status(:success)
        expect(privilege.reload.name).to be_nil
      end
    end

    context "with unpermitted keys" do
      let(:privilege_params) { {name: "SSO provider", config: {select_options: ["a"]}, lago_id: SecureRandom.uuid} }

      it "ignores them" do
        request

        expect(response).to have_http_status(:success)
        expect(privilege.reload).to have_attributes(id: privilege.id, config: {"select_options" => %w[okta google entra_id]})
      end
    end

    context "with another code and value_type" do
      let(:privilege_params) { {code: "other", value_type: "string", name: "SSO provider"} }

      it "ignores them and updates the name" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(code: "provider", value_type: "select", name: "SSO provider")
        expect(privilege.reload).to have_attributes(code: "provider", value_type: "select")
      end
    end

    context "with select_options empty on a select privilege" do
      let(:privilege_params) { {select_options: []} }

      include_examples "a refused update on", "select_option_removal_not_allowed", "select_options"
    end

    context "with select_options null on a select privilege" do
      let(:privilege_params) { {name: "SSO provider", select_options: nil} }

      it "ignores them and updates the name" do
        request

        expect(response).to have_http_status(:success)
        expect(privilege.reload).to have_attributes(name: "SSO provider", config: {"select_options" => %w[okta google entra_id]})
      end
    end

    context "with select_options on a string privilege" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "provider", value_type: "string") }
      let(:privilege_params) { {name: "Provider", select_options: ["okta"]} }

      it "ignores them" do
        request

        expect(response).to have_http_status(:success)
        expect(privilege.reload).to have_attributes(name: "Provider", config: {})
      end
    end

    [["a string", "okta"], ["a list of objects", [{a: 1}]]].each do |label, select_options|
      context "with select_options as #{label}" do
        let(:privilege_params) { {name: "SSO provider", select_options:} }

        it "ignores them and updates the name" do
          request

          expect(response).to have_http_status(:success)
          expect(privilege.reload).to have_attributes(name: "SSO provider", config: {"select_options" => %w[okta google entra_id]})
        end
      end
    end

    context "with select_options as a list of numbers" do
      let(:privilege_params) { {select_options: [1, 2]} }

      include_examples "a refused update on", "select_option_removal_not_allowed", "select_options"
    end

    context "with select_options that keep the current ones and add a number" do
      let(:privilege_params) { {select_options: ["okta", "google", "entra_id", 1]} }

      include_examples "a refused update on", "invalid_format", "select_options"
    end

    [["a number", 123], ["a boolean", true]].each do |label, name|
      context "with name as #{label}" do
        let(:privilege_params) { {name:} }

        include_examples "a refused update on", "value_is_invalid", "name"
      end
    end

    context "when the privilege root is missing" do
      let(:params) { privilege_params }

      include_examples "a refused update", :bad_request

      it "returns the v2 missing parameter error" do
        request

        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "privilege", meta: {}}])
      end
    end

    context "when the privilege root is a string" do
      let(:params) { {privilege: "SSO provider"} }

      include_examples "a refused update", :bad_request

      it "returns the v2 missing parameter error" do
        request

        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "privilege", meta: {}}])
      end
    end

    context "when the feature does not exist" do
      let(:feature_code) { "unknown" }

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is discarded" do
      let(:feature) { create(:feature, organization:, code: "sso", deleted_at: Time.current) }
      let(:privilege) do
        create(:privilege, feature:, organization:, code: "provider", value_type: "select", config: {select_options: %w[okta]},
          deleted_at: Time.current)
      end

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature belongs to another organization" do
      let(:feature) { create(:feature, organization: create(:organization), code: "sso") }
      let(:privilege) do
        create(:privilege, feature:, organization: feature.organization, code: "provider", value_type: "select",
          config: {select_options: %w[okta google entra_id]})
      end

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the privilege does not exist" do
      let(:privilege_code) { "unknown" }

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege is discarded" do
      let(:privilege) do
        create(:privilege, feature:, organization:, code: "provider", value_type: "select", config: {select_options: %w[okta]},
          deleted_at: Time.current)
      end

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege belongs to another feature" do
      let(:privilege) do
        create(:privilege, organization:, code: "provider", value_type: "select", config: {select_options: %w[okta]},
          feature: create(:feature, organization:, code: "storage"))
      end

      before { feature }

      include_examples "a refused update", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "without product catalog", product_catalog: false do
      include_examples "a refused update", :forbidden

      it "returns feature_unavailable" do
        request

        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the feature and privilege codes contain a slash" do
      let(:feature) { create(:feature, organization:, code: "sso/eu") }
      let(:feature_code) { "sso/eu" }
      let(:privilege) do
        create(:privilege, feature:, organization:, code: "a/b", value_type: "select", config: {select_options: %w[okta]})
      end
      let(:privilege_code) { "a/b" }
      let(:privilege_params) { {name: "Renamed"} }

      it "updates the privilege of that feature" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "sso/eu", code: "a/b", name: "Renamed")
      end
    end
  end

  describe "DELETE /api/v2/features/:feature_code/privileges/:code" do
    subject(:request) { delete_with_token(organization, "/api/v2/features/#{feature_code}/privileges/#{privilege_code}") }

    let(:feature_code) { "seats" }
    let(:privilege_code) { "max_admins" }
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats") }
    let(:privilege) do
      create(:privilege, feature:, organization:, code: "max_admins", name: "Maximum admins", value_type: "integer",
        created_at: Time.zone.parse("2026-11-14T10:00:00.123456Z"), updated_at: Time.zone.parse("2026-11-14T11:00:00.654321Z"))
    end

    before { privilege }

    include_examples "requires API permission", "feature", "write"

    shared_examples "a refused delete" do |status|
      it "discards nothing and sends no webhook" do
        expect { request }
          .to not_have_enqueued_job(SendWebhookJob)
          .and not_change { privilege.reload.deleted_at }

        expect(response).to have_http_status(status)
        expect(feature.reload).not_to be_discarded
      end
    end

    it "discards the privilege and renders it with the v2 body" do
      travel_to(Time.zone.parse("2026-11-16T10:00:00.123456Z"), with_usec: true) { request }

      expect(response).to have_http_status(:success)
      expect(json).to eq(
        privilege: {
          lago_id: privilege.id,
          feature_code: "seats",
          code: "max_admins",
          name: "Maximum admins",
          value_type: "integer",
          select_options: nil,
          created_at: "2026-11-14T10:00:00.123456Z",
          updated_at: "2026-11-16T10:00:00.123456Z",
          deleted_at: "2026-11-16T10:00:00.123456Z"
        }
      )
      expect(privilege.reload).to be_discarded
      expect(feature.reload).not_to be_discarded
    end

    it "sends feature.updated once" do
      expect { request }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature) # exactly once by default

      expect(response).to have_http_status(:success)
    end

    it "answers the v2 not found error on a later show and a second delete" do
      request
      expect(response).to have_http_status(:success)

      get_with_token(organization, "/api/v2/features/seats/privileges/max_admins")
      expect(response).to be_v2_not_found_error("privilege")

      delete_with_token(organization, "/api/v2/features/seats/privileges/max_admins")
      expect(response).to be_v2_not_found_error("privilege")
    end

    context "when plans and subscriptions grant values of the privilege" do
      let(:plan) { create(:plan, organization:) }
      let(:plan_entitlement) { create(:entitlement, feature:, organization:, plan:) }
      let(:subscription_entitlement) do
        create(:entitlement, :subscription, feature:, organization:, subscription: create(:subscription, organization:))
      end
      let(:other_privilege) { create(:privilege, feature:, organization:, code: "max", value_type: "integer") }
      let(:plan_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege:, organization:, value: "10") }
      let(:subscription_value) do
        create(:entitlement_value, entitlement: subscription_entitlement, privilege:, organization:, value: "20")
      end
      let(:other_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege: other_privilege, organization:, value: "5") }

      before do
        plan_value
        subscription_value
        other_value
      end

      it "discards the values of the privilege only" do
        request

        expect(response).to have_http_status(:success)
        expect(plan_value.reload).to be_discarded
        expect(subscription_value.reload).to be_discarded
        expect(other_value.reload).not_to be_discarded
        expect(other_privilege.reload).not_to be_discarded
        expect(plan_entitlement.reload).not_to be_discarded
      end

      it "sends feature.updated once and plan.updated for the plan" do
        expect { request }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature) # exactly once by default

        expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", plan).once
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
      end
    end

    context "when the feature does not exist" do
      let(:feature_code) { "unknown" }

      include_examples "a refused delete", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is discarded" do
      let(:feature) { create(:feature, organization:, code: "seats", deleted_at: Time.current) }

      it "returns the v2 not found error and leaves the privilege kept" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to be_v2_not_found_error("feature")
        expect(privilege.reload).not_to be_discarded
      end
    end

    context "when the feature belongs to another organization" do
      let(:feature) { create(:feature, organization: create(:organization), code: "seats") }
      let(:privilege) { create(:privilege, feature:, organization: feature.organization, code: "max_admins") }

      include_examples "a refused delete", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the privilege does not exist" do
      let(:privilege_code) { "unknown" }

      include_examples "a refused delete", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege is discarded" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "max_admins", deleted_at: Time.current) }

      include_examples "a refused delete", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the privilege belongs to another feature" do
      let(:privilege) do
        create(:privilege, organization:, code: "max_admins", feature: create(:feature, organization:, code: "storage"))
      end

      before { feature }

      include_examples "a refused delete", :not_found

      it "returns the v2 not found error" do
        request

        expect(response).to be_v2_not_found_error("privilege")
      end
    end

    context "when the destroy service fails" do
      before do
        allow(Entitlement::PrivilegeDestroyService).to receive(:call)
          .and_return(Entitlement::PrivilegeDestroyService::Result.new.not_found_failure!(resource: "privilege"))
      end

      it "renders the failure with the v2 error body" do
        request

        expect(response).to be_v2_not_found_error("privilege")
        expect(privilege.reload).not_to be_discarded
      end
    end

    context "without product catalog", product_catalog: false do
      include_examples "a refused delete", :forbidden

      it "returns feature_unavailable" do
        request

        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the feature and privilege codes contain a slash" do
      let(:feature) { create(:feature, organization:, code: "sso/eu") }
      let(:feature_code) { "sso/eu" }
      let(:privilege) { create(:privilege, feature:, organization:, code: "a/b") }
      let(:privilege_code) { "a/b" }

      before { create(:privilege, organization:, code: "a/b", feature: create(:feature, organization:, code: "sso")) }

      it "discards the privilege of that feature" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:privilege]).to include(lago_id: privilege.id, feature_code: "sso/eu", code: "a/b")
        expect(privilege.reload).to be_discarded
      end
    end
  end
end
