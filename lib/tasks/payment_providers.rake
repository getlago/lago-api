# frozen_string_literal: true

namespace :payment_providers do
  desc 'Generate code'
  task generate_code: :environment do
    PaymentProviders::BaseProvider.find_each do |payment_provider|
    end
  end
end