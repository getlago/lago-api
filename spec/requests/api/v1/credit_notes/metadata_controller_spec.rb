# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::CreditNotes::MetadataController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:credit_note) { create(:credit_note, customer:) }

  describe "POST /api/v1/credit_notes/:id/metadata" do
    subject { post_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/metadata", {metadata: params}) }

    let(:credit_note_id) { credit_note.id }
    let(:params) { {foo: "bar", baz: "qux"} }

    it_behaves_like "requires API permission", "credit_note", "write"

    context "when credit note is not found" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("credit_note")
      end
    end

    context "when credit note is draft" do
      let(:credit_note) { create(:credit_note, :draft, customer:) }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("credit_note")
      end
    end

    context "when credit note has no metadata" do
      it "creates metadata" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq(foo: "bar", baz: "qux")
        expect(credit_note.reload.metadata.value).to eq("foo" => "bar", "baz" => "qux")
      end
    end

    context "when credit note has existing metadata" do
      before do
        metadata = create(:item_metadata, owner: credit_note, organization:, value: {old: "value", foo: "old"})
        credit_note.update!(metadata_id: metadata.id)
      end

      it "replaces all metadata" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq(foo: "bar", baz: "qux")
        expect(credit_note.reload.metadata.value).to eq("foo" => "bar", "baz" => "qux")
      end
    end

    context "when params are empty" do
      let(:params) { {} }

      before do
        metadata = create(:item_metadata, owner: credit_note, organization:, value: {old: "value"})
        credit_note.update!(metadata_id: metadata.id)
      end

      it "replaces metadata with empty hash" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq({})
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end

    context "when params are empty and metadata does not exist" do
      let(:params) { {} }

      it "creates metadata with empty hash" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq({})
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end

    context "when metadata param is not provided" do
      subject { post_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/metadata", {}) }

      it "creates metadata with empty hash" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:metadata]).to eq({})
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end
  end
end
