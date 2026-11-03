# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::CreditNotes::MetadataController do
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer, organization:) }
  let(:credit_note) { create(:credit_note, customer:) }

  before { organization.enable_feature_flag!(:product_catalog) }

  describe "POST /api/v2/credit_notes/:id/metadata" do
    subject(:request) { post_with_token(organization, "/api/v2/credit_notes/#{credit_note_id}/metadata", request_params) }

    let(:credit_note_id) { credit_note.id }
    let(:request_params) { {metadata: {foo: "bar"}} }

    it_behaves_like "requires API permission", "credit_note", "write"

    context "when metadata already exists" do
      let(:item_metadata) { create(:item_metadata, owner: credit_note, organization:, value: {old: "value"}) }

      before { item_metadata }

      it "replaces all metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq(foo: "bar")
        expect(credit_note.reload.metadata.value).to eq("foo" => "bar")
      end
    end

    context "when metadata is omitted" do
      let(:request_params) { {} }

      it "creates empty metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq({})
      end
    end

    context "when metadata is empty" do
      let(:request_params) { {metadata: {}} }

      it "creates empty metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq({})
      end
    end

    context "when the credit note is missing" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("credit_note")
      end
    end

    context "when the credit note belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:credit_note_id) { create(:credit_note, customer: other_customer).id }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("credit_note")
      end
    end

    context "when metadata is not an object" do
      let(:request_params) { {metadata: ["invalid"]} }

      it "returns a native v2 invalid request" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to include(
          code: "value_is_invalid",
          details: [{code: "value_is_invalid", field: "metadata", meta: {}}]
        )
      end
    end
  end

  describe "PATCH /api/v2/credit_notes/:id/metadata" do
    subject(:request) { patch_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/metadata", request_params) }

    let(:request_params) { {metadata: {foo: "bar"}} }

    context "when metadata already exists" do
      let(:item_metadata) { create(:item_metadata, owner: credit_note, organization:, value: {old: "value"}) }

      before { item_metadata }

      it "merges metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq(old: "value", foo: "bar")
      end

      context "when metadata is empty" do
        let(:request_params) { {metadata: {}} }

        it "keeps existing metadata unchanged" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:metadata]).to eq(old: "value")
        end
      end
    end

    context "when metadata is omitted" do
      let(:request_params) { {} }

      it "leaves metadata absent" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to be_nil
      end
    end

    context "when metadata is empty and no metadata exists" do
      let(:request_params) { {metadata: {}} }

      it "does not create metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to be_nil
        expect(credit_note.reload.metadata).to be_nil
      end
    end

    context "when metadata is not an object" do
      let(:request_params) { {metadata: "invalid"} }

      it "returns a native v2 invalid request" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:details]).to eq([{code: "value_is_invalid", field: "metadata", meta: {value: "invalid"}}])
      end
    end
  end

  describe "DELETE /api/v2/credit_notes/:id/metadata" do
    subject(:request) { delete_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/metadata") }

    it "returns nil metadata when none exists" do
      request

      expect(response).to have_http_status(:success)
      expect(json[:metadata]).to be_nil
    end

    context "when metadata exists" do
      let(:item_metadata) { create(:item_metadata, owner: credit_note, organization:, value: {foo: "bar"}) }

      before { item_metadata }

      it "deletes all metadata" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to be_nil
        expect(credit_note.reload.metadata).to be_nil
      end
    end
  end

  describe "DELETE /api/v2/credit_notes/:id/metadata/:key" do
    subject(:request) { delete_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/metadata/#{key}") }

    let(:key) { "foo" }

    context "when metadata is missing" do
      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("metadata")
      end
    end

    context "when metadata exists" do
      let(:item_metadata) { create(:item_metadata, owner: credit_note, organization:, value: {foo: "bar", baz: "qux"}) }

      before { item_metadata }

      it "deletes the requested key" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq(baz: "qux")
      end

      context "when the key is missing" do
        let(:key) { "missing" }

        it "keeps metadata unchanged" do
          request

          expect(response).to have_http_status(:success)
          expect(json[:metadata]).to eq(foo: "bar", baz: "qux")
        end
      end
    end

    context "when the credit note is missing" do
      subject(:request) { delete_with_token(organization, "/api/v2/credit_notes/#{SecureRandom.uuid}/metadata/#{key}") }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("credit_note")
      end
    end
  end

  describe "POST /api/v2/credit_notes/:id/download" do
    subject(:request) { post_with_token(organization, "/api/v2/credit_notes/#{SecureRandom.uuid}/download") }

    it "returns a real 404 instead of falling through to v1" do
      request

      expect(response).to have_http_status(:not_found)
    end
  end
end
