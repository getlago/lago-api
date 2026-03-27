# frozen_string_literal: true

FactoryBot.define do
  factory :quote_owner do
    quote
    user
    organization_id { quote&.organization_id }
  end
end
