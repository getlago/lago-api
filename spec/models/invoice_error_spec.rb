# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceError, type: :model do
  let(:invoice) { create(:invoice, :generating) }
  let(:result) { BaseService::Result.new }
  let(:error) { BaseService::ValidationFailure.new(result, messages: messages) }
  let(:messages) { ["message1", "message2"] }

  let(:error_with_backtrace) do
    error = OpenStruct.new
    error.backtrace = "backtrace"
    error
  end

  describe ".create_for" do
    it "does nothing if the invoice is nil" do
      expect(described_class.create_for(invoice: nil, error:)).to eq(nil)
    end

    it "creates an invoice error with the same id as the invoice" do
      invoice_error = described_class.create_for(invoice:, error:)
      expect(invoice_error.id).to eq(invoice.id)
    end

    it "stores the error in the error field" do
      invoice_error = described_class.create_for(invoice:, error:)
      expect(invoice_error.error).to eq(error.inspect.to_json)
    end

    it "stores the backtrace in the backtrace field" do
      invoice_error = described_class.create_for(invoice:, error: error_with_backtrace)
      expect(invoice_error.backtrace).to eq("backtrace")
    end

    it "stores the subscriptions in the subscriptions field" do
      invoice_error = described_class.create_for(invoice:, error:)
      expect(invoice_error.subscriptions).to eq("[]")
    end
  end
end
