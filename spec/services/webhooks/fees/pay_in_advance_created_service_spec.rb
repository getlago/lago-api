# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Fees::PayInAdvanceCreatedService do
  subject(:webhook_service) { described_class.new(object: fee) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:charge) do
    create(:standard_charge, properties: {
      "amount" => "100",
      "presentation_group_keys" => [{"value" => "department", "options" => {"display_in_invoice" => true}}]
    })
  end
  let(:fee) { create(:charge_fee, charge:, subscription:, presentation_breakdowns: [build(:presentation_breakdown)]) }

  describe ".call" do
    it_behaves_like "creates webhook", "fee.created", "fee", {"amount_cents" => Integer, "presentation_breakdowns" => [{"presentation_by" => {"department" => "engineering"}, "units" => "60.0"}]}

    it "keeps the v1 payload for a legacy fee" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload["fee"]
      expect(payload).to eq(JSON.parse(V1::FeeSerializer.new(fee, root_name: "fee").to_json)["fee"])
      expect(payload).to include("lago_id" => fee.id, "lago_subscription_id" => subscription.id)
    end

    context "with a product fee" do
      let(:contract) { create(:contract, organization:, customer:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
      let(:fee) do
        create(
          :fee,
          organization:,
          billing_entity: customer.billing_entity,
          invoice: nil,
          subscription: nil,
          fee_type: :product,
          invoiceable: contract_rate_card.rate_card.product,
          contract:,
          contract_rate_card:,
          rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
          pay_in_advance: true,
          pay_in_advance_event_transaction_id: "tx_1"
        )
      end

      before { create(:fee_applied_tax, fee:) }

      it "sends the v2 payload of the event fee with its tax lines" do
        webhook_service.call

        payload = Webhook.order(created_at: :desc).first.payload["fee"]
        expect(payload).to eq(JSON.parse(V2::FeeSerializer.new(fee, root_name: "fee", includes: %i[applied_taxes]).to_json)["fee"])
        expect(payload["applied_taxes"].map { it["lago_fee_id"] }).to eq([fee.id])
        expect(payload).to include(
          "lago_id" => fee.id,
          "lago_invoice_id" => nil,
          "external_customer_id" => customer.external_id,
          "external_contract_id" => contract.external_id,
          "billing_timing" => "advance",
          "event_transaction_id" => "tx_1"
        )
      end
    end
  end
end
