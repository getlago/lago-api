# frozen_string_literal: true

RSpec.configure do |config|
  config.before { BillingEngineMigrations::Lookup.expire! }
end
