# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Wallets::UpdatedService do
  subject(:webhook_service) { described_class.new(object: wallet) }

  let(:wallet) { create(:wallet, :with_purchase_order_number) }

  describe ".call" do
    it_behaves_like "creates webhook", "wallet.updated", "wallet", {
      "purchase_order_number" => "PO-123",
      "recurring_transaction_rules" => []
    }

    context "with a streaming destination" do
      before do
        create(:kinesis_destination, organization: wallet.organization)
        wallet.reload
      end

      it "partitions the stream by the customer external id" do
        webhook_service.call

        expect(StreamingDestinations::DeliverJob).to have_been_enqueued.with(
          destination: anything,
          payload: anything,
          partition_key: wallet.customer.external_id
        )
      end
    end
  end
end
