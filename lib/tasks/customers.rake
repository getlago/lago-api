# frozen_string_literal: true

namespace :customers do
  desc 'Generate Slug for Customers'
  task generate_slug: :environment do
    Customer.order(:created_at).find_each(&:save)
  end
end
