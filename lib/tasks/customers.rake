# frozen_string_literal: true

namespace :customers do
  desc 'Generate Slug for Customers'
  task generate_slug: :environment do
    Customer.order(:created_at).find_each(&:save)
  end

  desc 'Set customer currency from active subscription'
  task populate_currency: :environment do
    Customer.where(currency: nil).find_each do |customer|
      subscription = customer.active_subscription
      next unless subscription

      customer.update!(currency: subscription.plan.amount_currency)
    end
  end
end
