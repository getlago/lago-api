# frozen_string_literal: true

module StripeHelper
  def get_stripe_fixtures(file, version: ENV.fetch("STRIPE_API_VERSION", "2020-08-27"))
    File.read(Rails.root.join("spec/fixtures/stripe/#{version}/#{file}"))
  end
end
