# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnrichedEvent do
  subject { build(:enriched_event) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:customer) { create_default(:customer) }

  it { is_expected.to belong_to(:event) }

  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_presence_of(:timestamp) }
  it { is_expected.to validate_presence_of(:transaction_id) }
  it { is_expected.to validate_presence_of(:external_subscription_id) }
  it { is_expected.to validate_presence_of(:organization_id) }
  it { is_expected.to validate_presence_of(:subscription_id) }
  it { is_expected.to validate_presence_of(:plan_id) }
  it { is_expected.to validate_presence_of(:charge_id) }
  it { is_expected.to validate_presence_of(:enriched_at) }
end
