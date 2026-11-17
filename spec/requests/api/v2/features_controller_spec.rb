# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::FeaturesController do
  let(:organization) { create(:organization) }

  describe "GET /api/v2/features" do
    subject { get_with_token(organization, "/api/v2/features", params) }

    let(:params) { {} }
    let(:older) do
      create(
        :feature,
        organization:,
        code: "seats",
        name: "Seats",
        description: "Number of seats",
        created_at: Time.zone.parse("2026-10-01T08:30:00.123456Z"),
        updated_at: Time.zone.parse("2026-10-02T09:00:00.654321Z")
      )
    end
    let(:newer) do
      create(
        :feature,
        organization:,
        code: "storage",
        name: "Storage",
        description: nil,
        created_at: Time.zone.parse("2026-10-05T10:00:00.000001Z"),
        updated_at: Time.zone.parse("2026-10-05T10:00:00.000001Z")
      )
    end

    before do
      older
      newer
    end

    include_examples "requires API permission", "feature", "read"

    it "returns the v2 features, newest first" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:features]).to eq([
        {
          lago_id: newer.id,
          code: "storage",
          name: "Storage",
          description: nil,
          created_at: "2026-10-05T10:00:00.000001Z",
          updated_at: "2026-10-05T10:00:00.000001Z",
          deleted_at: nil
        },
        {
          lago_id: older.id,
          code: "seats",
          name: "Seats",
          description: "Number of seats",
          created_at: "2026-10-01T08:30:00.123456Z",
          updated_at: "2026-10-02T09:00:00.654321Z",
          deleted_at: nil
        }
      ])
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "when a feature has privileges" do
      before { create(:privilege, feature: older, organization:) }

      it "does not render the privileges" do
        subject

        expect(json[:features].map { it.keys }).to all(eq(%i[lago_id code name description created_at updated_at deleted_at]))
      end
    end

    context "with a discarded feature and a feature of another organization" do
      let(:discarded) { create(:feature, organization:, deleted_at: Time.current) }
      let(:other) { create(:feature) }

      before do
        discarded
        other
      end

      it "lists neither" do
        subject

        expect(json[:features].map { it[:lago_id] }).to eq([newer.id, older.id])
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :features, model: Entitlement::Feature do
      let(:paginated_path) { "/api/v2/features" }
      let(:create_paginated_record) { ->(created_at) { create(:feature, organization:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :features do
      let(:filtered_path) { "/api/v2/features" }
      let(:create_filtered_record) { ->(created_at) { create(:feature, organization:, created_at:) } }
    end

    context "with a search term" do
      let(:by_code) { create(:feature, organization:, code: "match_code", name: "A", description: "A") }
      let(:by_name) { create(:feature, organization:, code: "b", name: "Match name", description: "B") }
      let(:by_description) { create(:feature, organization:, code: "c", name: "C", description: "has match inside") }
      let(:params) { {search_term: "match"} }

      before do
        by_code
        by_name
        by_description
      end

      it "returns the features whose code, name or description matches" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:features].map { it[:lago_id] }).to match_array([by_code.id, by_name.id, by_description.id])
      end
    end

    context "with a limit of 1" do
      let(:params) { {limit: 1} }

      it "walks the list forward and backward" do
        subject
        expect(json[:features].map { it[:lago_id] }).to eq([newer.id])
        expect(json[:meta][:prev_cursor]).to be_nil

        get_with_token(organization, "/api/v2/features", limit: 1, after: json[:meta][:next_cursor])
        expect(json[:features].map { it[:lago_id] }).to eq([older.id])
        expect(json[:meta][:next_cursor]).to be_nil

        get_with_token(organization, "/api/v2/features", limit: 1, before: json[:meta][:prev_cursor])
        expect(json[:features].map { it[:lago_id] }).to eq([newer.id])
      end
    end

    context "with include_total_count" do
      let(:params) { {limit: 1, include_total_count: true} }

      it "returns the total count" do
        subject

        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "with an invalid cursor" do
      let(:params) { {after: "not-a-cursor!"} }

      it "returns a bad request" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_pagination_cursor")
      end
    end

    context "with an invalid created_at bound" do
      let(:params) { {created_at_from: "not-a-date"} }

      it "returns an invalid_date validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:details]).to eq([{code: "invalid_date", field: "created_at_from", meta: {}}])
      end
    end

    context "with page pagination parameters" do
      let(:params) { {page: 1, per_page: 20} }

      it "rejects them as replaced by the cursor" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:details]).to eq([
          {code: "replaced_by_cursor", field: "page", meta: {}},
          {code: "replaced_by_cursor", field: "per_page", meta: {}}
        ])
      end
    end

    context "with expands[]=privileges" do
      let(:params) { {expands: ["privileges"]} }

      it "rejects the expansion, only the show action expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:details]).to eq([{code: "action_not_expandable", field: "expands", meta: {invalid_values: ["privileges"]}}])
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature unavailable" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v2/features/:code" do
    subject { get_with_token(organization, "/api/v2/features/#{code}", params) }

    let(:params) { {} }
    let(:code) { "sso" }
    let(:feature) do
      create(
        :feature,
        organization:,
        code: "sso",
        name: "SSO",
        description: "Single sign-on",
        created_at: Time.zone.parse("2026-10-01T08:30:00.123456Z"),
        updated_at: Time.zone.parse("2026-10-02T09:00:00.654321Z")
      )
    end

    let(:privileges) { [create(:privilege, feature:, organization:, code: "provider", value_type: "string")] }

    before do
      feature
      privileges
    end

    include_examples "requires API permission", "feature", "read"

    it "returns the v2 feature without its privileges" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:feature]).to eq(
        lago_id: feature.id,
        code: "sso",
        name: "SSO",
        description: "Single sign-on",
        created_at: "2026-10-01T08:30:00.123456Z",
        updated_at: "2026-10-02T09:00:00.654321Z",
        deleted_at: nil
      )
      expect(json[:feature]).not_to have_key(:privileges)
    end

    context "with expands[]=privileges", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      let(:params) { {expands: ["privileges"]} }
      let(:base_time) { Time.zone.parse("2026-10-03T10:00:00.000001Z") }

      # Created out of order, and two of them at the same instant with ids against their insertion
      # order, so only created_at (newest first) then id gives this list.
      let(:select_privilege) do
        create(:privilege, feature:, organization:, code: "provider", name: "Provider", value_type: "select",
          config: {"select_options" => %w[okta google]}, created_at: base_time + 3.hours, updated_at: base_time + 4.hours)
      end
      let(:boolean_privilege) do
        create(:privilege, feature:, organization:, id: "ffffffff-0000-4000-8000-000000000002", code: "enforced",
          name: "Enforced", value_type: "boolean", created_at: base_time + 2.hours, updated_at: base_time + 2.hours)
      end
      let(:string_privilege) do
        create(:privilege, feature:, organization:, id: "00000000-0000-4000-8000-000000000001", code: "domain",
          name: nil, value_type: "string", created_at: base_time + 2.hours, updated_at: base_time + 2.hours)
      end
      let(:integer_privilege) do
        create(:privilege, feature:, organization:, code: "max_admins", name: "Max admins", value_type: "integer",
          created_at: base_time, updated_at: base_time)
      end

      let(:deleted_privilege) do
        create(:privilege, feature:, organization:, code: "legacy", deleted_at: Time.current, created_at: base_time - 1.day)
      end
      let(:other_privilege) do
        create(:privilege, feature: create(:feature, organization:, code: "other"), organization:, code: "other_priv")
      end
      let(:privileges) do
        [select_privilege, boolean_privilege, string_privilege, integer_privilege, deleted_privilege, other_privilege]
      end

      it "embeds the live privileges newest first, then by id" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:feature]).to eq(
          lago_id: feature.id,
          code: "sso",
          name: "SSO",
          description: "Single sign-on",
          created_at: "2026-10-01T08:30:00.123456Z",
          updated_at: "2026-10-02T09:00:00.654321Z",
          deleted_at: nil,
          privileges: [
            {
              lago_id: select_privilege.id,
              feature_code: "sso",
              code: "provider",
              name: "Provider",
              value_type: "select",
              select_options: %w[okta google],
              created_at: "2026-10-03T13:00:00.000001Z",
              updated_at: "2026-10-03T14:00:00.000001Z",
              deleted_at: nil
            },
            {
              lago_id: "00000000-0000-4000-8000-000000000001",
              feature_code: "sso",
              code: "domain",
              name: nil,
              value_type: "string",
              select_options: nil,
              created_at: "2026-10-03T12:00:00.000001Z",
              updated_at: "2026-10-03T12:00:00.000001Z",
              deleted_at: nil
            },
            {
              lago_id: "ffffffff-0000-4000-8000-000000000002",
              feature_code: "sso",
              code: "enforced",
              name: "Enforced",
              value_type: "boolean",
              select_options: nil,
              created_at: "2026-10-03T12:00:00.000001Z",
              updated_at: "2026-10-03T12:00:00.000001Z",
              deleted_at: nil
            },
            {
              lago_id: integer_privilege.id,
              feature_code: "sso",
              code: "max_admins",
              name: "Max admins",
              value_type: "integer",
              select_options: nil,
              created_at: "2026-10-03T10:00:00.000001Z",
              updated_at: "2026-10-03T10:00:00.000001Z",
              deleted_at: nil
            }
          ]
        )
      end
    end

    context "with expands[]=privileges on a feature without privileges" do
      let(:params) { {expands: ["privileges"]} }
      let(:privileges) { [] }

      it "renders an empty list" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:feature][:privileges]).to eq([])
      end
    end

    context "with an unknown expansion" do
      let(:params) { {expands: ["foo"]} }

      it "returns an invalid_expand error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "invalid_expand",
          details: [
            {code: "invalid_expand", field: "expands", meta: {invalid_values: ["foo"], allowed_values: ["privileges"]}}
          ]
        )
      end
    end

    context "when the feature does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature belongs to another organization" do
      let(:code) { "other_sso" }

      before { create(:feature, organization: create(:organization), code: "other_sso") }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "when the feature is deleted" do
      let(:feature) { create(:feature, organization:, code: "sso", deleted_at: Time.current) }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("feature")
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature unavailable" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "POST /api/v2/features" do
    subject(:request) { post_with_token(organization, "/api/v2/features", params) }

    let(:feature_params) { {code: "seats", name: "Seats", description: "Number of seats"} }
    let(:params) { {feature: feature_params} }

    include_examples "requires API permission", "feature", "write"

    it "creates a feature without privileges and renders the v2 body" do
      travel_to(Time.zone.parse("2026-11-14T10:00:00.123456Z"), with_usec: true) do
        expect { request }
          .to change(organization.features, :count).by(1)
          .and not_change(Entitlement::Privilege, :count)
          .and have_enqueued_job_after_commit(SendWebhookJob).with("feature.created", instance_of(Entitlement::Feature)) # exactly once by default
      end

      feature = organization.features.sole
      expect(response).to have_http_status(:success)
      expect(json[:feature]).to eq(
        lago_id: feature.id,
        code: "seats",
        name: "Seats",
        description: "Number of seats",
        created_at: "2026-11-14T10:00:00.123456Z",
        updated_at: "2026-11-14T10:00:00.123456Z",
        deleted_at: nil
      )
      expect(Utils::ActivityLog).to have_produced("feature.created").after_commit.with(feature)
    end

    context "with privileges in the body" do
      let(:feature_params) { super().merge(privileges: [{code: "max", value_type: "integer"}]) }

      it "ignores them and creates the feature without privileges" do
        expect { request }
          .to change(organization.features, :count).by(1)
          .and not_change(Entitlement::Privilege, :count)

        expect(response).to have_http_status(:success)
        expect(json[:feature]).not_to have_key(:privileges)
      end
    end

    context "when the feature root is missing" do
      let(:params) { feature_params }

      it "returns the v2 missing parameter error" do
        expect { request }.not_to change(Entitlement::Feature, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "feature", meta: {}}])
      end
    end

    context "when the feature root is a string" do
      let(:params) { {feature: "seats"} }

      it "returns the v2 missing parameter error" do
        expect { request }.not_to change(Entitlement::Feature, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "feature", meta: {}}])
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, code|
      context "with code as #{label}" do
        let(:feature_params) { super().merge(code:) }

        it "returns value_is_invalid on code and creates nothing" do
          expect { request }.not_to change(Entitlement::Feature, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "code", meta: {}}])
        end
      end
    end

    context "with a blank code" do
      let(:feature_params) { super().merge(code: "") }

      it "returns a validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "code", meta: {}}])
      end
    end

    context "when the code is already used in the organization" do
      before { create(:feature, organization:, code: "seats") }

      it "returns a validation error" do
        expect { request }.not_to change(Entitlement::Feature, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "code", meta: {}}])
      end
    end

    context "when the code is used by another organization" do
      before { create(:feature, organization: create(:organization), code: "seats") }

      it "creates the feature" do
        expect { request }.to change(organization.features, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:feature][:code]).to eq("seats")
      end
    end

    context "with keys that are not permitted" do
      let(:posted_id) { SecureRandom.uuid }
      let(:feature_params) { super().merge(lago_id: posted_id, id: posted_id, foo: "bar") }

      it "ignores them and creates the feature" do
        expect { request }.to change(organization.features, :count).by(1)

        feature = organization.features.sole
        expect(response).to have_http_status(:success)
        expect(feature.id).not_to eq(posted_id)
        expect(json[:feature]).to eq(
          lago_id: feature.id,
          code: "seats",
          name: "Seats",
          description: "Number of seats",
          created_at: feature.created_at.iso8601(6),
          updated_at: feature.updated_at.iso8601(6),
          deleted_at: nil
        )
      end
    end

    context "with a code and a name over 255 characters" do
      let(:feature_params) { super().merge(code: "a" * 256, name: "b" * 256) }

      it "returns a validation error with the maximum length" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [
            {code: "value_is_too_long", field: "code", meta: {max_length: 255}},
            {code: "value_is_too_long", field: "name", meta: {max_length: 255}}
          ]
        )
      end
    end

    context "with a description over 600 characters" do
      let(:feature_params) { super().merge(description: "c" * 601) }

      it "returns a validation error with the maximum length" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_too_long", field: "description", meta: {max_length: 600}}]
        )
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature unavailable" do
        expect { request }.not_to change(Entitlement::Feature, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
