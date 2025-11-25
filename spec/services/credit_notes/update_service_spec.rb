# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::UpdateService do
  subject(:credit_note_service) { described_class.new(credit_note:, **params) }

  let(:credit_note) { create(:credit_note) }

  let(:params) do
    {refund_status: "succeeded"}
  end

  it "updates the credit note status" do
    result = credit_note_service.call

    aggregate_failures do
      expect(result).to be_success
      expect(result.credit_note.refund_status).to eq("succeeded")
      expect(result.credit_note.refunded_at).to be_present
    end
  end

  it "call SegmentTrackJob" do
    allow(SegmentTrackJob).to receive(:perform_later)

    credit_note_service.call

    expect(SegmentTrackJob).to have_received(:perform_later).with(
      membership_id: CurrentContext.membership,
      event: "refund_status_changed",
      properties: {
        organization_id: credit_note.organization.id,
        credit_note_id: credit_note.id,
        refund_status: "succeeded"
      }
    )
  end

  context "with invalid refund status" do
    let(:params) do
      {refund_status: "foo_bar"}
    end

    it "returns an error" do
      result = credit_note_service.call

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:refund_status)
        expect(result.error.messages[:refund_status]).to include("value_is_invalid")
      end
    end
  end

  context "when credit_note is draft" do
    let(:credit_note) { create(:credit_note, :draft) }

    it "returns a failure" do
      result = credit_note_service.call

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("credit_note_not_found")
      end
    end
  end

  describe "metadata" do
    context "with metadata not passed" do
      let(:params) { {refund_status: "succeeded"} }

      it "does not change metadata" do
        expect { credit_note_service.call }.not_to change(Metadata::ItemMetadata, :count)
      end
    end

    context "with metadata not passed, existing metadata" do
      let(:params) { {refund_status: "succeeded"} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "value"}) }

      it "removes existing metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata).to be_nil
      end
    end

    context "with metadata: nil" do
      let(:params) { {metadata: nil} }

      it "does not create metadata" do
        expect { credit_note_service.call }.not_to change(Metadata::ItemMetadata, :count)
      end
    end

    context "with metadata: nil, existing metadata" do
      let(:params) { {metadata: nil} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "value"}) }

      it "removes existing metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata).to be_nil
      end
    end

    context "with metadata: nil, partial_metadata: false, existing metadata" do
      let(:params) { {metadata: nil, partial_metadata: false} }
      let(:organization) { credit_note.organization }
      let!(:existing_metadata) do
        create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "value"})
      end

      it "removes existing metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata).to be_nil
        expect(Metadata::ItemMetadata.find_by(id: existing_metadata.id)).to be_nil
      end
    end

    context "with metadata: {}" do
      let(:params) { {metadata: {}} }

      it "creates metadata with empty value" do
        expect { credit_note_service.call }.to change(Metadata::ItemMetadata, :count).by(1)
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end

    context "with metadata: {}, existing metadata" do
      let(:params) { {metadata: {}} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "value"}) }

      it "replaces metadata with {}" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end

    context "with metadata: {}, partial_metadata: false, existing metadata" do
      let(:params) { {metadata: {}, partial_metadata: false} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "value"}) }

      it "sets metadata to {}" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({})
      end
    end

    context "with metadata values" do
      let(:params) { {metadata: {"key1" => "value1", "key2" => "value2"}} }

      it "creates metadata" do
        expect { credit_note_service.call }.to change(Metadata::ItemMetadata, :count).by(1)
        expect(credit_note.reload.metadata.value).to eq({"key1" => "value1", "key2" => "value2"})
      end
    end

    context "with metadata values, existing metadata" do
      let(:params) { {metadata: {"key1" => "value1", "key2" => "value2"}} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "old"}) }

      it "replaces metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => "value1", "key2" => "value2"})
      end
    end

    context "with metadata values, partial_metadata: false, existing metadata" do
      let(:params) { {metadata: {"key1" => "value1"}, partial_metadata: false} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "old"}) }

      it "replaces metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => "value1"})
      end
    end

    context "with metadata values, partial_metadata: true, existing metadata" do
      let(:params) { {metadata: {"key1" => "value1"}, partial_metadata: true} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "old"}) }

      it "merges metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"existing" => "old", "key1" => "value1"})
      end
    end

    context "with metadata overwriting existing key" do
      let(:params) { {metadata: {"existing" => "new"}} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"existing" => "old"}) }

      it "overwrites the key" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"existing" => "new"})
      end
    end

    context "with metadata: {key: nil}" do
      let(:params) { {metadata: {"key1" => nil}} }

      it "creates metadata with nil value" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => nil})
      end
    end

    context "with metadata: {key: nil}, existing metadata" do
      let(:params) { {metadata: {"key1" => nil}} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"key1" => "old_value"}) }

      it "sets key to nil" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => nil})
      end
    end

    context "with metadata: {key: ''}" do
      let(:params) { {metadata: {"key1" => ""}} }

      it "creates metadata with empty string" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => ""})
      end
    end

    context "with metadata: {key: ''}, existing metadata" do
      let(:params) { {metadata: {"key1" => ""}} }
      let(:organization) { credit_note.organization }

      before { create(:item_metadata, owner: credit_note, organization:, value: {"key1" => "old", "key2" => "keep"}) }

      it "replaces with empty string" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => ""})
      end
    end

    context "with metadata and refund_status" do
      let(:params) { {metadata: {"key1" => "value1"}, refund_status: "succeeded"} }

      it "updates both" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.refund_status).to eq("succeeded")
        expect(credit_note.reload.metadata.value).to eq({"key1" => "value1"})
      end
    end

    context "with ActionController::Parameters" do
      let(:params) { {metadata: ActionController::Parameters.new({"key1" => "value1"})} }

      it "handles ActionController::Parameters" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"key1" => "value1"})
      end
    end
  end
end
