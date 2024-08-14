# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::UsageThresholds::CheckService, type: :service do
  subject(:service) { described_class.new(lifetime_usage: lifetime_usage) }

  let(:lifetime_usage) { create(:lifetime_usage, subscription:, recalculate_current_usage:, recalculate_invoiced_usage:) }
  let(:recalculate_current_usage) { true }
  let(:recalculate_invoiced_usage) { true }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }
end
