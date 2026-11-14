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
      create(:privilege, feature: older, organization:)

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

    it "does not list discarded features nor features of another organization" do
      discarded = create(:feature, organization:, deleted_at: Time.current)
      other = create(:feature)

      subject

      expect(json[:features].map { it[:lago_id] }).to eq([newer.id, older.id])
      expect(json[:features].map { it[:lago_id] }).not_to include(discarded.id, other.id)
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

    [
      ["an empty list", []],
      ["a list", [{code: "max", value_type: "integer"}]],
      ["null", nil]
    ].each do |label, privileges|
      context "with privileges as #{label}" do
        let(:feature_params) { super().merge(privileges:) }

        it "refuses the parameter and writes nothing" do
          expect { request }
            .to not_change(Entitlement::Feature, :count)
            .and not_change(Entitlement::Privilege, :count)
            .and not_have_enqueued_job(SendWebhookJob)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            code: "parameter_not_allowed",
            details: [{code: "parameter_not_allowed", field: "feature.privileges", meta: {}}]
          )
        end
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
