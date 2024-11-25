FactoryBot.define do
  factory :invoice_custom_section do
    organization
    code { Faker::Lorem.words(number: 3).join('_') }
    display_name { Faker::Lorem.words(number: 3).join(' ') }
    details { 'These details are shown in the invoice' }
  end
end
