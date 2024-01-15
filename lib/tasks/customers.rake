# frozen_string_literal: true

namespace :customers do
  desc 'Generate Slug for Customers'
  task generate_slug: :environment do
    Customer.unscoped.order(:created_at).find_each(&:save)
  end

  desc 'Set customer currency from active subscription'
  task populate_currency: :environment do
    Customer.where(currency: nil).find_each do |customer|
      currencies = customer.subscriptions.map { |s| s.plan.amount_currency }.uniq
      next if currencies.size > 1 || currencies.empty?

      customer.update!(currency: currencies.first)
    end
  end
end
