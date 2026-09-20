# frozen_string_literal: true

FactoryBot.define do
  factory :contract_applied_invoice_custom_section, class: "Contract::AppliedInvoiceCustomSection" do
    contract
    organization { contract&.organization || association(:organization) }
    invoice_custom_section { association(:invoice_custom_section, organization:) }
  end
end
