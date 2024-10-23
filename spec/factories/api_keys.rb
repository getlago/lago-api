# frozen_string_literal: true

FactoryBot.define do
  factory :api_key do
    organization { association(:organization) }
  end
end
