# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note do
    customer
    invoice

    status { 'available' }
    reason { 'overpaid' }
    amount_cents { 100 }
    amount_currency { 'EUR' }

    remaining_amount_cents { 100 }
    remaining_amount_currency { 'EUR' }

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
