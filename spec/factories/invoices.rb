# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    customer
    organization

    issuing_date { Time.zone.now - 1.day }
    payment_due_date { issuing_date }
    payment_status { 'pending' }
    currency { 'EUR' }

    organization_sequential_id { rand(1_000_000) }

    trait :with_file do
      after(:build) do |model|
        model.file.attach(
          io: File.open(Rails.root.join('spec/fixtures/blank.pdf')),
          filename: 'blank.pdf',
          content_type: 'application/pdf',
        )
      end
    end

    trait :draft do
      status { :draft }
    end

    trait :credit do
      invoice_type { :credit }
    end

    trait :dispute_lost do
      payment_dispute_lost_at { DateTime.current - 1.day }
    end
  end
end
