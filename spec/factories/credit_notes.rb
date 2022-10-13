# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note do
    customer
    invoice

    reason { 'duplicated_charge' }
    total_amount_cents { 100 }
    total_amount_currency { 'EUR' }

    credit_status { 'available' }
    credit_amount_cents { 100 }
    credit_amount_currency { 'EUR' }
    balance_amount_cents { 100 }
    balance_amount_currency { 'EUR' }

    trait :with_file do
      after(:build) do |credit_note|
        credit_note.file.attach(
          io: File.open(Rails.root.join('spec/fixtures/blank.pdf')),
          filename: 'blank.pdf',
          content_type: 'application/pdf',
        )
      end
    end
  end
end
