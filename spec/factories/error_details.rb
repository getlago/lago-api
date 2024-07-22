# frozen_string_literal: true

FactoryBot.define do
  factory :error_detail do
    association :owner, factory: %i[invoice].sample
    association :integration, factory: :anrok_integration
  end
end
