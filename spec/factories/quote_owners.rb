# frozen_string_literal: true

FactoryBot.define do
  factory :quote_owner do
    organization
    quote
    user
  end
end
