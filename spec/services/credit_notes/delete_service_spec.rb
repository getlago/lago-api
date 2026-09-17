# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::DeleteService do
  subject(:delete_service) { described_class.new(credit_note:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :draft, organization:, customer:) }
  let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

  describe "#call" do
    it "soft-deletes the credit note" do
      result = delete_service.call

      expect(result).to be_success
      expect(result.credit_note).to be_deleted
      expect(credit_note.reload).to be_deleted
    end

    context "when credit note is nil" do
      let(:credit_note) { nil }

      it "returns a not found failure" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("credit_note")
      end
    end

    context "when credit note is not a draft" do
      let(:credit_note) { create(:credit_note, status: :finalized, invoice:, customer:) }

      it "returns a not allowed failure and keeps the credit note" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("not_deletable")
        expect(credit_note.reload).to be_finalized
      end
    end
  end
end
