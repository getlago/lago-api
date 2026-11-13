# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::SigningKeys::CreateService do
  subject(:result) { described_class.call(webhook_endpoint:) }

  # let, not let_it_be: the concurrency example commits its rows and empties the tables.
  let(:organization) { create(:organization) }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }

  describe "#call" do
    context "when the endpoint has no signing key" do
      it "creates one key with the endpoint's organization" do
        expect { result }.to change(WebhookEndpointSigningKey, :count).by(1)

        expect(result).to be_success
        expect(result.signing_key).to be_persisted
        expect(result.signing_key).to have_attributes(organization_id: organization.id, webhook_endpoint_id: webhook_endpoint.id)
        expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([result.signing_key.id])
      end
    end

    context "when the endpoint already has a signing key" do
      let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      before do
        signing_key
        # A key of another endpoint does not count.
        create(:webhook_endpoint_signing_key, webhook_endpoint: create(:webhook_endpoint, organization:))
      end

      it "returns the current key of the endpoint without creating another" do
        expect { result }.not_to change(WebhookEndpointSigningKey, :count)

        expect(result).to be_success
        expect(result.signing_key).to eq(signing_key)
      end
    end

    context "when the same endpoint gets a key from two transactions at once", transaction: false do
      it "creates a single key" do
        endpoint_id = webhook_endpoint.id # materialize on this connection before the threads read it
        created = Queue.new

        first = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ApplicationRecord.transaction do
              described_class.call!(webhook_endpoint: WebhookEndpoint.find(endpoint_id))
              created << true
              # Holds the endpoint lock with an uncommitted key while the second call runs.
              sleep 1
            end
          end
        end
        created.pop

        second = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call!(webhook_endpoint: WebhookEndpoint.find(endpoint_id))
          end
        end

        first.join
        second_key = second.value.signing_key

        expect(WebhookEndpointSigningKey.where(webhook_endpoint_id: endpoint_id).pluck(:id)).to eq([second_key.id])
      end
    end
  end
end
