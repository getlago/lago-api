FactoryBot.define do
  factory :fixed_charge do
    organization { plan&.organization || association(:organization) }
    plan
    add_on
    invoice_display_name { Faker::Fantasy::Tolkien.location }
    units { 1 }
    pay_in_advance { false }

    trait :standard do
      charge_model { "standard" }
      properties do
        {}
      end
    end

    trait :graduated do
      charge_model { "graduated" }
      properties do
        {
          graduated_ranges: [
            {from_value: 0, to_value: 10, per_unit_amount: "2", flat_amount: "1"},
            {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "0"}
          ]
        }
      end
    end

    trait :pay_in_advance do
      pay_in_advance { true }
    end

    trait :prorated do
      prorated { true }
    end
  end
end
