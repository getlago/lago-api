FactoryBot.define do
  factory :applied_invoice_custom_section do
    invoice
    code { Faker::Lorem.words(number: 3).join('_') }
    display_name { Faker::Lorem.words(number: 3).join(' ') }
    details { 'These details are shown in the invoice' }
  end
end
