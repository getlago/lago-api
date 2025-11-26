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
    let(:organization) { credit_note.organization }

    context "when deleting metadata" do
      let(:params) { {metadata: nil, replace_metadata: true} }
      let!(:existing_metadata) do
        create(:item_metadata, owner: credit_note, organization:, value: {"foo" => "bar"}).tap do |m|
          credit_note.update!(metadata_id: m.id)
          credit_note.reload
        end
      end

      it "removes existing metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata).to be_nil
        expect(Metadata::ItemMetadata.find_by(id: existing_metadata.id)).to be_nil
      end
    end

    context "when creating metadata" do
      let(:params) { {metadata: {"foo" => "bar"}} }

      it "creates metadata" do
        expect { credit_note_service.call }.to change(Metadata::ItemMetadata, :count).by(1)
        expect(credit_note.reload.metadata.value).to eq({"foo" => "bar"})
      end
    end

    context "when replacing metadata" do
      let(:params) { {metadata: {"baz" => "qux"}, replace_metadata: true} }

      before do
        metadata = create(:item_metadata, owner: credit_note, organization:, value: {"foo" => "bar"})
        credit_note.update!(metadata_id: metadata.id)
        credit_note.reload
      end

      it "replaces metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"baz" => "qux"})
      end
    end

    context "when merging metadata" do
      let(:params) { {metadata: {"baz" => "qux"}} }

      before do
        metadata = create(:item_metadata, owner: credit_note, organization:, value: {"foo" => "bar"})
        credit_note.update!(metadata_id: metadata.id)
        credit_note.reload
      end

      it "merges metadata" do
        result = credit_note_service.call

        expect(result).to be_success
        expect(credit_note.reload.metadata.value).to eq({"foo" => "bar", "baz" => "qux"})
      end
    end
  end
end
