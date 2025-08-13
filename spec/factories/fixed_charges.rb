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

    trait :graduated do
      charge_model { "graduated" }
      properties do
        {
          graduated_ranges: [
            {from_value: 0, to_value: 10, per_unit_amount: "5", flat_amount: "200"},
            {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "300"}
          ]
        }
      end
    end

    trait :volume do
      charge_model { "volume" }
      properties do
        {
          volume_ranges: [
            {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "1"},
            {from_value: 101, to_value: nil, per_unit_amount: "1", flat_amount: "0"}
          ]
        }
      end
    end
  end
end
