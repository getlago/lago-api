# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V2::Invoices::PaymentDisputeLostSerializer do
  subject(:serializer) { described_class.new(invoice, options) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }
  let_it_be(:invoice) { create_default(:invoice, :dispute_lost, invoice_type: :contract) }

  context "when options are present" do
    let(:options) do
      {
        "provider_error" => {
          "error_message" => "message",
          "error_code" => "code"
        }
      }.with_indifferent_access
    end

    it "serializes the v2 invoice with the provider error" do
      result = JSON.parse(serializer.to_json)

      expect(result["data"]["invoice"]).to include("lago_id" => invoice.id, "invoice_type" => "contract", "contracts" => [], "applied_taxes" => [])
      expect(result["data"]["invoice"]).not_to include("fees", "customer")
      expect(result["data"]["invoice"]).not_to have_key("subscriptions")
      expect(result["data"]["provider_error"]).to eq(options[:provider_error])
    end
  end

  context "when options are not present" do
    let(:options) do
      {}
    end

    it "serializes the v2 invoice without a provider error" do
      result = JSON.parse(serializer.to_json)

      expect(result["data"]["invoice"]).to include("lago_id" => invoice.id, "invoice_type" => "contract")
      expect(result["data"].key?("provider_error")).to eq(false)
    end
  end
end
