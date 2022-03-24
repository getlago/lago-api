# frozen_string_literal: true

FactoryBot.define do
  factory :plan do
    name { Faker::TvShows::SiliconValley.app }
  end
end
