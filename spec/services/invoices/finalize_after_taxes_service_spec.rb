# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizeAfterTaxesService do
  describe "#call" do
    let(:invoice) { create(:invoice) }
    let(:service) { described_class.new(invoice:) }

    context "when invoice is not found" do
      before { allow(Invoice).to receive(:find).and_return(nil) }

      it "returns not found failure" do
        result = service.call

        expect(result).to be_a_failure
        expect(result).to have_attributes(not_found: true)
      end
    end

    context "when invoice is found" do
      before { allow(Invoice).to receive(:find).and_return(invoice) }

      it "calls the PullTaxesAndApplyService" do
        expect(Invoices::ProviderTaxes::PullTaxesAndApplyService).to receive(:call).with(invoice:)

        service.call
      end
    end
  end
end
