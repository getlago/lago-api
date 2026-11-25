# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Plans::MetadataController do
  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: ["product_catalog"]) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "growth") }
  let(:stored_metadata) { nil }
  let(:path) { "/api/v2/plans/#{plan_code}/metadata" }
  let(:plan_code) { catalog_plan.code }

  before do
    catalog_plan
    create(:item_metadata, owner: catalog_plan, organization:, value: stored_metadata) if stored_metadata
  end

  shared_examples "a plan metadata write" do |webhook_metadata|
    it "moves updated_at, sends one plan.updated carrying the new metadata and logs one activity", versioning: true do
      travel_to(1.hour.from_now) do
        expect { request }
          .to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", catalog_plan)
        expect(response).to have_http_status(:success)
        expect(catalog_plan.reload.updated_at).to be_within(1.second).of(Time.current)
      end

      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(catalog_plan)
      expect(catalog_plan.reload.metadata&.value).to eq(webhook_metadata)
      expect(json[:metadata]&.deep_stringify_keys).to eq(webhook_metadata)
    end

    it "adds one version", versioning: true do
      expect { request }.to change { catalog_plan.versions.count }.by(1)
    end
  end

  shared_examples "a plan metadata no-op" do
    it "answers with the stored value and does nothing else", versioning: true do
      expected = catalog_plan.metadata&.value
      updated_at = catalog_plan.updated_at
      versions = catalog_plan.versions.count

      travel_to(1.hour.from_now) do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)
      end

      expect(response).to have_http_status(:success)
      expect(json[:metadata]&.deep_stringify_keys).to eq(expected)
      expect(catalog_plan.reload.updated_at).to eq(updated_at)
      expect(catalog_plan.versions.count).to eq(versions)
      expect(Utils::ActivityLog).not_to have_produced("plan.updated")
    end
  end

  shared_examples "a plan metadata route" do
    context "when the plan is unknown" do
      let(:plan_code) { "unknown" }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "when the plan is discarded" do
      before { catalog_plan.discard! }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "when the plan belongs to another organization" do
      let(:plan_code) { create(:catalog_plan, organization: create(:organization), code: "foreign").code }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "when a legacy plan has the same code" do
      let(:legacy_plan) { create(:plan, organization:, code: catalog_plan.code) }

      before { legacy_plan }

      it "never touches the legacy plan" do
        request

        expect(legacy_plan.reload.metadata).to be_nil
        expect(legacy_plan.updated_at).to eq(legacy_plan.created_at)
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "growth") }

      it "returns a forbidden error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "POST /api/v2/plans/:code/metadata" do
    subject(:request) { post_with_token(organization, path, request_params) }

    let(:request_params) { {metadata: {crm_id: "123"}} }

    include_examples "requires API permission", "plan", "write"
    it_behaves_like "a plan metadata route"

    context "when the plan has metadata" do
      let(:stored_metadata) { {"old" => "value"} }

      it "replaces it" do
        request

        expect(response).to have_http_status(:success)
        expect(json).to eq(metadata: {crm_id: "123"})
        expect(catalog_plan.reload.metadata.value).to eq("crm_id" => "123")
      end

      it_behaves_like "a plan metadata write", {"crm_id" => "123"}
    end

    context "when the plan has no metadata" do
      it "creates it" do
        request

        expect(json).to eq(metadata: {crm_id: "123"})
      end
    end

    context "when metadata is omitted" do
      let(:request_params) { {} }
      let(:stored_metadata) { {"old" => "value"} }

      it "stores an empty one" do
        request

        expect(json).to eq(metadata: {})
        expect(catalog_plan.reload.metadata.value).to eq({})
      end
    end

    context "when metadata is null" do
      let(:request_params) { {metadata: nil} }
      let(:stored_metadata) { {"old" => "value"} }

      it "returns a 400 on metadata and keeps the stored value" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:details].first).to include(code: "value_is_invalid", field: "metadata")
        expect(catalog_plan.reload.metadata.value).to eq("old" => "value")
      end
    end

    context "when the value is already stored" do
      let(:stored_metadata) { {"crm_id" => "123"} }

      it_behaves_like "a plan metadata no-op"
    end

    context "when a catalog plan and a legacy plan share the code" do
      let(:legacy_plan) { create(:plan, organization:, code: catalog_plan.code) }

      before { legacy_plan }

      it "writes only the catalog plan" do
        request

        expect(catalog_plan.reload.metadata.value).to eq("crm_id" => "123")
        expect(legacy_plan.reload.metadata).to be_nil
      end
    end

    [
      ["a string", "abc"],
      ["an array", %w[abc]]
    ].each do |description, value|
      context "when metadata is #{description}" do
        let(:request_params) { {metadata: value} }
        let(:stored_metadata) { {"old" => "value"} }

        it "returns a 400 on metadata and writes nothing" do
          expect { request }.not_to have_enqueued_job(SendWebhookJob)

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("value_is_invalid")
          expect(json[:details].first).to include(code: "value_is_invalid", field: "metadata")
          expect(catalog_plan.reload.metadata.value).to eq("old" => "value")
        end
      end
    end

    {
      "51 keys" => Array.new(51) { ["key_#{it}", "v"] }.to_h,
      "a 256-character value" => {"key" => "v" * 256},
      "a 101-character key" => {("k" * 101) => "v"},
      "a number" => {"key" => 1},
      "a nested value" => {"key" => {"nested" => "v"}}
    }.each do |description, value|
      context "when metadata holds #{description}" do
        let(:request_params) { {metadata: value} }
        let(:stored_metadata) { {"old" => "value"} }

        it "returns a 422 on metadata and writes nothing" do
          expect { request }.not_to have_enqueued_job(SendWebhookJob)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:details].first).to include(code: "value_is_invalid", field: "metadata")
          expect(catalog_plan.reload.metadata.value).to eq("old" => "value")
        end
      end
    end
  end

  %i[patch put].each do |verb|
    describe "#{verb.upcase} /api/v2/plans/:code/metadata" do
      subject(:request) { public_send(:"#{verb}_with_token", organization, path, request_params) }

      let(:request_params) { {metadata: {tier: "gold"}} }
      let(:stored_metadata) { {"crm_id" => "123"} }

      include_examples "requires API permission", "plan", "write"
      it_behaves_like "a plan metadata route"
      it_behaves_like "a plan metadata write", {"crm_id" => "123", "tier" => "gold"}

      it "merges the keys" do
        request

        expect(json).to eq(metadata: {crm_id: "123", tier: "gold"})
      end

      context "when a key is sent as null" do
        let(:request_params) { {metadata: {tier: nil}} }

        it "keeps it with a null value" do
          request

          expect(json).to eq(metadata: {crm_id: "123", tier: nil})
        end
      end

      context "when metadata is empty and the plan has none" do
        let(:request_params) { {metadata: {}} }
        let(:stored_metadata) { nil }

        it "returns null and stores nothing" do
          request

          expect(response).to have_http_status(:success)
          expect(json).to eq(metadata: nil)
          expect(catalog_plan.reload.metadata).to be_nil
        end
      end

      context "when metadata is a string" do
        let(:request_params) { {metadata: "abc"} }

        it "returns a 400 on metadata" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json[:details].first).to include(code: "value_is_invalid", field: "metadata")
          expect(catalog_plan.reload.metadata.value).to eq("crm_id" => "123")
        end
      end

      context "when the value is already stored" do
        let(:request_params) { {metadata: {crm_id: "123"}} }

        it_behaves_like "a plan metadata no-op"
      end

      context "when metadata is empty" do
        let(:request_params) { {metadata: {}} }

        it_behaves_like "a plan metadata no-op"
      end

      it "sends a plan.updated carrying the merged metadata" do
        perform_enqueued_jobs(only: SendWebhookJob) { request }

        expect(Webhook.where(webhook_type: "plan.updated").sole.payload.dig("plan", "metadata"))
          .to eq("crm_id" => "123", "tier" => "gold")
      end

      context "when the merge reaches exactly 50 keys" do
        let(:stored_metadata) { Array.new(49) { ["key_#{it}", "v"] }.to_h }

        it "answers 200" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:metadata].size).to eq(50)
        end
      end

      context "when it overwrites a key while at 50" do
        let(:stored_metadata) { Array.new(50) { ["key_#{it}", "v"] }.to_h }
        let(:request_params) { {metadata: {key_0: "new"}} }

        it "answers 200" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:metadata][:key_0]).to eq("new")
          expect(json[:metadata].size).to eq(50)
        end
      end

      context "when the merge goes over 50 keys" do
        let(:stored_metadata) { Array.new(50) { ["key_#{it}", "v"] }.to_h }

        it "returns a 422 and writes nothing" do
          request

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:details].first).to include(code: "value_is_invalid", field: "metadata")
          expect(catalog_plan.reload.metadata.value.size).to eq(50)
        end
      end
    end
  end

  describe "DELETE /api/v2/plans/:code/metadata" do
    subject(:request) { delete_with_token(organization, path) }

    let(:stored_metadata) { {"crm_id" => "123"} }

    include_examples "requires API permission", "plan", "write"
    it_behaves_like "a plan metadata route"
    it_behaves_like "a plan metadata write", nil

    it "removes the row" do
      request

      expect(json).to eq(metadata: nil)
      expect(Metadata::ItemMetadata.where(owner: catalog_plan)).to be_empty
    end

    context "when the plan has no metadata" do
      let(:stored_metadata) { nil }

      it_behaves_like "a plan metadata no-op"
    end
  end

  describe "DELETE /api/v2/plans/:code/metadata/:key" do
    subject(:request) { delete_with_token(organization, "#{path}/#{key}") }

    let(:key) { "crm_id" }
    let(:stored_metadata) { {"crm_id" => "123", "tier" => "gold"} }

    include_examples "requires API permission", "plan", "write"
    it_behaves_like "a plan metadata route"
    it_behaves_like "a plan metadata write", {"tier" => "gold"}

    it "removes the key" do
      request

      expect(json).to eq(metadata: {tier: "gold"})
    end

    context "when the key is unknown" do
      let(:key) { "missing" }

      it_behaves_like "a plan metadata no-op"

      it "answers 200 with the stored value" do
        request

        expect(json).to eq(metadata: {crm_id: "123", tier: "gold"})
      end
    end

    context "when the key is the last one" do
      let(:stored_metadata) { {"crm_id" => "123"} }

      it "keeps the row with an empty value" do
        request

        expect(json).to eq(metadata: {})
        expect(catalog_plan.reload.metadata.value).to eq({})
      end
    end

    context "when the key contains a dot" do
      let(:key) { "app.version" }
      let(:stored_metadata) { {"app" => "x", "app.version" => "1"} }

      it "removes that key only" do
        request

        expect(json).to eq(metadata: {app: "x"})
      end
    end

    context "when the plan has no metadata" do
      let(:stored_metadata) { nil }

      it "returns a metadata not found and sends nothing" do
        expect { request }.not_to have_enqueued_job(SendWebhookJob)

        expect(response).to be_v2_not_found_error("metadata")
        expect(Utils::ActivityLog).not_to have_produced("plan.updated")
      end
    end
  end
end
