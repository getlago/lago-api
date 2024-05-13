# frozen_string_literal: true

FactoryBot.define do
  factory :group_property do
    association :charge, factory: :standard_charge
    group
    values do
      {amount: Faker::Number.between(from: 100, to: 500).to_s}
    end
    invoice_display_name { Faker::Fantasy::Tolkien.character }
  end
end
