FactoryBot.define do
  factory :coupon do
    organization
    name { Faker::Name.name }
    code { Faker::Name.name.underscore }

    factory :free_days_coupon do
      coupon_type { 'free_days' }
      day_count { rand(30) }
    end

    factory :fixed_amount_coupon do
      coupon_type { 'fixed_amount' }
      amount_cents { 200 }
      amount_currency { 'EUR' }
    end
  end
end
