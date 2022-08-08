# frozen_string_literal: true

namespace :subscriptions do
  desc 'Fill missing unique_id'
  task fill_unique_id: :environment do
    Subscription.includes(:customer).find_each do |subscription|
      subscription.update!(unique_id: subscription.customer.customer_id)
    end
  end
end
