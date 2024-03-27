# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::OneOffCreatedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "builds payload with invoice.one_off_created webhook type" do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq("invoice.one_off_created")
        expect(payload[:object_type]).to eq("invoice")
      end
    end
  end
end
