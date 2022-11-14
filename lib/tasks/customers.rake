# frozen_string_literal: true

namespace :customers do
  desc 'Generate Slug for Customers'
  task generate_slug: :environment do
    Customer.order(:created_at).find_each(&:save)
  end

  desc 'Set customer currency from active subscription'
  task populate_currency: :environment do
    Customer.where(currency: nil).find_each do |customer|
      currencies = customer.subscriptions.map { |s| s.plan.amount_currency }.uniq
      next if currencies.size > 1 || currencies.size.zero?

      customer.update!(currency: currencies.first)
    end
  end

  desc 'Set sync_with_provider field for existing customers'
  task populate_sync_with_provider: :environment do
    Organization.all.each do |org|
      next if org&.stripe_payment_provider&.create_customers.blank?

      org.customers.each do |customer|
        stripe_customer = customer&.stripe_customer

        next unless stripe_customer

        stripe_customer.sync_with_provider = true
        stripe_customer.save!
      end
    end
  end
end
