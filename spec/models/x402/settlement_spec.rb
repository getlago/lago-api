# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Settlement do
  subject(:settlement) { build(:x402_settlement) }

  describe "enums" do
    it do
      expect(settlement).to define_enum_for(:kind).backed_by_column_of_type(:enum).validating
        .with_values(credit_purchase: "credit_purchase", invoice_payment: "invoice_payment")
      expect(settlement).to define_enum_for(:status).backed_by_column_of_type(:enum).validating
        .with_values(pending: "pending", settled: "settled", failed: "failed")
    end
  end

  describe "associations" do
    it do
      expect(settlement).to belong_to(:organization)
      expect(settlement).to belong_to(:x402_connection).class_name("X402::Connection")
      expect(settlement).to belong_to(:customer).optional
      expect(settlement).to belong_to(:subscription).optional
      expect(settlement).to belong_to(:wallet_transaction).optional
    end
  end
end
