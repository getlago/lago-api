# frozen_string_literal: true

require "rails_helper"

describe "Regenerate From Voided Invoice Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000, pay_in_advance: true) }

  let(:subscription) do
    travel_to(DateTime.new(2023, 1, 1)) do
      create_subscription(
        external_customer_id: customer.external_id,
        external_id: "sub_#{customer.external_id}",
        plan_code: plan.code
      )
    end

    customer.reload.subscriptions.first
  end

  let(:original_invoice) do
    travel_to(DateTime.new(2023, 1, 15)) { perform_billing }
    invoice = subscription.invoices.first
    invoice.update!(status: :voided)
    invoice
  end

  let(:original_fee) { original_invoice.fees.first }

  describe "#call" do
    it "regenerates invoice with adjusted display name, units and unit amount" do
      result = Invoices::RegenerateFromVoidedService.new(
        voided_invoice: original_invoice,
        fees_params: [
          {
            id: original_fee.id,
            subscription_id: subscription.id,
            invoice_display_name: "new-dis-name",
            units: 10,
            unit_amount_cents: 50.50
          }
        ]
      ).call

      regenerated_fee = result.invoice.fees.first
      expect(regenerated_fee.invoice_display_name).to eq "new-dis-name"
      expect(regenerated_fee.units).to eq 10
      expect(regenerated_fee.unit_amount_cents).to eq 5050
      expect(regenerated_fee.amount_cents).to eq 10 * 5050
    end

    it "regenerates invoice with only updated units" do
      result = Invoices::RegenerateFromVoidedService.new(
        voided_invoice: original_invoice,
        fees_params: [
          {
            id: original_fee.id,
            subscription_id: subscription.id,
            units: 3
          }
        ]
      ).call

      regenerated_fee = result.invoice.fees.first
      expect(regenerated_fee.invoice_display_name).to eq nil
      expect(regenerated_fee.units).to eq 3
      expect(regenerated_fee.unit_amount_cents).to eq original_fee.unit_amount_cents
      expect(regenerated_fee.amount_cents).to eq 3 * original_fee.unit_amount_cents
    end
  end
end
