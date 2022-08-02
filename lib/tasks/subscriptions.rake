# frozen_string_literal: true

namespace :subscriptions do
  desc 'Fill missing unique_id'
  task fill_unique_id: :environment do
    Subscription.where(unique_id: nil).find_each do |sub|
      sub.update!(unique_id: SecureRandom.uuid)
    end
  end
end
