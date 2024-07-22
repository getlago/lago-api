# frozen_string_literal: true

FactoryBot.define do
  factory :integration_error_detail do
    association :owner, factory: %i[invoice].sample
    association :error_producer, factory: :anrok_integration
  end
end
