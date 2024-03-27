# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::PaymentProviders::CustomerCheckoutService do
  subject(:webhook_service) { described_class.new(object: customer) }

  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "builds payload with customer.checkout_url_generated webhook type" do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq("customer.checkout_url_generated")
        expect(payload[:object_type]).to eq("payment_provider_customer_checkout_url")
      end
    end
  end
end
