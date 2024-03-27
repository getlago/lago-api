# frozen_string_literal: true

FactoryBot.define do
  factory :invite do
    organization

    status { "pending" }
    email { Faker::Internet.email }
    token { SecureRandom.hex(20) }
  end
end
