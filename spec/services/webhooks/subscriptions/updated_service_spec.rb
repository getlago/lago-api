# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Subscriptions::UpdatedService do
  subject(:webhook_service) { described_class.new(object: subscription) }

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }

  describe ".call" do
    it_behaves_like "creates webhook", "subscription.updated", "subscription"

    context "with a streaming destination" do
      before do
        create(:kinesis_destination, organization: subscription.organization)
        subscription.reload
      end

      it "partitions the stream by the customer external id" do
        webhook_service.call

        expect(StreamingDestinations::DeliverJob).to have_been_enqueued.with(
          destination: anything,
          payload: anything,
          partition_key: subscription.customer.external_id
        )
      end
    end
  end
end
