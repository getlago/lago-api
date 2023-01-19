# frozen_string_literal: true

FactoryBot.define do
  trait :discarded do
    deleted_at { Time.current }
  end
end
