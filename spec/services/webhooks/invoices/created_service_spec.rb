# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::CreatedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }

  before_all do
    create_default(:billable_metric)
    create_default(:plan)
  end

  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:charge) do
    create(:standard_charge, properties: {
      "amount" => "100",
      "presentation_group_keys" => [{"value" => "department", "options" => {"display_in_invoice" => true}}]
    })
  end

  before do
    create(:charge_fee, charge:, invoice:, presentation_breakdowns: [build(:presentation_breakdown)])
    create_list(:fee, 3, invoice:)
    create_list(:credit, 4, invoice:)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.created", "invoice", {"fees" => Array, "credits" => Array}
    it_behaves_like "sends the catalog invoice on v2"

    it "includes presentation_breakdowns in fees" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      fees = webhook.payload["invoice"]["fees"]

      expect(fees).to include(
        hash_including(
          "presentation_breakdowns" => [
            hash_including("presentation_by" => {"department" => "engineering"}, "units" => "60.0")
          ]
        ),
        hash_including("presentation_breakdowns" => [])
      )
    end

    context "when a progressive billing credit was applied to a charge fee" do
      let(:credited_fee) do
        create(:charge_fee, charge:, invoice:, precise_coupons_amount_cents: 2000, progressive_billing_credit_amount_cents: 1500)
      end

      before { credited_fee }

      it "includes progressive_billing_credit_amount_cents in fees" do
        webhook_service.call

        webhook = Webhook.order(created_at: :desc).first
        fees = webhook.payload["invoice"]["fees"]

        expect(fees.to_h { [it["lago_id"], it["progressive_billing_credit_amount_cents"]] })
          .to eq(invoice.fees.to_h { [it.id, (it.id == credited_fee.id) ? 1500 : 0] })
      end
    end
  end
end
