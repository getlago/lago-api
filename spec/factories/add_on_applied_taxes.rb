# frozen_string_literal: true

FactoryBot.define do
  factory :add_on_applied_tax, class: 'AddOn::AppliedTax' do
    add_on
    tax
  end
end
