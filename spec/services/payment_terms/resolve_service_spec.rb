# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::ResolveService do
  subject(:result) { described_class.call(customer:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }

  context "when the customer has a payment term" do
    before do
      customer.update!(payment_term: {term_type: "net", days: 45})
      billing_entity.update!(payment_term: {term_type: "end_of_month"})
    end

    it "returns the customer term with source customer" do
      expect(result).to be_success
      expect(result.payment_term).to be_a(PaymentTerm)
      expect(result.payment_term.term_type).to eq("net")
      expect(result.payment_term.days).to eq(45)
      expect(result.source).to eq("customer")
    end
  end

  context "when only the billing entity has a payment term" do
    before do
      billing_entity.update!(payment_term: {term_type: "day_of_month", day_of_month: 15})
    end

    it "returns the billing entity term with source billing_entity" do
      expect(result).to be_success
      expect(result.payment_term.term_type).to eq("day_of_month")
      expect(result.payment_term.day_of_month).to eq(15)
      expect(result.payment_term.month_offset).to eq(1)
      expect(result.source).to eq("billing_entity")
    end
  end

  context "when no level has a payment term" do
    it "falls back to due_on_receipt with source default" do
      expect(result).to be_success
      expect(result.payment_term.term_type).to eq("due_on_receipt")
      expect(result.source).to eq("default")
    end
  end
end
