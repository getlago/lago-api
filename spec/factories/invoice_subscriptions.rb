# frozen_string_literal: true

FactoryBot.define do
  factory :invoice_subscription do
    subscription
    invoice

    source { :initial }
  end
end
