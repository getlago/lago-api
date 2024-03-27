# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Events::ValidationErrorsService do
  subject(:webhook_service) { described_class.new(object: organization, options:) }

  let(:organization) { create(:organization) }

  let(:options) do
    {
      errors: {
        invalid_code: [SecureRandom.uuid],
        missing_aggregation_property: [SecureRandom.uuid],
        missing_group_key: [SecureRandom.uuid]
      }
    }
  end

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "builds payload with events.errors webhook type" do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq("events.errors")
        expect(payload[:object_type]).to eq("events_errors")
        expect(payload["events_errors"]).to include(
          invalid_code: Array,
          missing_aggregation_property: Array,
          missing_group_key: Array
        )
      end
    end
  end
end
