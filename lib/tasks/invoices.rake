# frozen_string_literal: true

namespace :invoices do
  desc 'Generate Number for Invoices'
  task generate_number: :environment do
    Invoice.order(:created_at).find_each(&:save)
  end
end
