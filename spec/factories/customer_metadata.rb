# frozen_string_literal: true

FactoryBot.define do
  factory :customer_metadata, class: 'Metadata::CustomerMetadata' do
    customer

    key { 'lead_name' }
    value { 'John Doe' }
    display_in_invoice { true }
  end
end
