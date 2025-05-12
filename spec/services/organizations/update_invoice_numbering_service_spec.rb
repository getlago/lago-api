# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::UpdateInvoiceNumberingService, type: :service do
  subject(:update_service) { described_class.new(organization:, document_numbering:) }

  let(:organization) { create(:organization, document_numbering: "per_customer") }
  let(:document_numbering) { "per_organization" }

  describe "#call" do
    it "updates the organization's document_numbering" do
      result = update_service.call

      expect(result).to be_success
      expect(result.organization).to be_per_organization
    end

    context "when document_numbering is not changing" do
      let(:document_numbering) { "per_customer" }

      it "returns early without making changes" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization).to be_per_customer
      end
    end

    context "when changing from per_organization to per_customer" do
      let(:organization) { create(:organization, document_numbering: "per_organization") }
      let(:document_numbering) { "per_customer" }

      it "updates the organization's document_numbering without other changes" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization).to be_per_customer
      end
    end
  end
end
