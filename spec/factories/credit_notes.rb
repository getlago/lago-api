# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note do
    customer
    invoice

    issuing_date { Time.zone.today }

    reason { 'duplicated_charge' }
    total_amount_cents { 120 }
    total_amount_currency { 'EUR' }
    taxes_amount_cents { 20 }

    credit_status { 'available' }
    credit_amount_cents { 120 }
    credit_amount_currency { 'EUR' }
    balance_amount_cents { 120 }
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

    trait :draft do
      status { :draft }
    end
  end
end
