# frozen_string_literal: true

FactoryBot.define do
  factory :fixed_charge do
    organization { add_on&.organization || plan&.organization || association(:organization) }
    plan
    add_on
    charge_model { "standard" }
    units { 1 }
    properties { {amount: Faker::Number.between(from: 100, to: 500).to_s} }
    invoice_display_name { Faker::Fantasy::Tolkien.location }
  end
end
