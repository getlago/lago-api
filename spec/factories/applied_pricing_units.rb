FactoryBot.define do
  factory :applied_pricing_unit do
    pricing_unit
    priceable { association(:charge) }
    organization
    conversion_rate { rand(1.0..10.0) }
  end
end
