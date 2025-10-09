# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Payments::Payloads::BasePayload do
  let(:payload) { described_class.new(integration:, payment:) }
  let(:payment) { create(:payment, payable: invoice) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  describe "#initialize" do
    it "assigns the payment" do
      expect(payload.instance_variable_get(:@payment)).to eq(payment)
    end
  end

  describe "#integration_customer" do
    subject(:method_call) { payload.__send__(:integration_customer) }

    before do
      integration_customer
      create(:hubspot_customer, customer:)
    end

    it "returns the first accounting kind integration customer" do
      expect(subject).to eq(integration_customer)
    end

    it "memoizes the integration customer" do
      subject
      expect(payload.instance_variable_get(:@integration_customer)).to eq(integration_customer)
    end
  end

  describe "#body" do
    let(:integration_invoice) { create(:integration_resource, syncable: invoice, integration:) }

    before { integration_invoice }

    it "returns correct body" do
      expect(payload.body).to eq(
        [
          {
            "invoice_id" => integration_invoice.external_id,
            "account_code" => nil,
            "date" => payment.created_at.utc.iso8601,
            "amount_cents" => payment.amount_cents
          }
        ]
      )
    end
  end
end
