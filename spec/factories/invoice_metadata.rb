# frozen_string_literal: true

FactoryBot.define do
  factory :invoice_metadata, class: "Metadata::InvoiceMetadata" do
    invoice

    key { "lead_name" }
    value { "John Doe" }
  end
end
