# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    BillingEngineMigrations::Lookup.expire!
    BillingEngineMigrations::MappedSubscriptions.expire!
  end
end
