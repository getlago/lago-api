# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::VoidedService do
  subject(:webhook_invoice_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  before do
    create_list(:fee, 2, invoice:)
    create_list(:credit, 2, invoice:)
  end

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "builds payload with invoice.drafted webhook type" do
      webhook_invoice_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq("invoice.voided")
        expect(payload[:object_type]).to eq("invoice")
      end
    end
  end
end
