# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract::AppliedInvoiceCustomSection do
  subject(:applied_invoice_custom_section) { build(:contract_applied_invoice_custom_section) }

  describe "associations" do
    it do
      expect(applied_invoice_custom_section).to belong_to(:organization)
      expect(applied_invoice_custom_section).to belong_to(:contract)
      expect(applied_invoice_custom_section).to belong_to(:invoice_custom_section)
    end
  end
end
