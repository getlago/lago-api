# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::ResolveService do
  subject(:result) { described_class.call(customer:) }

  let(:billing_entity) { build_stubbed(:billing_entity, payment_term: billing_entity_term) }
  let(:billing_entity_term) { nil }
  let(:customer) { build_stubbed(:customer, billing_entity:, payment_term: customer_term) }
  let(:customer_term) { nil }

  context "when the customer has a payment term" do
    let(:customer_term) { {term_type: "net", days: 45} }
    let(:billing_entity_term) { {term_type: "end_of_month"} }

    it "returns the customer term with source customer" do
      expect(result).to be_success
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "net", days: 45))
      expect(result.source).to eq("customer")
    end
  end

  context "when only the billing entity has a payment term" do
    let(:billing_entity_term) { {term_type: "day_of_month", day_of_month: 15} }

    it "returns the billing entity term with source billing_entity" do
      expect(result).to be_success
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "day_of_month", day_of_month: 15, month_offset: 1))
      expect(result.source).to eq("billing_entity")
    end
  end

  context "when no level has a payment term" do
    it "falls back to due_on_receipt with source default" do
      expect(result).to be_success
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "due_on_receipt"))
      expect(result.source).to eq("default")
    end
  end
end
