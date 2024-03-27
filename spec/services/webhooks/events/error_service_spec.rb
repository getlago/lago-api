# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Events::ErrorService do
  subject(:webhook_service) { described_class.new(object: event, options:) }

  let(:organization) { create(:organization) }
  let(:event) { create(:received_event, organization_id: organization.id) }
  let(:options) { {error: {transaction_id: ["value_already_exist"]}} }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "builds payload with event.error webhook type" do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq("event.error")
        expect(payload[:object_type]).to eq("event_error")
      end
    end
  end
end
