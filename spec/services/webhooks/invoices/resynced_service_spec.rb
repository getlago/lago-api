# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::ResyncedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.resynced", "invoice"
    it_behaves_like "sends the catalog invoice on v2"

    context "with a legacy invoice" do
      before { allow(V1::InvoiceSerializer).to receive(:new).and_call_original }

      it "calls the InvoiceSerializer with integration_customers included" do
        webhook_service.call

        expect(V1::InvoiceSerializer).to have_received(:new).with(
          invoice,
          root_name: "invoice",
          includes: array_including(:customer, :integration_customers, :subscriptions, :fees, :credits, :applied_taxes)
        )
      end
    end
  end
end
