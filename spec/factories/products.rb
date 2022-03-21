# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    name { Faker::TvShows::SiliconValley.app }
  end
end
