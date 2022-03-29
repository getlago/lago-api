# frozen_string_literal: true

FactoryBot.define do
  factory :customer do
    organization
    name { Faker::TvShows::SiliconValley.character }
    customer_id { SecureRandom.uuid }
  end
end
