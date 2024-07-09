# frozen_string_literal: true

guard :rspec, cmd: 'bundle exec rspec' do
  watch('spec/spec_helper.rb') { 'spec' }
  watch('config/routes.rb') { 'spec/routing' }
  watch('app/controllers/application_controller.rb') { 'spec/requests' }
  watch('app/services/integrations/aggregator/invoices/payloads/base_payload.rb') do
    'spec/services/integrations/aggregator/invoices/payloads'
  end
  watch('app/services/integrations/aggregator/credit_notes/payloads/base_payload.rb') do
    'spec/services/integrations/aggregator/credit_notes/payloads'
  end
  watch('app/services/integrations/aggregator/contacts/payloads/base_payload.rb') do
    'spec/services/integrations/aggregator/contacts/payloads'
  end
  watch('app/services/integrations/aggregator/payments/payloads/base_payload.rb') do
    'spec/services/integrations/aggregator/payments/payloads'
  end
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^app/(.+)\.rb$}) { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r{^lib/(.+)\.rb$}) { |m| "spec/lib/#{m[1]}_spec.rb" }
  watch(%r{^app/controllers/(.+)_(controller)\.rb$}) do |m|
    [
      "spec/#{m[2]}s/#{m[1]}_#{m[2]}_spec.rb",
      "spec/requests/#{m[1]}_controller_spec.rb"
    ]
  end
end
