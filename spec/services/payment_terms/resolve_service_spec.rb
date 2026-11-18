# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::ResolveService do
  subject(:result) { described_class.call(customer:) }

  let(:billing_entity) { build_stubbed(:billing_entity, payment_term: billing_entity_term) }
  let(:billing_entity_term) { nil }
  let(:customer) { build_stubbed(:customer, billing_entity:, payment_term: customer_term) }
  let(:customer_term) { nil }

  context "when a subscription with its own payment term is given" do
    subject(:result) { described_class.call(customer:, subscription:) }

    let(:subscription) { build_stubbed(:subscription, customer:, payment_term: subscription_term) }
    let(:subscription_term) { {term_type: "net", days: 60} }
    let(:customer_term) { {term_type: "net", days: 30} }

    it "returns the subscription term with source subscription" do
      expect(result).to be_success
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "net", days: 60))
      expect(result.source).to eq("subscription")
    end

    context "when the subscription has no payment term" do
      let(:subscription_term) { nil }

      it "falls back to the customer term" do
        expect(result).to be_success
        expect(result.payment_term).to eq(PaymentTerm.new(term_type: "net", days: 30))
        expect(result.source).to eq("customer")
      end
    end
  end

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

  context "when the issuing billing entity is given" do
    subject(:result) { described_class.call(customer:, billing_entity: other_billing_entity) }

    let(:billing_entity_term) { {term_type: "net", days: 30} }
    let(:other_billing_entity) { build_stubbed(:billing_entity, payment_term: {term_type: "end_of_month"}) }

    it "returns the term of the given billing entity" do
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "end_of_month"))
      expect(result.source).to eq("billing_entity")
    end
  end

  context "when the subscription is issued by another billing entity" do
    subject(:result) { described_class.call(customer:, subscription:) }

    let(:billing_entity_term) { {term_type: "net", days: 30} }
    let(:other_billing_entity) { build_stubbed(:billing_entity, payment_term: {term_type: "end_of_month"}) }
    let(:subscription) { build_stubbed(:subscription, customer:, billing_entity: other_billing_entity) }

    it "returns the term of the subscription's billing entity" do
      expect(result.payment_term).to eq(PaymentTerm.new(term_type: "end_of_month"))
      expect(result.source).to eq("billing_entity")
    end

    context "when the issuing billing entity is given" do
      subject(:result) { described_class.call(customer:, subscription:, billing_entity:) }

      it "returns the term of the given billing entity" do
        expect(result.payment_term).to eq(PaymentTerm.new(term_type: "net", days: 30))
        expect(result.source).to eq("billing_entity")
      end
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
