# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceSettlement do
  subject(:invoice_settlement) { build(:invoice_settlement) }

  describe "enums" do
    it do
      expect(subject)
        .to define_enum_for(:settlement_type)
        .with_values(payment: "payment", credit_note: "credit_note")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:billing_entity)
      expect(subject).to belong_to(:target_invoice).class_name("Invoice")
      expect(subject).to belong_to(:source_payment).class_name("Payment").optional
      expect(subject).to belong_to(:source_credit_note).class_name("CreditNote").optional
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_numericality_of(:amount_cents).is_greater_than(0)
      expect(subject).to validate_inclusion_of(:amount_currency).in_array(described_class.currency_list)
      expect(subject).to validate_presence_of(:settlement_type)
    end
  end
end
