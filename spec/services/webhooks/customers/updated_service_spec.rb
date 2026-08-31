# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Customers::UpdatedService do
  subject(:webhook_service) { described_class.new(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "customer.updated", "customer"

    context "with a streaming destination" do
      before do
        create(:kinesis_destination, organization: customer.organization)
        customer.reload
      end

      it "partitions the stream by the customer external id" do
        webhook_service.call

        expect(StreamingDestinations::DeliverJob).to have_been_enqueued.with(
          destination: anything,
          payload: anything,
          partition_key: customer.external_id
        )
      end
    end
  end
end
